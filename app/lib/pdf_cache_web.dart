import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';


import 'package:web/web.dart' as web;

import 'pdf_cache_key.dart';

/// Web byte-snapshot store for opened PDFs, backed by IndexedDB.
///
/// The browser file picker hands back only bytes - no reusable path - so
/// without a store a web Recent entry could never reopen ("Pick again to
/// reopen"). We keep the opened bytes in IndexedDB (`localStorage` is ~5 MB,
/// synchronous and string-only; IndexedDB stores binary blobs) keyed by a
/// content hash, and reopening reads them straight back. One object store maps
/// the content hash to the raw `Uint8List`.
///
/// Every operation degrades to a miss on failure - a blocked or unavailable
/// IndexedDB (private-mode quotas, disabled storage) just leaves the Recent
/// entry non-reopenable, exactly as before, and never breaks the app.

/// Web keeps opened bytes in IndexedDB, so Recent entries reopen without a
/// fresh pick.
bool get canCacheRecentPdfs => true;

const String _dbName = 'dart_pdf_editor_app.recent_pdfs';
const String _storeName = 'pdfs';

/// Snapshots [bytes] into IndexedDB and returns the content-hash key, or null
/// when the store is unavailable or the write fails.
///
/// The key is a content key ([pdfContentKey]), so reopening or re-picking the
/// same document reuses one entry instead of piling up copies - and the same
/// bytes always map to the same Recent identity, matching the native
/// filesystem store.
///
/// The first `await` is load-bearing and must stay first. An `async` body runs
/// synchronously up to its initial await, so computing the key before one
/// would run it inside the caller's frame - and `unawaited(...)` at the call
/// site would not help, because that defers only the *future*, never the
/// synchronous prefix. Yielding first pushes the whole snapshot off the frame
/// that opened the document, which is the one the user is waiting on.
Future<String?> cacheOpenedPdf(Uint8List bytes) async {
  try {
    await null;
    final key = pdfContentKey(bytes);
    final store = await _store('readwrite');
    await _run<void>(store.put(bytes.toJS, key.toJS), (_) {});
    return key;
  } catch (_) {
    return null;
  }
}

/// Reads a snapshot back by its content-hash [cacheKey]. Throws when it's gone
/// or IndexedDB is unavailable - the web has no filesystem to fall back to, so
/// `readPdfAtPath` must not treat a miss as "read it off disk instead"; the
/// throw drops the stale Recent entry, exactly as a gone file does on native.
Future<Uint8List?> readCachedPdf(String cacheKey) async {
  final store = await _store('readonly');
  final bytes = await _run<Uint8List?>(store.get(cacheKey.toJS), (result) {
    if (result == null) return null;
    return (result as JSUint8Array).toDart;
  });
  if (bytes == null) throw StateError('No cached PDF for $cacheKey');
  return bytes;
}

/// Deletes snapshots no longer referenced by [keep] (the cache keys still held
/// by Recent entries), so the store can't grow without bound as entries roll
/// off the capped list.
Future<void> pruneCachedPdfs(Set<String> keep) async {
  try {
    final readStore = await _store('readonly');
    final keys = await _run<List<String>>(readStore.getAllKeys(), (result) {
      if (result == null) return const [];
      return [
        for (final key in (result as JSArray<JSAny?>).toDart)
          (key! as JSString).toDart,
      ];
    });
    for (final key in keys) {
      if (keep.contains(key)) continue;
      // A fresh transaction per delete: an IndexedDB transaction auto-commits
      // once it goes idle, so it would already be inactive if we reused one
      // read store across these awaited deletes.
      final store = await _store('readwrite');
      await _run<void>(store.delete(key.toJS), (_) {});
    }
  } catch (_) {
    // No writable store - nothing to prune.
  }
}

Future<web.IDBDatabase>? _db;

Future<web.IDBObjectStore> _store(String mode) async {
  final db = await (_db ??= _openEnsuringStore());
  return db.transaction(_storeName.toJS, mode).objectStore(_storeName);
}

/// Opens the database and guarantees the object store exists.
///
/// A brand-new database is created at version 1 and `onupgradeneeded` adds the
/// store. But if the database already exists *without* our store - e.g. a stray
/// `indexedDB.open(name)` with no upgrade handler, an interrupted first run -
/// reopening at the same version never fires `onupgradeneeded`, so every
/// transaction would throw "object store not found". We detect that and reopen
/// at the next version to add the store.
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

/// Wraps a single IDB request, mapping its result through [map] on success and
/// propagating its error otherwise.
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
