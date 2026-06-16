import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// One filter, every platform: desktop and web match on the extension,
/// Android on the MIME type, iOS/macOS on the uniform type identifier —
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

/// A PDF the user picked to open, or null when the dialog was cancelled.
class PickedPdf {
  const PickedPdf(this.name, this.bytes, {this.path});

  final String name;
  final Uint8List bytes;

  /// The on-disk path on desktop platforms (null on web/mobile, where the
  /// picker hands back a sandboxed copy). The origin for in-place save.
  final String? path;
}

/// Opens the system file picker for a PDF. Returns null when the user cancels.
Future<XFile?> pickPdfFile() =>
    openFile(acceptedTypeGroups: const [pdfTypeGroup]);

/// Opens the system file picker and reads the chosen PDF. Returns null when
/// the user cancels. Throws if the file can't be read — callers surface that.
Future<PickedPdf?> pickPdf() async {
  final file = await pickPdfFile();
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return PickedPdf(file.name, bytes, path: originPathForPickedFile(file));
}

/// The picked file's writable origin on desktop, or null on web/mobile where
/// the path is only a tmp/sandbox location.
String? originPathForPickedFile(XFile file) => (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux))
    ? file.path
    : null;

/// Picks a PDF and returns just its bytes (null when cancelled) — the source
/// for "Insert PDF…" and document comparison.
Future<Uint8List?> pickPdfBytes() async {
  final file = await openFile(acceptedTypeGroups: const [pdfTypeGroup]);
  return file?.readAsBytes();
}

/// Picks an image and returns its bytes — used by the form image picker and
/// the insert-image tool.
Future<Uint8List?> pickImageBytes() async {
  final file = await openFile(acceptedTypeGroups: const [imageTypeGroup]);
  return file?.readAsBytes();
}

/// Ensures [name] ends in `.pdf`, falling back to a default stem.
String ensurePdfName(String name) {
  var trimmed = name.trim();
  if (trimmed.isEmpty) trimmed = 'document';
  if (!trimmed.toLowerCase().endsWith('.pdf')) trimmed = '$trimmed.pdf';
  return trimmed;
}

/// The outcome of a save, with a message suitable for a toast (null = the
/// user cancelled, so say nothing).
class SaveResult {
  const SaveResult._(this.message, {this.path, this.succeeded = false});

  /// A user-visible confirmation, or null when the action was cancelled.
  final String? message;

  /// Where it landed on disk, when that's a stable writable path (desktop
  /// save dialog). Null for downloads / share-sheet / cancellation.
  final String? path;

  /// True when the document was actually written somewhere — the caller uses
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

/// Reads a PDF straight from a known on-disk [path] — used to reopen a recent
/// file. Throws if it can't be read (caller drops the stale recent entry).
Future<Uint8List> readPdfAtPath(String path) => XFile(path).readAsBytes();

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

/// Overwrites the file at [path] with [bytes] (in-place save). Uses
/// [XFile.saveTo] rather than dart:io so this file still compiles for web,
/// where [supportsInPlaceSave] is false and this is never called.
Future<SaveResult> saveBytesToPath(Uint8List bytes, String path) async {
  try {
    await XFile.fromData(bytes, mimeType: 'application/pdf').saveTo(path);
    return SaveResult.saved(path);
  } catch (e) {
    return SaveResult.failed(e);
  }
}

/// Save-as with whatever the platform offers: a save dialog on desktop, a
/// browser download on the web, the share sheet on phones and tablets (where
/// apps can't write outside their sandbox directly). The origin-aware
/// "Save in place" path is added in a later phase.
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
      try {
        await file.saveTo(location.path);
        return SaveResult.saved(location.path);
      } catch (e) {
        return SaveResult.failed(e);
      }
  }
}
