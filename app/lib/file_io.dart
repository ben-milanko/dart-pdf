import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pdf_bookmark_source.dart';
import 'pdf_cache.dart';
import 'pdf_file_source.dart';
import 'pdf_mobile_source.dart';
import 'web_file_picker_stub.dart'
    if (dart.library.js_interop) 'web_file_picker.dart';

const _macosFileAccessChannel =
    MethodChannel('dev.milanko.dartpdf/file_access');

/// One filter, every platform: desktop and web match on the extension,
/// Android on the MIME type, iOS/macOS on the uniform type identifier -
/// a type group missing the field a platform filters by throws there.
const pdfTypeGroup = XTypeGroup(
  label: 'PDF documents',
  extensions: ['pdf'],
  mimeTypes: ['application/pdf'],
  uniformTypeIdentifiers: ['com.adobe.pdf'],
);

/// Images accepted by the form tool's push-button fill and the image tool.
const imageTypeGroup = XTypeGroup(
  label: 'Images',
  extensions: ['png', 'jpg', 'jpeg'],
  mimeTypes: ['image/png', 'image/jpeg'],
  uniformTypeIdentifiers: ['public.png', 'public.jpeg'],
);

/// Custom stamp bundles exported from the Manage Stamps dialog.
const stampBundleTypeGroup = XTypeGroup(
  label: 'DartPDF stamps',
  extensions: ['json'],
  mimeTypes: ['application/json'],
  uniformTypeIdentifiers: ['public.json'],
);

const _stampBundleFormat = 'dev.milanko.dartpdf.custom-stamps';

/// A PDF the user picked to open, or null when the dialog was cancelled.
class PickedPdf {
  const PickedPdf(this.name, this.bytes, {this.path, this.bookmark});

  final String name;
  final Uint8List bytes;

  /// The on-disk path on desktop platforms (null on web/mobile, where the
  /// picker hands back a sandboxed copy). The origin for in-place save.
  final String? path;

  /// macOS security-scoped bookmark for [path], when available. Stored with
  /// recents/session entries so sandboxed folders can be reopened later.
  final String? bookmark;
}

/// A file the mobile reference picker handed back: a native [token] pointing at
/// the *original* file (not a sandbox copy), its display [name], the [length]
/// when the provider reports it, and whether the runner's up-front probe found
/// the reference [seekable] (so ranged reads are worth attempting - see #364).
class MobilePickedPdf {
  const MobilePickedPdf({
    required this.token,
    required this.name,
    this.length,
    required this.seekable,
  });

  /// Opaque native reference (Android persisted `content://` Uri; iOS
  /// security-scoped bookmark). Passed back to [pdfByteSourceForMobileToken].
  final String token;
  final String name;
  final int? length;

  /// Whether native ranged reads over [token] are random-access. False for a
  /// non-seekable pipe (many cloud providers), where the caller streams whole
  /// instead of opening progressively.
  final bool seekable;
}

/// Whether this platform can pick a mobile file *by reference* (Android/iOS,
/// off-web) and read ranges from it natively - the mobile counterpart of
/// [progressiveOpenSupported]. The OS pickers otherwise copy the whole file
/// into the sandbox before the app sees a byte, paying the full cloud transport
/// up front (#364); the reference picker keeps the original so ranged reads can
/// first-paint from a few MB. Whether ranged reads actually help depends on the
/// provider (a non-seekable SAF pipe streams whole) - probed per pick.
bool get supportsMobileProgressiveOpen =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Opens the reference-based mobile document picker and returns one entry per
/// chosen PDF (empty when cancelled). Each entry carries a native [token] to
/// the original file plus a seekability probe result. Throws
/// [MissingPluginException] on a runner without the channel, so callers can
/// fall back to the copy-based [pickPdfFiles].
Future<List<MobilePickedPdf>> pickPdfMobileReferences() async {
  final picked = await mobileFileChannel
      .invokeListMethod<Map<Object?, Object?>>('pickDocuments');
  if (picked == null) return const [];
  final out = <MobilePickedPdf>[];
  for (final entry in picked) {
    final token = entry['token'] as String?;
    if (token == null || token.isEmpty) continue;
    out.add(MobilePickedPdf(
      token: token,
      name: (entry['name'] as String?) ?? 'document.pdf',
      length: (entry['length'] as num?)?.toInt(),
      seekable: entry['seekable'] == true,
    ));
  }
  return out;
}

/// A ranged [PdfByteSource] over a mobile pick's native [token], so the app can
/// open it progressively via [PdfDocument.openSource] and stream the rest in
/// behind the first paint - the mobile counterpart of [pdfByteSourceForPath].
PdfByteSource pdfByteSourceForMobileToken(
  String token, {
  PdfCancelToken? cancelToken,
  void Function(int received, int? total)? onProgress,
}) =>
    PdfMobileByteSource(
      token,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );

/// Opens the system file picker for a PDF. Returns null when the user cancels.
///
/// On the web this reads the picked file's bytes directly (see [pickPdfFileWeb])
/// instead of going through `file_selector`, whose blob-URL XFiles hang on
/// `readAsBytes()` under the deployed site's cross-origin isolation.
Future<XFile?> pickPdfFile() => kIsWeb
    ? pickPdfFileWeb()
    : openFile(acceptedTypeGroups: const [pdfTypeGroup]);

/// Opens the system file picker for one or more PDFs. Returns an empty list
/// when the user cancels. On the web, reads the bytes eagerly (see
/// [pickPdfFilesWeb]) for the same reason as [pickPdfFile].
Future<List<XFile>> pickPdfFiles() => kIsWeb
    ? pickPdfFilesWeb()
    : openFiles(acceptedTypeGroups: const [pdfTypeGroup]);

/// Opens the system file picker and reads the chosen PDF. Returns null when
/// the user cancels. Throws if the file can't be read - callers surface that.
Future<PickedPdf?> pickPdf() async {
  final file = await pickPdfFile();
  if (file == null) return null;
  final path = originPathForPickedFile(file);
  final bytes = await file.readAsBytes();
  final bookmark = await securityBookmarkForPath(path);
  return PickedPdf(file.name, bytes, path: path, bookmark: bookmark);
}

/// The picked file's writable origin on desktop, or null on web/mobile where
/// the path is only a tmp/sandbox location.
String? originPathForPickedFile(XFile file) => (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux))
    ? file.path
    : null;

bool get _isMacOSDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// Creates a security-scoped bookmark for [path] on macOS.
///
/// Returns null on other platforms, when [path] is absent, or when the native
/// side cannot create a bookmark. Callers still keep the path and fall back to
/// normal `XFile` I/O, preserving the old behavior.
Future<String?> securityBookmarkForPath(String? path) async {
  if (!_isMacOSDesktop || path == null || path.isEmpty) return null;
  try {
    final data = await _macosFileAccessChannel.invokeMethod<Uint8List>(
      'bookmarkForPath',
      {'path': path},
    );
    return data == null || data.isEmpty ? null : base64Encode(data);
  } on MissingPluginException {
    return null;
  } catch (_) {
    return null;
  }
}

/// Picks a PDF and returns just its bytes (null when cancelled) - the source
/// for "Insert PDF…" and document comparison.
Future<Uint8List?> pickPdfBytes() async {
  final file = await openFile(acceptedTypeGroups: const [pdfTypeGroup]);
  return file?.readAsBytes();
}

/// Picks an image and returns its bytes - used by the form image picker and
/// the insert-image tool.
Future<Uint8List?> pickImageBytes() async {
  final file = await openFile(acceptedTypeGroups: const [imageTypeGroup]);
  return file?.readAsBytes();
}

/// Encodes custom stamps as a portable JSON bundle.
String encodeCustomStampBundle(List<PdfCustomStamp> stamps) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert({
    'format': _stampBundleFormat,
    'version': 1,
    'stamps': [
      for (final stamp in stamps) jsonDecode(stamp.encode()),
    ],
  });
}

/// Decodes a custom stamp JSON bundle.
///
/// Accepts the current `{stamps: [...]}` bundle shape and a plain JSON list
/// for easier recovery from manually-edited exports.
List<PdfCustomStamp> decodeCustomStampBundle(String source) {
  final decoded = jsonDecode(source);
  final rawStamps = switch (decoded) {
    {'stamps': final List stamps} => stamps,
    final List stamps => stamps,
    _ => throw const FormatException('Stamp bundle has no stamps list'),
  };
  return List.unmodifiable([
    for (final raw in rawStamps) _decodeCustomStampEntry(raw),
  ]);
}

PdfCustomStamp _decodeCustomStampEntry(Object? raw) {
  final stamp = switch (raw) {
    String json => PdfCustomStamp.decode(json),
    Map<String, dynamic> map => PdfCustomStamp.decode(jsonEncode(map)),
    Map map => PdfCustomStamp.decode(jsonEncode(map)),
    _ => null,
  };
  if (stamp == null) throw const FormatException('Invalid stamp entry');
  return stamp;
}

/// Opens a JSON stamp bundle and returns the stamps inside it.
Future<List<PdfCustomStamp>?> importCustomStamps() async {
  final file = await openFile(acceptedTypeGroups: const [stampBundleTypeGroup]);
  if (file == null) return null;
  return decodeCustomStampBundle(utf8.decode(await file.readAsBytes()));
}

/// Ensures [name] ends in `.pdf`, falling back to a default stem.
String ensurePdfName(String name) {
  var trimmed = name.trim();
  if (trimmed.isEmpty) trimmed = 'document';
  return ensurePdfExtension(trimmed);
}

/// Appends `.pdf` to [path] unless it already ends with it (case-insensitive).
/// The desktop save dialog lets the user clear or change the extension, so the
/// path it hands back can lack one - exported and saved files must still open
/// as PDFs.
String ensurePdfExtension(String path) =>
    path.toLowerCase().endsWith('.pdf') ? path : '$path.pdf';

/// Appends `.json` to [path] unless it already ends with it
/// (case-insensitive).
String ensureJsonExtension(String path) =>
    path.toLowerCase().endsWith('.json') ? path : '$path.json';

/// The outcome of a save, with a message suitable for a toast (null = the
/// user cancelled, so say nothing).
class SaveResult {
  const SaveResult._(this.message, {this.path, this.succeeded = false});

  /// A user-visible confirmation, or null when the action was cancelled.
  final String? message;

  /// Where it landed on disk, when that's a stable writable path (desktop
  /// save dialog). Null for downloads / share-sheet / cancellation.
  final String? path;

  /// True when the document was actually written somewhere - the caller uses
  /// this to clear the dirty state and record a recent file.
  final bool succeeded;

  static const cancelled = SaveResult._(null);
  factory SaveResult.saved(String path) =>
      SaveResult._('Saved to $path', path: path, succeeded: true);
  factory SaveResult.downloaded(String name) =>
      SaveResult._('Downloaded $name', succeeded: true);
  factory SaveResult.shared() => const SaveResult._('Shared', succeeded: true);
  factory SaveResult.failed(Object error) =>
      SaveResult._('Save failed: $error');
}

/// Reads a PDF straight from a known on-disk [path] - used to reopen a recent
/// file. Throws if it can't be read (caller drops the stale recent entry).
///
/// On macOS, [bookmark] reactivates the user's original security-scoped access
/// before reading. This is required for sandboxed locations such as OneDrive's
/// CloudStorage folder after an app restart.
Future<Uint8List> readPdfAtPath(String path, {String? bookmark}) async {
  // The byte-snapshot store gets first refusal. On the web a recent/session
  // entry is an IndexedDB blob keyed under [path] and there's no filesystem to
  // fall back to, so the web store returns the bytes (or throws on a miss, which
  // drops the stale entry). Native keeps its snapshot as a real file, so its
  // store declines here (returns null) and we read [path] off disk below.
  final cached = await readCachedPdf(path);
  if (cached != null) return cached;
  if (_isMacOSDesktop && bookmark != null && bookmark.isNotEmpty) {
    try {
      final bytes = await _macosFileAccessChannel.invokeMethod<Uint8List>(
        'readFile',
        {'path': path, 'bookmark': bookmark},
      );
      if (bytes != null) return bytes;
    } catch (_) {
      // Fall through to the generic path read below.
    }
  }
  return XFile(path).readAsBytes();
}

/// Whether opening [path] progressively (first paint from ranged reads, full
/// bytes streamed in behind it) is worthwhile on this platform. Desktop only:
/// the big cloud-synced documents this pays off for live behind a real file
/// path, and web/mobile picks hand back bytes (or a throwaway sandbox copy)
/// that are already fully in memory.
bool progressiveOpenSupported(String? path) =>
    supportsInPlaceSave && path != null && path.isNotEmpty;

/// A ranged [PdfByteSource] for a local file, so the app can open it
/// progressively via [PdfDocument.openSource] and stream the rest in behind the
/// first paint. On sandboxed macOS a bookmarked reopen must reactivate its
/// security scope, so it reads through the native runner
/// ([PdfBookmarkFileByteSource]); every other desktop path reads directly with
/// a `RandomAccessFile` ([PdfFileByteSource]).
PdfByteSource pdfByteSourceForPath(
  String path, {
  String? bookmark,
  PdfCancelToken? cancelToken,
  void Function(int received, int? total)? onProgress,
}) {
  if (_isMacOSDesktop && bookmark != null && bookmark.isNotEmpty) {
    return PdfBookmarkFileByteSource(
      bookmark: bookmark,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  }
  return PdfFileByteSource(
    path,
    cancelToken: cancelToken,
    onProgress: onProgress,
  );
}

/// Whether the current platform can open a local file's containing folder in
/// the system file manager. Desktop only: mobile/web origins are either absent
/// or not meaningful outside the app sandbox.
bool get supportsOpenContainingFolder => supportsInPlaceSave;

/// User-facing label for the tab context-menu action that opens a tab's source
/// folder in the platform file manager.
String get openContainingFolderLabel {
  if (defaultTargetPlatform == TargetPlatform.macOS) return 'Open in Finder';
  if (defaultTargetPlatform == TargetPlatform.windows) {
    return 'Open in File Explorer';
  }
  return 'Open containing folder';
}

/// Returns the parent directory for a platform path without importing dart:io
/// (this library must keep compiling for web). Handles both POSIX and Windows
/// separators, plus simple roots like `/` and `C:\`.
String? containingFolderPath(String path) {
  var trimmed = path.trim();
  if (trimmed.isEmpty) return null;
  while (
      trimmed.length > 1 && (trimmed.endsWith('/') || trimmed.endsWith(r'\'))) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  final slash = trimmed.lastIndexOf('/');
  final backslash = trimmed.lastIndexOf(r'\');
  final index = slash > backslash ? slash : backslash;
  if (index < 0) return null;
  if (index == 0) return trimmed.substring(0, 1);
  // Preserve `C:\` as the parent of `C:\file.pdf`.
  if (index == 2 && trimmed.length > 1 && trimmed[1] == ':') {
    return trimmed.substring(0, 3);
  }
  return trimmed.substring(0, index);
}

/// Opens [path]'s containing folder in Finder / File Explorer / the Linux file
/// manager. Returns false when there is no usable origin path or the platform
/// refuses to launch it.
Future<bool> openContainingFolder(String? path) async {
  if (!supportsOpenContainingFolder || path == null) return false;
  final folder = containingFolderPath(path);
  if (folder == null) return false;
  return launchUrl(Uri.file(folder), mode: LaunchMode.externalApplication);
}

/// Whether the current platform supports overwriting a file in place by path.
/// Desktop only: web has no filesystem, and mobile content URIs are typically
/// read-only, so those save-as instead.
bool get supportsInPlaceSave =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Overwrites the file at [path] with [bytes] (in-place save).
///
/// On macOS, [bookmark] reactivates the security-scoped origin before writing.
/// Other platforms use [XFile.saveTo] rather than dart:io so this file still
/// compiles for web, where [supportsInPlaceSave] is false and this is never
/// called.
Future<SaveResult> saveBytesToPath(
  Uint8List bytes,
  String path, {
  String? bookmark,
}) async {
  try {
    if (_isMacOSDesktop && bookmark != null && bookmark.isNotEmpty) {
      try {
        final ok = await _macosFileAccessChannel.invokeMethod<bool>(
          'writeFile',
          {'path': path, 'bookmark': bookmark, 'bytes': bytes},
        );
        if (ok == true) return SaveResult.saved(path);
      } catch (_) {
        // Fall through to the generic path write below.
      }
    }
    await XFile.fromData(bytes, mimeType: 'application/pdf').saveTo(path);
    return SaveResult.saved(path);
  } catch (e) {
    return SaveResult.failed(e);
  }
}

/// Save-as with whatever the platform offers: a save dialog on desktop, a
/// browser download on the web, the share sheet on phones and tablets (where
/// apps can't write outside their sandbox directly).
Future<SaveResult> saveBytesAs(
  BuildContext context,
  Uint8List bytes,
  String suggestedName,
) async {
  final name = ensurePdfName(suggestedName);
  final file = XFile.fromData(bytes, mimeType: 'application/pdf', name: name);

  if (kIsWeb) {
    await file.saveTo(name);
    return SaveResult.downloaded(name);
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android || TargetPlatform.iOS:
      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      await SharePlus.instance.share(ShareParams(
        files: [file],
        fileNameOverrides: [name],
        // required on iPad: the share popover anchors to this rect
        sharePositionOrigin: origin ?? const Rect.fromLTWH(0, 0, 1, 1),
      ));
      return SaveResult.shared();
    default:
      final location = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const [pdfTypeGroup],
      );
      if (location == null) return SaveResult.cancelled;
      // The dialog returns the path verbatim - if the user cleared or changed
      // the extension, force `.pdf` so the file still opens as a PDF.
      final path = ensurePdfExtension(location.path);
      try {
        await file.saveTo(path);
        return SaveResult.saved(path);
      } catch (e) {
        return SaveResult.failed(e);
      }
  }
}

/// Exports user-managed custom stamps as a portable JSON bundle.
Future<SaveResult> exportCustomStampsAs(
  BuildContext context,
  List<PdfCustomStamp> stamps,
) =>
    saveJsonAs(context, encodeCustomStampBundle(stamps), 'dartpdf-stamps.json');

/// Save-as for a JSON document, with the same platform behaviour as
/// [saveBytesAs]: a save dialog on desktop, a browser download on the web,
/// the share sheet on phones. [name] should carry `.json`.
Future<SaveResult> saveJsonAs(
  BuildContext context,
  String json,
  String name,
) async {
  final bytes = Uint8List.fromList(utf8.encode(json));
  final file = XFile.fromData(
    bytes,
    mimeType: 'application/json',
    name: name,
  );

  if (kIsWeb) {
    await file.saveTo(name);
    return SaveResult.downloaded(name);
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android || TargetPlatform.iOS:
      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      await SharePlus.instance.share(ShareParams(
        files: [file],
        fileNameOverrides: [name],
        sharePositionOrigin: origin ?? const Rect.fromLTWH(0, 0, 1, 1),
      ));
      return SaveResult.shared();
    default:
      final location = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const [stampBundleTypeGroup],
      );
      if (location == null) return SaveResult.cancelled;
      final path = ensureJsonExtension(location.path);
      try {
        await file.saveTo(path);
        return SaveResult.saved(path);
      } catch (e) {
        return SaveResult.failed(e);
      }
  }
}

/// Save-as for a rasterized page image ([bytes], PNG or JPEG per [mimeType]),
/// using the same platform behaviour as [saveBytesAs]: a save dialog on
/// desktop, a browser download on the web, the share sheet on phones. [name]
/// is the suggested filename (with extension).
Future<SaveResult> saveImageBytesAs(
  BuildContext context,
  Uint8List bytes,
  String name,
  String mimeType,
) async {
  final file = XFile.fromData(bytes, mimeType: mimeType, name: name);

  if (kIsWeb) {
    await file.saveTo(name);
    return SaveResult.downloaded(name);
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android || TargetPlatform.iOS:
      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      await SharePlus.instance.share(ShareParams(
        files: [file],
        fileNameOverrides: [name],
        sharePositionOrigin: origin ?? const Rect.fromLTWH(0, 0, 1, 1),
      ));
      return SaveResult.shared();
    default:
      final location = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const [imageTypeGroup],
      );
      if (location == null) return SaveResult.cancelled;
      try {
        await file.saveTo(location.path);
        return SaveResult.saved(location.path);
      } catch (e) {
        return SaveResult.failed(e);
      }
  }
}
