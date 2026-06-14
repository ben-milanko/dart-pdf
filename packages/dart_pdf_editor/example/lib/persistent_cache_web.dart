import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:web/web.dart' as web;

/// Web backend for the on-disk caches: an IndexedDB-backed
/// [PdfCacheStore], so page previews and extracted text persist across
/// browser sessions on the web exactly as the filesystem store does on
/// native — `localStorage` is too small (~5 MB) and synchronous, whereas
/// IndexedDB stores binary blobs and is the right home for raster bytes.
///
/// One object store keyed by the cache key, values stored as binary
/// (`Uint8List`). Every operation wraps the callback-based IDB request in
/// a Future; failures surface as rejected Futures and [PdfDiskCache]
/// degrades them to cache misses, so a blocked/again-unavailable
/// IndexedDB never breaks the app.
PdfCacheStore createPersistentCacheStore() => _IndexedDbCacheStore();

const String _dbName = 'dart_pdf_editor_cache';
const String _storeName = 'entries';

class _IndexedDbCacheStore implements PdfCacheStore {
  Future<web.IDBDatabase>? _db;

  Future<web.IDBDatabase> _open() => _db ??= _openEnsuringStore();

  /// Opens the database and guarantees the object store exists.
  ///
  /// A brand-new database is created at version 1 and `onupgradeneeded`
  /// adds the store. But if the database already exists *without* our
  /// store — e.g. something opened it with no upgrade handler (a stray
  /// `indexedDB.open(name)` from the console, an interrupted first run) —
  /// reopening at the same version would never fire `onupgradeneeded`, so
  /// every transaction would throw "object store not found". We detect
  /// that and reopen at the next version to add the store.
  Future<web.IDBDatabase> _openEnsuringStore() async {
    var db = await _openAt(null);
    if (!db.objectStoreNames.contains(_storeName)) {
      final next = db.version + 1;
      db.close();
      db = await _openAt(next);
    }
    return db;
  }

  Future<web.IDBDatabase> _openAt(int? version) {
    final completer = Completer<web.IDBDatabase>();
    final request = version == null
        ? web.window.indexedDB.open(_dbName)
        : web.window.indexedDB.open(_dbName, version);
    request.onupgradeneeded = (web.Event _) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }.toJS;
    request.onsuccess = (web.Event _) {
      completer.complete(request.result as web.IDBDatabase);
    }.toJS;
    request.onerror = (web.Event _) {
      completer.completeError(
          StateError('IndexedDB open failed: ${request.error?.message}'));
    }.toJS;
    return completer.future;
  }

  /// Wraps a single IDB request, mapping its result through [map] on
  /// success and propagating its error otherwise.
  Future<T> _run<T>(web.IDBRequest request, T Function(JSAny?) map) {
    final completer = Completer<T>();
    request.onsuccess = (web.Event _) {
      completer.complete(map(request.result));
    }.toJS;
    request.onerror = (web.Event _) {
      completer.completeError(
          StateError('IndexedDB request failed: ${request.error?.message}'));
    }.toJS;
    return completer.future;
  }

  Future<web.IDBObjectStore> _store(String mode) async {
    final db = await _open();
    return db.transaction(_storeName.toJS, mode).objectStore(_storeName);
  }

  @override
  Future<Uint8List?> read(String key) async {
    final store = await _store('readonly');
    return _run<Uint8List?>(store.get(key.toJS), (result) {
      if (result == null) return null;
      return (result as JSUint8Array).toDart;
    });
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final store = await _store('readwrite');
    await _run<void>(store.put(bytes.toJS, key.toJS), (_) {});
  }

  @override
  Future<void> delete(String key) async {
    final store = await _store('readwrite');
    await _run<void>(store.delete(key.toJS), (_) {});
  }

  @override
  Future<List<String>> keys() async {
    final store = await _store('readonly');
    return _run<List<String>>(store.getAllKeys(), (result) {
      if (result == null) return const [];
      return [
        for (final key in (result as JSArray<JSAny?>).toDart)
          (key! as JSString).toDart,
      ];
    });
  }

  @override
  Future<void> clear() async {
    final store = await _store('readwrite');
    await _run<void>(store.clear(), (_) {});
  }
}
