import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'idb_web.dart';
import 'ocr_jobs.dart';

OcrJobStorage openOcrJobStorage() => _BrowserOcrJobStorage();

class _BrowserOcrJobStorage implements OcrJobStorage {
  Future<web.IDBDatabase>? _db;
  Future<web.IDBDatabase> get db =>
      _db ??= openIdb('dart_pdf_editor_app.ocr_jobs', const ['blobs']);

  @override
  Future<List<String>> keys() async {
    final tx = (await db).transaction('blobs'.toJS, 'readonly');
    return idbRequest(
        tx.objectStore('blobs').getAllKeys(),
        (value) => [
              for (final key in (value as JSArray<JSString>).toDart) key.toDart,
            ]);
  }

  @override
  Future<Uint8List?> read(String key) async {
    final tx = (await db).transaction('blobs'.toJS, 'readonly');
    return idbRequest(
        tx.objectStore('blobs').get(key.toJS),
        (value) => value == null || value.isUndefined
            ? null
            : (value as JSUint8Array).toDart);
  }

  Future<void> _mutate(void Function(web.IDBObjectStore) action) async {
    final tx = (await db).transaction('blobs'.toJS, 'readwrite');
    final done = Completer<void>();
    tx.oncomplete = (web.Event _) {
      done.complete();
    }.toJS;
    tx.onabort = (web.Event _) {
      done.completeError(StateError('OCR checkpoint transaction aborted'));
    }.toJS;
    tx.onerror = (web.Event _) {
      // onabort supplies the terminal failure, including quota exhaustion.
    }
        .toJS;
    action(tx.objectStore('blobs'));
    // A request's success is NOT a commit. Await the transaction itself before
    // advancing the page cursor or reporting that a job is safely staged.
    await done.future;
  }

  @override
  Future<void> write(String key, Uint8List bytes) => _mutate((store) {
        store.put(bytes.toJS, key.toJS);
      });
  @override
  Future<void> remove(String key) => _mutate((store) {
        store.delete(key.toJS);
      });

  @override
  Future<OcrJobLease?> claim(String id) async {
    final acquired = Completer<OcrJobLease?>();
    final released = Completer<JSAny?>();
    // Web Locks are released on tab termination, and never expire just because
    // a background tab is frozen. Two tabs cannot resume the same job at once.
    unawaited(web.window.navigator.locks
        .request(
            'dartpdf-ocr-$id',
            web.LockOptions(ifAvailable: true),
            ((web.Lock? lock) {
              if (lock == null) {
                acquired.complete(null);
                return Future<JSAny?>.value(null).toJS;
              }
              acquired.complete(_BrowserLease(released));
              return released.future.toJS;
            }).toJS)
        .toDart
        .catchError((Object error) {
      if (!acquired.isCompleted) acquired.completeError(error);
      return null;
    }));
    return acquired.future;
  }
}

class _BrowserLease implements OcrJobLease {
  _BrowserLease(this.done);
  final Completer<JSAny?> done;
  @override
  Future<void> release() async {
    if (!done.isCompleted) done.complete(null);
  }
}
