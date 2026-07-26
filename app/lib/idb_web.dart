/// Small IndexedDB helpers shared by the web byte stores (pdf_cache_web.dart's
/// opened-document snapshots and unsaved_changes_store_web.dart's crash-recovery
/// mirror). IndexedDB is the only browser store that holds binary blobs of PDF
/// size - `localStorage` is ~5 MB, synchronous and string-only.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Opens [name] and guarantees every store in [stores] exists.
///
/// A brand-new database is created at version 1 and `onupgradeneeded` adds the
/// stores. But if the database already exists *without* one of them - e.g. a
/// stray `indexedDB.open(name)` with no upgrade handler, an interrupted first
/// run, or a version of the app that declared fewer stores - reopening at the
/// same version never fires `onupgradeneeded`, so every transaction against the
/// missing store would throw "object store not found". We detect that and
/// reopen at the next version to add it.
Future<web.IDBDatabase> openIdb(String name, List<String> stores) async {
  var db = await _openAt(name, stores, null);
  if (stores.every((s) => db.objectStoreNames.contains(s))) return db;
  final next = db.version + 1;
  db.close();
  return _openAt(name, stores, next);
}

Future<web.IDBDatabase> _openAt(String name, List<String> stores, int? version) {
  final completer = Completer<web.IDBDatabase>();
  final request = version == null
      ? web.window.indexedDB.open(name)
      : web.window.indexedDB.open(name, version);
  request.onupgradeneeded = (web.Event _) {
    final db = request.result as web.IDBDatabase;
    for (final store in stores) {
      if (!db.objectStoreNames.contains(store)) db.createObjectStore(store);
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
///
/// Requests must be *issued* while their transaction is still active - an
/// IndexedDB transaction auto-commits as soon as it goes idle, so awaiting one
/// request before issuing the next on the same transaction is what makes it
/// inactive. Issue them all, then await the futures together.
Future<T> idbRequest<T>(web.IDBRequest request, T Function(JSAny?) map) {
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
