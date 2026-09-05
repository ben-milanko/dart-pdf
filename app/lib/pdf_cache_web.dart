import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'idb_web.dart';
import 'pdf_cache_key.dart';
import 'pdf_cache_policy.dart';

bool get canCacheRecentPdfs => true;
bool get canManageCachedPdfs => true;

final _cache = WebPdfCache();

Future<String?> cacheOpenedPdf(Uint8List bytes) => _cache.put(bytes);
Future<Uint8List?> readCachedPdf(String key) => _cache.read(key);
Future<Set<String>?> pruneCachedPdfs(Set<String> keep) => _cache.prune(keep);
Future<PdfCacheUsage?> cachedPdfUsage() => _cache.usage();
Future<bool> clearCachedPdfs() => _cache.clear();

typedef PdfStorageEstimate = ({num? usage, num? quota});

Future<PdfStorageEstimate> _estimateStorage() async {
  final estimate = await web.window.navigator.storage.estimate().toDart;
  return (usage: estimate.usage, quota: estimate.quota);
}

/// Disposable PDF snapshots. Metadata and bytes change in one transaction, so
/// concurrent tabs cannot overspend the budget or leave orphaned byte records.
/// Limits and the estimate provider are injectable for real-browser tests.
class WebPdfCache {
  WebPdfCache({
    this.databaseName = 'dart_pdf_editor_app.recent_pdfs',
    this.maxBytes = pdfCacheMaxBytes,
    this.maxFileBytes = pdfCacheMaxFileBytes,
    Future<PdfStorageEstimate> Function()? estimateStorage,
  }) : _estimate = estimateStorage ?? _estimateStorage;

  final String databaseName;
  final int maxBytes;
  final int maxFileBytes;
  final Future<PdfStorageEstimate> Function() _estimate;
  Future<web.IDBDatabase>? _db;
  static const _pdfs = 'pdfs';
  static const _meta = 'metadata';

  Future<web.IDBDatabase> _database() async {
    try {
      final db = await (_db ??= openIdb(databaseName, const [_pdfs, _meta],
          onUpgrade: (_, transaction) {
        // Upgrade the old raw-byte store one PDF at a time: getAll() here
        // would clone the entire, potentially multi-GB legacy cache into RAM.
        final metadata = transaction.objectStore(_meta);
        final request = transaction.objectStore(_pdfs).openCursor();
        request.onsuccess = (web.Event _) {
          try {
            if (request.result == null) return;
            final cursor = request.result as web.IDBCursorWithValue;
            final key = (cursor.key as JSString).toDart;
            final size = (cursor.value as JSUint8Array).toDart.length;
            if (size > maxFileBytes || size > maxBytes) {
              cursor.delete();
              metadata.delete(cursor.key);
            } else {
              // Historical access times aren't available. Legacy snapshots are
              // oldest until first reopened; content keys and bytes stay intact.
              metadata.put(_Entry(key, size, 0).encode().toJS, cursor.key);
            }
            cursor.continue_();
          } catch (_) {
            transaction.abort();
          }
        }.toJS;
      }));
      db.onversionchange = (web.Event _) {
        db.close();
        _db = null;
      }.toJS;
      return db;
    } catch (_) {
      _db = null; // A transient open failure must not poison the next attempt.
      rethrow;
    }
  }

  /// Yields before hashing, preserving #438's open-frame latency fix. A skipped
  /// or failed snapshot is just a Recent that needs a fresh file pick.
  Future<String?> put(Uint8List bytes) async {
    await null;
    if (bytes.length > maxFileBytes || bytes.length > maxBytes) return null;
    try {
      final key = pdfContentKey(bytes);
      PdfStorageEstimate estimate;
      try {
        estimate = await _estimate();
      } catch (_) {
        estimate = (usage: null, quota: null);
      }
      return await _withEntries((transaction, entries) {
        final existing = entries.any((entry) => entry.key == key);
        if (!existing &&
            !pdfCacheFitsQuota(bytes.length,
                usage: estimate.usage, quota: estimate.quota)) {
          _trim(transaction, entries);
          return null;
        }
        final entry = _Entry(key, bytes.length, _nextAccess(entries));
        entries.removeWhere((entry) => entry.key == key);
        _trim(transaction, entries, reserve: bytes.length);
        transaction.objectStore(_meta).put(entry.encode().toJS, key.toJS);
        if (!existing) {
          transaction.objectStore(_pdfs).put(bytes.toJS, key.toJS);
        }
        return key;
      });
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> read(String key) async {
    final db = await _database();
    final bytes = await _transaction<Uint8List?>(db, (transaction, result) {
      final request = transaction.objectStore(_pdfs).get(key.toJS);
      request.onsuccess = (web.Event _) {
        try {
          final raw = request.result;
          if (raw == null) {
            result(null);
            return;
          }
          final bytes = (raw as JSUint8Array).toDart;
          final metadata = transaction.objectStore(_meta);
          final all = metadata.getAll();
          all.onsuccess = (web.Event _) {
            try {
              metadata.put(
                  _Entry(key, bytes.length, _nextAccess(_entries(all.result)))
                      .encode()
                      .toJS,
                  key.toJS);
              result(bytes);
            } catch (_) {
              transaction.abort();
            }
          }.toJS;
        } catch (_) {
          transaction.abort();
        }
      }.toJS;
    });
    if (bytes == null) throw StateError('No cached PDF for $key');
    return bytes;
  }

  /// Also enforces the byte limits on startup, including a legacy store that
  /// already exceeds them. Returns null on failure, never a false empty store.
  Future<Set<String>?> prune(Set<String> keep) async {
    try {
      return await _withEntries((transaction, entries) {
        for (final entry in entries.toList()) {
          if (!keep.contains(entry.key)) {
            _delete(transaction, entry.key);
            entries.remove(entry);
          }
        }
        _trim(transaction, entries);
        return entries.map((entry) => entry.key).toSet();
      });
    } catch (_) {
      return null;
    }
  }

  Future<PdfCacheUsage?> usage() async {
    try {
      return await _withEntries((transaction, entries) {
        _trim(transaction, entries);
        return PdfCacheUsage(
            entries.fold(0, (sum, entry) => sum + entry.size), entries.length);
      });
    } catch (_) {
      return null;
    }
  }

  Future<bool> clear() async {
    try {
      final db = await _database();
      await _transaction<void>(db, (transaction, result) {
        transaction.objectStore(_pdfs).clear();
        transaction.objectStore(_meta).clear();
        result(null);
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> close() async {
    (await _db)?.close();
    _db = null;
  }

  int _nextAccess(List<_Entry> entries) => entries.fold(
      DateTime.now().millisecondsSinceEpoch,
      (time, entry) => time > entry.used ? time : entry.used + 1);

  void _trim(web.IDBTransaction transaction, List<_Entry> entries,
      {int reserve = 0}) {
    entries.sort((a, b) {
      final order = a.used.compareTo(b.used);
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
    var total = entries.fold(reserve, (sum, entry) => sum + entry.size);
    for (final entry in entries.toList()) {
      if (entry.size > maxFileBytes || total > maxBytes) {
        _delete(transaction, entry.key);
        total -= entry.size;
        entries.remove(entry);
      }
    }
  }

  void _delete(web.IDBTransaction transaction, String key) {
    transaction.objectStore(_pdfs).delete(key.toJS);
    transaction.objectStore(_meta).delete(key.toJS);
  }

  Future<T> _withEntries<T>(
      T Function(web.IDBTransaction, List<_Entry>) edit) async {
    final db = await _database();
    return _transaction<T>(db, (transaction, result) {
      final request = transaction.objectStore(_meta).getAll();
      request.onsuccess = (web.Event _) {
        try {
          // Issue all dependent requests in the event callback, before the
          // transaction goes idle. An await here can auto-commit underneath us.
          result(edit(transaction, _entries(request.result)));
        } catch (_) {
          transaction.abort();
        }
      }.toJS;
    });
  }

  List<_Entry> _entries(JSAny? raw) => [
        for (final value in (raw as JSArray<JSString>).toDart)
          _Entry.decode(value.toDart),
      ];

  Future<T> _transaction<T>(web.IDBDatabase db,
      void Function(web.IDBTransaction, void Function(T)) start) {
    final done = Completer<T>();
    final transaction =
        db.transaction([_pdfs.toJS, _meta.toJS].toJS, 'readwrite');
    late T value;
    transaction.oncomplete = (web.Event _) {
      try {
        done.complete(value);
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    }.toJS;
    transaction.onabort = (web.Event _) {
      done.completeError(StateError('PDF cache transaction aborted: '
          '${transaction.error?.message}'));
    }.toJS;
    try {
      start(transaction, (result) {
        value = result;
      });
    } catch (_) {
      transaction.abort();
    }
    // Request success alone is insufficient: quota errors can abort at commit.
    return done.future;
  }
}

class _Entry {
  const _Entry(this.key, this.size, this.used);
  final String key;
  final int size;
  final int used;

  String encode() => jsonEncode([key, size, used]);
  factory _Entry.decode(String value) {
    final fields = jsonDecode(value) as List;
    return _Entry(fields[0] as String, fields[1] as int, fields[2] as int);
  }
}
