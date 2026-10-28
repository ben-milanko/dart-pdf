import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:pdf_document/pdf_document.dart';

import 'live_sync.dart';

/// Live sync on desktop: the sidecar is a hidden folder next to the PDF,
/// which whatever keeps that folder in step (the OneDrive, Google Drive,
/// iCloud or Dropbox client, or a network share) carries to everyone else.
/// Phones are left out for now - their documents arrive through providers
/// rather than as a folder the app may write beside.
LiveSyncBackend? get platformLiveSyncBackend =>
    Platform.isAndroid || Platform.isIOS ? null : const FolderLiveSyncBackend();

/// [LiveSyncBackend] over the local file system.
class FolderLiveSyncBackend extends LiveSyncBackend {
  const FolderLiveSyncBackend();

  /// The sidecar folder for the PDF at [pdfPath]:
  /// `<folder>/.<file name>.dartpdf-sync`.
  static Directory sidecarFor(String pdfPath) {
    final file = File(pdfPath);
    final name = file.uri.pathSegments.last;
    return Directory(
        '${file.parent.path}${Platform.pathSeparator}.$name.dartpdf-sync');
  }

  @override
  PdfSyncStore? storeFor(String path) {
    if (path.isEmpty || path.contains('://')) return null;
    return FolderSyncStore(sidecarFor(path));
  }

  @override
  String get deviceName {
    try {
      final host = Platform.localHostname;
      // macOS reports "Bens-MacBook-Pro.local"
      return host.endsWith('.local')
          ? host.substring(0, host.length - '.local'.length)
          : host;
    } catch (_) {
      return Platform.operatingSystem;
    }
  }

  /// A sandboxed Mac app holds only the file the user opened, not its
  /// folder. When the folder can't be written, ask the user to pick it in
  /// the open panel, which grants access for the rest of the session.
  @override
  Future<bool> requestFolderAccess(String path) async {
    if (!Platform.isMacOS) return true;
    final folder = File(path).parent;
    if (await _canWrite(folder)) return true;
    final picked = await getDirectoryPath(initialDirectory: folder.path);
    if (picked == null) return false;
    return _samePath(picked, folder.path) && await _canWrite(folder);
  }

  static bool _samePath(String a, String b) {
    String norm(String p) => p.endsWith('/') ? p.substring(0, p.length - 1) : p;
    return norm(a) == norm(b);
  }

  static Future<bool> _canWrite(Directory folder) async {
    final probe = File('${folder.path}${Platform.pathSeparator}'
        '.dartpdf-sync-probe-${Random().nextInt(1 << 30)}');
    try {
      await probe.writeAsBytes(const [0]);
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

/// A [PdfSyncStore] over one directory. Writes go to a temporary name first
/// and are renamed into place, so a reader - or a sync client uploading the
/// folder - never sees a half-written file under its final name. The
/// temporary names start with `~$`, which OneDrive does not upload.
class FolderSyncStore implements PdfSyncStore {
  FolderSyncStore(this.directory);

  final Directory directory;

  static const _tempPrefix = r'~$';

  File _file(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  @override
  Future<List<PdfSyncStoreEntry>> list() async {
    if (!await directory.exists()) return const [];
    final entries = <PdfSyncStoreEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.startsWith(_tempPrefix)) continue;
      try {
        entries.add(PdfSyncStoreEntry(name, await entity.lastModified()));
      } on FileSystemException {
        continue; // removed between list and stat
      }
    }
    return entries;
  }

  @override
  Future<Uint8List?> read(String name) async {
    try {
      return await _file(name).readAsBytes();
    } on FileSystemException {
      return null; // gone, or not downloaded yet: the caller retries
    }
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    await directory.create(recursive: true);
    final target = _file(name);
    final temp = _file('$_tempPrefix$name.${Random().nextInt(1 << 30)}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    try {
      await temp.rename(target.path);
    } on FileSystemException {
      // Windows refuses to rename over a file another process (a sync
      // client) holds open for a moment; replace it and try once more.
      try {
        if (await target.exists()) await target.delete();
        await temp.rename(target.path);
      } on FileSystemException {
        await temp.delete().catchError((_) => temp);
        rethrow;
      }
    }
  }

  @override
  Future<void> delete(String name) async {
    try {
      await _file(name).delete();
    } on FileSystemException {
      // already gone
    }
  }
}
