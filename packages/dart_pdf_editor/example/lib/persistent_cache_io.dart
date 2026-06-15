import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

/// Native filesystem-backed [PdfCacheStore]: one file per key under a
/// stable cache directory, so the on-disk preview cache survives app
/// restarts.
///
/// The directory lives under the system temp root so the example needs no
/// extra dependency; a real app would point this at
/// `path_provider`'s `getApplicationCacheDirectory()` instead. Keys are
/// base64url-encoded into filenames (they contain `/`), and every
/// operation is wrapped so a filesystem hiccup degrades to a cache miss.
PdfCacheStore createPersistentCacheStore() => _FileCacheStore(
      Directory('${Directory.systemTemp.path}/dart_pdf_editor_cache'),
    );

class _FileCacheStore implements PdfCacheStore {
  _FileCacheStore(this._dir);

  final Directory _dir;
  bool _ensured = false;

  String _fileFor(String key) =>
      '${_dir.path}${Platform.pathSeparator}${base64Url.encode(utf8.encode(key))}';

  Future<void> _ensureDir() async {
    if (_ensured) return;
    if (!await _dir.exists()) await _dir.create(recursive: true);
    _ensured = true;
  }

  @override
  Future<Uint8List?> read(String key) async {
    final file = File(_fileFor(key));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    await _ensureDir();
    await File(_fileFor(key)).writeAsBytes(bytes, flush: false);
  }

  @override
  Future<void> delete(String key) async {
    final file = File(_fileFor(key));
    if (await file.exists()) await file.delete();
  }

  @override
  Future<List<String>> keys() async {
    if (!await _dir.exists()) return const [];
    final result = <String>[];
    await for (final entity in _dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      try {
        result.add(utf8.decode(base64Url.decode(name)));
      } catch (_) {
        // a stray file that isn't one of ours — ignore it
      }
    }
    return result;
  }

  @override
  Future<void> clear() async {
    if (await _dir.exists()) await _dir.delete(recursive: true);
    _ensured = false;
  }
}
