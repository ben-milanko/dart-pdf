import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'cache_store.dart';

/// A stable content key for a PDF (or any byte payload), suitable as a
/// cache namespace.
///
/// Hashes the byte length plus a scattering of sampled bytes with FNV-1a,
/// so it stays cheap on large CAD/scan files while still telling different
/// documents apart. Hosts that already have a stable identifier (a file
/// path, a URL, a database id) should prefer that — it survives trivial
/// re-saves that change the bytes but not the logical document.
String pdfContentKey(Uint8List bytes) {
  var hash = 0x811c9dc5;
  void mix(int byte) {
    hash ^= byte & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }

  final length = bytes.length;
  mix(length);
  mix(length >> 8);
  mix(length >> 16);
  mix(length >> 24);
  const sampleBudget = 4096;
  if (length <= sampleBudget) {
    for (final b in bytes) {
      mix(b);
    }
  } else {
    final stride = length ~/ sampleBudget;
    for (var i = 0; i < length; i += stride) {
      mix(bytes[i]);
    }
  }
  return hash.toRadixString(16);
}

/// A size-bounded, persistent LRU on top of a [PdfCacheStore].
///
/// This is the shared machinery every on-disk cache in the library sits
/// on — page rasters in `dart_pdf_editor`, extracted text in
/// `pdf_graphics`. It adds three things the bare store lacks:
///
///  * **Versioning.** A [version] tag is stored alongside the data; when
///    the running [version] differs (a serialization-format bump, a
///    renderer change that invalidates old rasters) the whole namespace
///    is purged on first use. Bump it whenever cached bytes could be
///    interpreted wrongly by new code.
///  * **A byte budget.** Total stored bytes are kept under [maxBytes] by
///    evicting least-recently-used entries — so a long-lived cache can't
///    grow without bound.
///  * **A persisted manifest.** The key → size table and LRU order live
///    in the store too (under a reserved key), so eviction decisions
///    survive across sessions instead of restarting cold every launch.
///
/// All work is serialized through an internal queue, so concurrent
/// [read]/[write] calls (the viewer fires many at once) can't corrupt the
/// manifest. Every operation is best-effort: a backend failure degrades
/// to a miss, never an exception out of the cache.
class PdfDiskCache {
  PdfDiskCache(
    this.store, {
    this.namespace = 'pdf',
    this.version = '1',
    this.maxBytes = 64 * 1024 * 1024,
  });

  /// Where bytes actually live (filesystem, IndexedDB, memory...).
  final PdfCacheStore store;

  /// Prefixes every stored key, so several caches can share one store.
  final String namespace;

  /// Cache-format generation; a mismatch purges the namespace (see class
  /// doc).
  final String version;

  /// Eviction ceiling on the total size of data entries (the manifest
  /// itself is not counted).
  final int maxBytes;

  // LinkedHashMap insertion order is the LRU order: a hit re-inserts at
  // the back, eviction takes the front (oldest).
  final Map<String, int> _sizes = <String, int>{};
  int _totalBytes = 0;

  bool _loaded = false;
  bool _manifestDirty = false;
  Future<void> _queue = Future<void>.value();

  // Manifest-flush coalescing. The manifest is O(entries), so rewriting it
  // on every write is O(n) per write and O(n^2) over a whole document — a
  // measurable cost on large CAD/scan files. Instead a burst of writes
  // flushes the manifest once, when the queue drains (`_pendingWrites`
  // hits 0), with a hard cap (`_flushBatchMax`) so a never-ending stream
  // still persists periodically. This is safe because the manifest only
  // has to survive to the next *cold* start; the in-memory `_sizes` table
  // is always current within a session, and `read` already tolerates a
  // stale manifest (a missing data key is forgotten on access).
  int _pendingWrites = 0;
  int _writesSinceFlush = 0;
  static const int _flushBatchMax = 64;

  // The version is NOT part of the key (it lives in the manifest), so a
  // version bump can physically reclaim the old bytes instead of orphaning
  // them under a stale prefix.
  String get _manifestKey => '$namespace/__manifest__';
  String _dataKey(String key) => '$namespace/d/$key';

  /// Resolves once the manifest has loaded (or failed to). Optional —
  /// every public method awaits it internally; exposed for tests and for
  /// hosts that want to front-load the read.
  Future<void> get ready => _run(() async {});

  /// The cached bytes for [key], or null on a miss. Counts as a use,
  /// moving [key] to the most-recently-used end.
  Future<Uint8List?> read(String key) => _run(() async {
        if (!_sizes.containsKey(key)) return null;
        final bytes = await _safeRead(_dataKey(key));
        if (bytes == null) {
          // The manifest and the store disagree (a partial write, an
          // external purge); forget the entry so we don't keep missing.
          _forget(key);
          return null;
        }
        // touch: re-insert at the back
        final size = _sizes.remove(key)!;
        _sizes[key] = size;
        return bytes;
      });

  /// Stores [bytes] under [key] (replacing any previous value) and evicts
  /// least-recently-used entries until the total fits [maxBytes].
  ///
  /// The manifest write is coalesced (see the `_pendingWrites` note): an
  /// isolated `await`ed write still persists immediately, but a burst —
  /// the viewer caching a whole document's previews at once — flushes the
  /// manifest just once when the burst drains.
  Future<void> write(String key, Uint8List bytes) {
    _pendingWrites++;
    return _run(() async {
      var changed = false;
      try {
        // An entry larger than the whole budget would force-evict
        // everything and still not fit — skip it rather than thrash.
        if (bytes.length > maxBytes) return;
        await _safeWrite(_dataKey(key), bytes);
        final previous = _sizes.remove(key);
        if (previous != null) _totalBytes -= previous;
        _sizes[key] = bytes.length;
        _totalBytes += bytes.length;
        _manifestDirty = true;
        changed = true;
        await _evictToBudget(keep: key);
      } finally {
        _pendingWrites--;
        if (changed) _writesSinceFlush++;
        // Flush once the burst drains, or after a capped batch so a
        // continuous stream still persists. `_flushManifest` no-ops when
        // nothing is dirty, so a flush here is free if this write skipped.
        if (_pendingWrites == 0 || _writesSinceFlush >= _flushBatchMax) {
          _writesSinceFlush = 0;
          await _flushManifest();
        }
      }
    });
  }

  /// Drops [key] from the cache.
  Future<void> remove(String key) => _run(() async {
        if (!_sizes.containsKey(key)) return;
        await _safeDelete(_dataKey(key));
        _forget(key);
        await _flushManifest();
      });

  /// Empties the entire namespace (data + manifest). Other namespaces
  /// sharing the store are untouched.
  Future<void> clear() => _run(() async {
        await _purgeNamespace();
        _sizes.clear();
        _totalBytes = 0;
        _manifestDirty = false;
        _writesSinceFlush = 0;
      });

  /// Persists any manifest changes deferred by write-coalescing right now.
  ///
  /// Writes settle their manifest on their own shortly after a burst ends,
  /// so this is optional; call it from an app-pause/close handler to
  /// guarantee the manifest survives a kill that lands mid-burst.
  Future<void> flush() => _run(() async {
        _writesSinceFlush = 0;
        await _flushManifest();
      });

  /// Number of cached entries (test hook).
  Future<int> get debugLength => _run(() async => _sizes.length);

  /// Total cached data bytes (test hook).
  Future<int> get debugBytes => _run(() async => _totalBytes);

  // --- internals -----------------------------------------------------

  /// Serializes [action] behind every earlier call and loads the manifest
  /// on the first one. A throw inside the cache never escapes — it logs
  /// nothing and falls back to the empty/miss result — but the queue keeps
  /// running for the next caller.
  Future<T> _run<T>(Future<T> Function() action) {
    final result = _queue.then((_) async {
      if (!_loaded) await _loadManifest();
      return action();
    });
    // Keep the chain alive regardless of this action's outcome.
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _loadManifest() async {
    _loaded = true;
    final raw = await _safeRead(_manifestKey);
    if (raw == null) return;
    try {
      final decoded = json.decode(utf8.decode(raw));
      if (decoded is! Map) return;
      if (decoded['version'] != version) {
        // Stale format: wipe everything we might misread.
        await _purgeNamespace();
        return;
      }
      final entries = decoded['entries'];
      if (entries is! List) return;
      for (final entry in entries) {
        if (entry is! List || entry.length != 2) continue;
        final key = entry[0];
        final size = entry[1];
        if (key is String && size is int && size >= 0) {
          _sizes[key] = size;
          _totalBytes += size;
        }
      }
    } catch (_) {
      // Corrupt manifest: start clean (the data keys age out via the
      // store's own clear paths or simply get overwritten).
      _sizes.clear();
      _totalBytes = 0;
    }
  }

  Future<void> _flushManifest() async {
    if (!_manifestDirty) return;
    final entries = [
      for (final entry in _sizes.entries) [entry.key, entry.value]
    ];
    final payload = utf8.encode(json.encode({
      'version': version,
      'entries': entries,
    }));
    await _safeWrite(_manifestKey, Uint8List.fromList(payload));
    _manifestDirty = false;
  }

  Future<void> _evictToBudget({String? keep}) async {
    while (_totalBytes > maxBytes && _sizes.length > 1) {
      // First key is the least-recently-used; never evict the entry we
      // just wrote even if it alone busts the budget (it ages out next).
      String? victim;
      for (final key in _sizes.keys) {
        if (key != keep) {
          victim = key;
          break;
        }
      }
      if (victim == null) break;
      await _safeDelete(_dataKey(victim));
      _forget(victim);
      _manifestDirty = true;
    }
  }

  void _forget(String key) {
    final size = _sizes.remove(key);
    if (size != null) {
      _totalBytes -= size;
      _manifestDirty = true;
    }
  }

  Future<void> _purgeNamespace() async {
    final prefix = '$namespace/';
    try {
      final all = await store.keys();
      for (final key in all) {
        if (key.startsWith(prefix)) await store.delete(key);
      }
    } catch (_) {
      // A store that can't enumerate still loses its manifest below, so
      // a fresh manifest simply won't reference the orphans.
    }
  }

  Future<Uint8List?> _safeRead(String key) async {
    try {
      return await store.read(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _safeWrite(String key, Uint8List bytes) async {
    try {
      await store.write(key, bytes);
    } catch (_) {}
  }

  Future<void> _safeDelete(String key) async {
    try {
      await store.delete(key);
    } catch (_) {}
  }
}
