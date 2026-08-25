import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'idb_web.dart';

const String _dbName = 'dart_pdf_editor_app.recent_thumbnails';
const String _storeName = 'thumbnails';

Future<Uint8List?> readStoredRecentThumbnail(String key) async {
  try {
    final store = await _store('readonly');
    return await idbRequest<Uint8List?>(store.get(key.toJS), (result) {
      if (result == null) return null;
      return (result as JSUint8Array).toDart;
    });
  } catch (_) {
    return null;
  }
}

Future<void> writeStoredRecentThumbnail(String key, Uint8List bytes) async {
  try {
    final store = await _store('readwrite');
    await idbRequest<void>(store.put(bytes.toJS, key.toJS), (_) {});
  } catch (_) {
    // Blocked/private storage only disables persistence for this thumbnail.
  }
}

Future<void> pruneStoredRecentThumbnails(Set<String> keep) async {
  try {
    final readStore = await _store('readonly');
    final keys = await idbRequest<List<String>>(
      readStore.getAllKeys(),
      (result) => result == null
          ? const []
          : [
              for (final key in (result as JSArray<JSAny?>).toDart)
                (key! as JSString).toDart,
            ],
    );
    for (final key in keys) {
      if (keep.contains(key)) continue;
      final store = await _store('readwrite');
      await idbRequest<void>(store.delete(key.toJS), (_) {});
    }
  } catch (_) {
    // No writable store - nothing to prune.
  }
}

Future<web.IDBDatabase>? _db;

Future<web.IDBObjectStore> _store(String mode) async {
  final db = await (_db ??= openIdb(_dbName, const [_storeName]));
  return db.transaction(_storeName.toJS, mode).objectStore(_storeName);
}
