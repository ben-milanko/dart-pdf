import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// A store that records calls and can be made to throw, to prove the
/// cache degrades to a miss rather than crashing.
class _FlakyStore implements PdfCacheStore {
  final PdfMemoryCacheStore _inner = PdfMemoryCacheStore();
  bool failReads = false;
  bool failWrites = false;
  int reads = 0;
  int writes = 0;

  @override
  Future<Uint8List?> read(String key) async {
    reads++;
    if (failReads) throw StateError('boom');
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    writes++;
    if (failWrites) throw StateError('boom');
    return _inner.write(key, bytes);
  }

  @override
  Future<void> delete(String key) => _inner.delete(key);

  @override
  Future<List<String>> keys() => _inner.keys();

  @override
  Future<void> clear() => _inner.clear();
}

void main() {
  group('pdfContentKey', () {
    test('is stable and distinguishes documents', () {
      final a = Uint8List.fromList(List.generate(10000, (i) => i % 256));
      final b = Uint8List.fromList(List.generate(10000, (i) => (i + 1) % 256));
      expect(pdfContentKey(a), pdfContentKey(a));
      expect(pdfContentKey(a), isNot(pdfContentKey(b)));
      // length alone changes the key
      expect(pdfContentKey(a), isNot(pdfContentKey(_bytes('short'))));
    });
  });

  group('PdfMemoryCacheStore', () {
    test('round-trips and copies the buffer', () async {
      final store = PdfMemoryCacheStore();
      final src = _bytes('hello');
      await store.write('k', src);
      src[0] = 0; // mutate caller buffer after write
      expect(await store.read('k'), _bytes('hello'));
      expect(await store.read('missing'), isNull);
      expect(store.debugLength, 1);
    });

    test('delete, keys, clear, and byte accounting', () async {
      final store = PdfMemoryCacheStore();
      await store.write('a', _bytes('one'));
      await store.write('b', _bytes('twelve')); // 6 bytes
      expect(store.debugBytes, _bytes('one').length + _bytes('twelve').length);
      expect((await store.keys())..sort(), ['a', 'b']);
      await store.delete('a');
      await store.delete('missing'); // no-op
      expect(await store.keys(), ['b']);
      await store.clear();
      expect(store.debugLength, 0);
      expect(await store.keys(), isEmpty);
    });
  });

  group('PdfDiskCache', () {
    test('reads back what it writes', () async {
      final cache = PdfDiskCache(PdfMemoryCacheStore());
      await cache.write('a', _bytes('alpha'));
      expect(await cache.read('a'), _bytes('alpha'));
      expect(await cache.read('absent'), isNull);
      expect(await cache.debugLength, 1);
    });

    test('evicts least-recently-used past the byte budget', () async {
      final cache = PdfDiskCache(PdfMemoryCacheStore(), maxBytes: 30);
      await cache.write('a', Uint8List(10));
      await cache.write('b', Uint8List(10));
      // touch a so b is now the oldest
      await cache.read('a');
      await cache.write('c', Uint8List(10)); // total 30, still fits
      await cache.write('d', Uint8List(10)); // total 40 -> evict oldest (b)
      expect(await cache.read('b'), isNull);
      expect(await cache.read('a'), isNotNull);
      expect(await cache.read('c'), isNotNull);
      expect(await cache.read('d'), isNotNull);
      expect(await cache.debugBytes, lessThanOrEqualTo(30));
    });

    test('an entry larger than the whole budget is not stored', () async {
      final cache = PdfDiskCache(PdfMemoryCacheStore(), maxBytes: 10);
      await cache.write('big', Uint8List(50));
      expect(await cache.read('big'), isNull);
      expect(await cache.debugLength, 0);
    });

    test('manifest (and entries) survive a new cache over the same store',
        () async {
      final store = PdfMemoryCacheStore();
      final first = PdfDiskCache(store);
      await first.write('keep', _bytes('value'));
      await first.write('also', _bytes('more'));

      final second = PdfDiskCache(store);
      expect(await second.read('keep'), _bytes('value'));
      expect(await second.debugLength, 2);
    });

    test('a version bump purges the old namespace', () async {
      final store = PdfMemoryCacheStore();
      await PdfDiskCache(store, version: '1').write('a', _bytes('v1'));

      final upgraded = PdfDiskCache(store, version: '2');
      expect(await upgraded.read('a'), isNull);
      expect(await upgraded.debugLength, 0);
      // the old data bytes are physically gone, not just shadowed
      final remaining = await store.keys();
      expect(remaining.any((k) => k.endsWith('/d/a')), isFalse);
    });

    test('namespaces are isolated within one store', () async {
      final store = PdfMemoryCacheStore();
      final rasters = PdfDiskCache(store, namespace: 'raster');
      final text = PdfDiskCache(store, namespace: 'text');
      await rasters.write('p0', _bytes('image'));
      await text.write('p0', _bytes('words'));
      expect(await rasters.read('p0'), _bytes('image'));
      expect(await text.read('p0'), _bytes('words'));
    });

    test('remove drops a single entry', () async {
      final store = PdfMemoryCacheStore();
      final cache = PdfDiskCache(store);
      await cache.write('a', _bytes('x'));
      await cache.write('b', _bytes('yy'));
      await cache.remove('a');
      await cache.remove('absent'); // no-op
      expect(await cache.read('a'), isNull);
      expect(await cache.read('b'), _bytes('yy'));
      expect(await cache.debugLength, 1);
      // the removal is durable: a fresh cache over the store agrees
      final reopened = PdfDiskCache(store);
      expect(await reopened.read('a'), isNull);
      expect(await reopened.read('b'), _bytes('yy'));
    });

    test('a corrupt manifest is recovered as an empty cache', () async {
      final store = PdfMemoryCacheStore();
      // write a manifest the loader can't parse
      await store.write('pdf/__manifest__', _bytes('not json at all'));
      final cache = PdfDiskCache(store);
      expect(await cache.debugLength, 0);
      // still usable afterwards
      await cache.write('a', _bytes('x'));
      expect(await cache.read('a'), _bytes('x'));
    });

    test('clear empties the namespace', () async {
      final store = PdfMemoryCacheStore();
      final cache = PdfDiskCache(store);
      await cache.write('a', _bytes('x'));
      await cache.clear();
      expect(await cache.read('a'), isNull);
      expect(await cache.debugLength, 0);
    });

    test('a manifest/store mismatch forgets the dangling entry', () async {
      final store = PdfMemoryCacheStore();
      final cache = PdfDiskCache(store);
      await cache.write('a', _bytes('x'));
      // simulate an external purge of the data key only
      for (final k in await store.keys()) {
        if (k.endsWith('/d/a')) await store.delete(k);
      }
      expect(await cache.read('a'), isNull);
      expect(await cache.debugLength, 0);
    });

    test('a throwing backend degrades to a miss, not a crash', () async {
      final store = _FlakyStore();
      final cache = PdfDiskCache(store);
      store.failWrites = true;
      await cache.write('a', _bytes('x')); // swallowed
      store.failWrites = false;
      store.failReads = true;
      expect(await cache.read('a'), isNull); // swallowed
      store.failReads = false;
      // the cache still works afterwards
      await cache.write('b', _bytes('y'));
      expect(await cache.read('b'), _bytes('y'));
    });

    test('concurrent writes do not corrupt the manifest', () async {
      final store = PdfMemoryCacheStore();
      final cache = PdfDiskCache(store);
      await Future.wait([
        for (var i = 0; i < 20; i++) cache.write('k$i', Uint8List(8)),
      ]);
      expect(await cache.debugLength, 20);
      // a fresh cache reads the same count back from the persisted manifest
      final reopened = PdfDiskCache(store);
      expect(await reopened.debugLength, 20);
    });

    test('a write burst coalesces into a single manifest flush', () async {
      final store = _FlakyStore(); // counts backend writes
      final cache = PdfDiskCache(store);
      const n = 100;
      await Future.wait([
        for (var i = 0; i < n; i++) cache.write('k$i', Uint8List(8)),
      ]);
      // n data writes; the manifest used to be rewritten once per write
      // (2n total). Coalesced, the burst flushes the manifest a handful of
      // times at most (the _flushBatchMax cap), never per-write.
      expect(store.writes, lessThan(n + 10),
          reason: 'manifest rewrite should not scale with the burst size');
      // ...and the persisted manifest is still complete and correct.
      final reopened = PdfDiskCache(store);
      expect(await reopened.debugLength, n);
      expect(await reopened.read('k0'), isNotNull);
      expect(await reopened.read('k${n - 1}'), isNotNull);
    });

    test('an isolated write persists its manifest immediately', () async {
      final store = PdfMemoryCacheStore();
      final cache = PdfDiskCache(store);
      await cache.write('solo', _bytes('x')); // no burst around it
      // a fresh cache sees it without any explicit flush()
      expect(await PdfDiskCache(store).read('solo'), _bytes('x'));
    });

    test('flush() forces a deferred manifest write', () async {
      final store = PdfMemoryCacheStore();
      final cache = PdfDiskCache(store);
      // Fire a burst without awaiting it, then flush explicitly.
      final burst = Future.wait([
        for (var i = 0; i < 50; i++) cache.write('k$i', Uint8List(8)),
      ]);
      await cache.flush();
      await burst;
      await cache.flush();
      expect(await PdfDiskCache(store).debugLength, 50);
    });
  });
}
