import 'dart:typed_data';

/// A pluggable key → bytes store backing the on-disk caches
/// ([PdfDiskCache] and everything layered on it).
///
/// The library never touches the filesystem itself: `dart:io` is banned
/// below the Flutter layer (so the COS, document, and graphics packages
/// keep running on the web and the Dart VM alike), and there is no single
/// persistent blob store that works on every platform without pulling in
/// a dependency. So persistence is a seam — exactly like [PdfOcrEngine],
/// [PdfImportSource], and the other host-provided interfaces. The host
/// supplies a backend (a `dart:io` directory on native, IndexedDB on the
/// web, a temp folder on a server) and the cache logic — keying,
/// versioning, byte-budget LRU eviction — lives on top in pure Dart.
///
/// Implementations may be slow (a real disk), so every method is async,
/// and callers treat the whole store as best-effort: a failed read or
/// write must degrade to recomputing, never crash. Keys are opaque
/// strings; [PdfDiskCache] namespaces and versions them, but a store is
/// free to hash or escape them for its filesystem.
abstract class PdfCacheStore {
  /// The bytes previously [write]-n under [key], or null when absent.
  /// Returning null (rather than throwing) is the miss signal.
  Future<Uint8List?> read(String key);

  /// Persists [bytes] under [key], replacing any previous value.
  Future<void> write(String key, Uint8List bytes);

  /// Removes [key] if present; a no-op otherwise.
  Future<void> delete(String key);

  /// Every key currently held. Used by [PdfDiskCache.clear] to purge a
  /// store whose manifest was lost, and by housekeeping.
  Future<List<String>> keys();

  /// Drops everything in the store.
  Future<void> clear();
}

/// An in-memory [PdfCacheStore] — the zero-dependency default that works
/// on every platform.
///
/// It is not persistent (it lives and dies with the process), so on its
/// own it only de-duplicates work within a single session. Its real jobs
/// are to give [PdfDiskCache] a usable out-of-the-box backend, to serve
/// as a deterministic test double, and to model the contract a real
/// (filesystem / IndexedDB) store must satisfy.
class PdfMemoryCacheStore implements PdfCacheStore {
  final Map<String, Uint8List> _entries = {};

  @override
  Future<Uint8List?> read(String key) async => _entries[key];

  @override
  Future<void> write(String key, Uint8List bytes) async {
    // Copy so a later mutation of the caller's buffer can't corrupt the
    // cached value (a real store serializes the bytes, so it can't either).
    _entries[key] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String key) async => _entries.remove(key);

  @override
  Future<List<String>> keys() async => _entries.keys.toList();

  @override
  Future<void> clear() async => _entries.clear();

  /// Number of entries held (test hook).
  int get debugLength => _entries.length;

  /// Total bytes held across all entries (test hook).
  int get debugBytes =>
      _entries.values.fold(0, (sum, bytes) => sum + bytes.length);
}
