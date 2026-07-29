// The persistent full-resolution raster tier (#615).
//
// Exact page rasters are memory-only unless a host wires
// `PdfRasterCache(fullRasters: ...)`. When it does, a completed render is
// encoded and stored asynchronously, and a later session reads it back at the
// same physical size instead of interpreting and rasterizing the page again.
//
// What these tests pin down is mostly what must NOT happen: every input that
// changes the baked pixels must be a miss, the big tier must not be able to
// evict the small preview/thumbnail tier, and corrupt or failing stores must
// degrade to an ordinary render.
//
// Harness note: PdfDiskCache serializes its work behind a Future created at
// construction, and a Future's continuations are scheduled in the zone the
// Future was created in. A cache built in the (fake-async) test body would
// therefore never make progress inside `tester.runAsync`, so every cache these
// tests `await` on is constructed inside the runAsync block.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A solid-colour image standing in for a rendered page raster.
Future<ui.Image> solidImage(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

/// A disk cache whose own methods throw, rather than a store whose failures
/// [PdfDiskCache] already swallows. This is the belt-and-braces path: a
/// backend that breaks its contract by throwing out of the Future itself.
class _ThrowingDiskCache extends PdfDiskCache {
  _ThrowingDiskCache()
      : super(PdfMemoryCacheStore(), namespace: 'page-rasters');

  @override
  Future<Uint8List?> read(String key) =>
      Future.error(StateError('read blew up'));

  @override
  Future<void> write(String key, Uint8List bytes) =>
      Future.error(StateError('write blew up'));
}

/// Wraps [payload] in the `PRAS` container header the cache writes, letting a
/// test forge a header that disagrees with its own body.
Uint8List frame(Uint8List payload,
    {required int width, required int height, int format = 0, int version = 1}) {
  final out = Uint8List(20 + payload.length);
  final header = ByteData.sublistView(out, 0, 20);
  header.setUint32(0, 0x50524153); // 'PRAS'
  header.setUint8(4, version);
  header.setUint8(5, format);
  header.setUint16(6, 0);
  header.setUint32(8, width);
  header.setUint32(12, height);
  header.setUint32(16, payload.length);
  out.setRange(20, out.length, payload);
  return out;
}

/// A store that fails every operation - the "storage quota is full" / "backend
/// threw" shape.
class _FailingStore implements PdfCacheStore {
  @override
  Future<Uint8List?> read(String key) async => throw StateError('read failed');

  @override
  Future<void> write(String key, Uint8List bytes) async =>
      throw StateError('write failed');

  @override
  Future<void> delete(String key) async => throw StateError('delete failed');

  @override
  Future<List<String>> keys() async => throw StateError('keys failed');

  @override
  Future<void> clear() async => throw StateError('clear failed');
}

PdfRasterCache _buildCache(
  PdfCacheStore store, {
  int fullBytes = 64 * 1024 * 1024,
  PdfRasterDiskFormat format = PdfRasterDiskFormat.png,
  String documentKey = 'doc-1',
}) =>
    PdfRasterCache(
      PdfDiskCache(store, namespace: 'previews'),
      fullRasters: PdfDiskCache(
        store,
        namespace: 'page-rasters',
        maxBytes: fullBytes,
      ),
      fullRasterFormat: format,
    ).forDocument(documentKey);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PdfRasterCache full-raster tier', () {
    testWidgets('is off until a host opts in', (tester) async {
      await tester.runAsync(() async {
        final store = PdfMemoryCacheStore();
        final withoutTier =
            PdfRasterCache(PdfDiskCache(store)).forDocument('d');
        expect(withoutTier.storesFullRasters, isFalse);

        final image = await solidImage(8, 8, const Color(0xFF102030));
        await withoutTier.storeFullRaster(0, image,
            pageColor: 0xFFFFFFFF, annotations: true, rotation: null);
        image.dispose();

        expect(store.debugLength, 0);
        expect(withoutTier.fullRasterStats.stores, 0);
        expect(withoutTier.fullRasterStats.rejects, 1);
      });
    });

    testWidgets('is off without a document key', (tester) async {
      await tester.runAsync(() async {
        final unbound = PdfRasterCache(
          PdfDiskCache(PdfMemoryCacheStore()),
          fullRasters: PdfDiskCache(PdfMemoryCacheStore()),
        );
        expect(unbound.storesFullRasters, isFalse);
        expect(
          await unbound.loadFullRaster(0,
              width: 8,
              height: 8,
              pageColor: 0xFFFFFFFF,
              annotations: true,
              rotation: null),
          isNull,
        );
      });
    });

    for (final format in PdfRasterDiskFormat.values) {
      testWidgets('round-trips an exact raster as ${format.name}',
          (tester) async {
        await tester.runAsync(() async {
          final cache = _buildCache(PdfMemoryCacheStore(), format: format);
          final image = await solidImage(37, 23, const Color(0xFF3355AA));
          await cache.storeFullRaster(4, image,
              pageColor: 0xFFFFFFFF, annotations: true, rotation: 90);
          image.dispose();

          final restored = await cache.loadFullRaster(4,
              width: 37,
              height: 23,
              pageColor: 0xFFFFFFFF,
              annotations: true,
              rotation: 90);
          expect(restored, isNotNull);
          expect(restored!.width, 37);
          expect(restored.height, 23);
          restored.dispose();

          final stats = cache.fullRasterStats;
          expect(stats.hits, 1);
          expect(stats.misses, 0);
          expect(stats.stores, 1);
          expect(stats.errors, 0);
          expect(stats.bytesWritten, greaterThan(0));
          expect(stats.bytesRead, greaterThan(0));

          // Latency diagnostics: totals accumulate and the means divide by the
          // right denominator (stores for encode, hits for decode).
          expect(stats.encodeMicros, greaterThan(0));
          expect(stats.decodeMicros, greaterThan(0));
          expect(stats.meanEncodeMicros, stats.encodeMicros / stats.stores);
          expect(stats.meanDecodeMicros, stats.decodeMicros / stats.hits);
          expect(stats.toString(), contains('hits=1'));

          stats.reset();
          expect(stats.hits, 0);
          expect(stats.misses, 0);
          expect(stats.stores, 0);
          expect(stats.rejects, 0);
          expect(stats.errors, 0);
          expect(stats.bytesRead, 0);
          expect(stats.bytesWritten, 0);
          expect(stats.encodeMicros, 0);
          expect(stats.decodeMicros, 0);
          // the means fall back to 0 rather than dividing by zero
          expect(stats.meanEncodeMicros, 0);
          expect(stats.meanDecodeMicros, 0);
        });
      });
    }

    testWidgets('every keyed input is a miss when it differs', (tester) async {
      await tester.runAsync(() async {
        final cache = _buildCache(PdfMemoryCacheStore());
        final image = await solidImage(20, 16, const Color(0xFF204060));
        await cache.storeFullRaster(2, image,
            pageColor: 0xFFFFFFFF,
            annotations: true,
            rotation: 0,
            revision: '0.0.0');
        image.dispose();

        Future<ui.Image?> load({
          int page = 2,
          int width = 20,
          int height = 16,
          int pageColor = 0xFFFFFFFF,
          bool annotations = true,
          int? rotation = 0,
          String revision = '0.0.0',
        }) =>
            cache.loadFullRaster(page,
                width: width,
                height: height,
                pageColor: pageColor,
                annotations: annotations,
                rotation: rotation,
                revision: revision);

        // the exact match hits...
        final hit = await load();
        expect(hit, isNotNull);
        hit!.dispose();

        // ...and everything else misses.
        expect(await load(page: 3), isNull, reason: 'page index');
        expect(await load(width: 21), isNull, reason: 'raster width');
        expect(await load(height: 17), isNull, reason: 'raster height');
        expect(await load(pageColor: 0xFF101010), isNull, reason: 'paper');
        expect(await load(annotations: false), isNull, reason: 'annotations');
        expect(await load(rotation: 90), isNull, reason: 'rotation');
        expect(await load(revision: '0.1.0'), isNull, reason: 'revision');

        // a different document is a different namespace
        final other = cache.forDocument('doc-2');
        expect(
          await other.loadFullRaster(2,
              width: 20,
              height: 16,
              pageColor: 0xFFFFFFFF,
              annotations: true,
              rotation: 0,
              revision: '0.0.0'),
          isNull,
          reason: 'document identity',
        );

        expect(cache.fullRasterStats.hits, 1);
        expect(cache.fullRasterStats.misses, 8);
      });
    });

    testWidgets('the key carries the renderer/format generation',
        (tester) async {
      // fullRasterVersion is part of the key, so a bump stops old entries
      // matching rather than letting new code decode them as if unchanged.
      final cache = _buildCache(PdfMemoryCacheStore());
      final key = cache.fullRasterKey(0,
          width: 10,
          height: 10,
          pageColor: 0xFFFFFFFF,
          annotations: true,
          rotation: null);
      expect(key, startsWith('doc-1/'));
      expect(key, contains('/f${PdfRasterCache.fullRasterVersion}/'));
      expect(key, contains('/10x10/'));
    });

    testWidgets('a corrupt payload is a miss, not a garbled page',
        (tester) async {
      await tester.runAsync(() async {
        final store = PdfMemoryCacheStore();
        final cache = _buildCache(store);
        final image = await solidImage(12, 9, const Color(0xFF808080));
        await cache.storeFullRaster(0, image,
            pageColor: 0xFFFFFFFF, annotations: true, rotation: null);
        image.dispose();

        Future<ui.Image?> load() => cache.loadFullRaster(0,
            width: 12,
            height: 9,
            pageColor: 0xFFFFFFFF,
            annotations: true,
            rotation: null);

        final original = await cache.readFullRasterBytes(0,
            width: 12, height: 9);
        expect(original, isNotNull, reason: 'the raw-bytes hook reads back');

        // Rewrite the stored bytes behind the cache's back, exactly as a
        // half-written file or an interrupted IndexedDB transaction would.
        final keys = await store.keys();
        final payloadKey =
            keys.firstWhere((k) => k.startsWith('page-rasters/d/'));
        Future<void> poison(Uint8List bytes) => store.write(payloadKey, bytes);

        await poison(original!.sublist(0, 10));
        expect(await load(), isNull, reason: 'truncated below the header');

        await poison(Uint8List(original.length));
        expect(await load(), isNull, reason: 'wrong magic');

        // A well-formed header whose declared payload length disagrees with
        // the bytes present.
        await poison(frame(Uint8List(4), width: 12, height: 9)..[19] = 99);
        expect(await load(), isNull, reason: 'payload length disagrees');

        // A well-formed header wrapping a body that is not an image at all -
        // the decoder throws rather than returning null.
        await poison(frame(Uint8List.fromList(List.filled(64, 0x7f)),
            width: 12, height: 9));
        expect(await load(), isNull, reason: 'undecodable body');

        // The nastiest case: a valid PNG of the WRONG size behind a header
        // that claims the right one - i.e. the store handed back another
        // entry's bytes. The post-decode dimension check is the last guard
        // between that and a page drawn at the wrong size.
        final wrongSize = await solidImage(20, 10, const Color(0xFF223344));
        final wrongPng =
            await wrongSize.toByteData(format: ui.ImageByteFormat.png);
        wrongSize.dispose();
        await poison(frame(
            wrongPng!.buffer
                .asUint8List(wrongPng.offsetInBytes, wrongPng.lengthInBytes),
            width: 12,
            height: 9));
        expect(await load(), isNull, reason: 'decoded size disagrees');

        expect(cache.fullRasterStats.errors, 5);
        expect(cache.fullRasterStats.hits, 0);
      });
    });

    testWidgets('a disk cache that throws is caught, not propagated',
        (tester) async {
      // PdfDiskCache swallows backend failures itself, so this covers the
      // outer guard: a cache implementation that breaks that contract.
      await tester.runAsync(() async {
        final cache = PdfRasterCache(
          PdfDiskCache(PdfMemoryCacheStore()),
          fullRasters: _ThrowingDiskCache(),
        ).forDocument('doc-1');

        final image = await solidImage(8, 8, const Color(0xFF010203));
        await cache.storeFullRaster(0, image,
            pageColor: 0xFFFFFFFF, annotations: true, rotation: null);
        image.dispose();

        expect(
          await cache.loadFullRaster(0,
              width: 8,
              height: 8,
              pageColor: 0xFFFFFFFF,
              annotations: true,
              rotation: null),
          isNull,
        );
        // one error from the throwing write, one from the throwing read
        expect(cache.fullRasterStats.errors, 2);
        expect(cache.fullRasterStats.misses, 1);
        expect(cache.fullRasterStats.stores, 0);
      });
    });

    testWidgets('a throwing backend degrades to a miss', (tester) async {
      await tester.runAsync(() async {
        final cache = PdfRasterCache(
          PdfDiskCache(_FailingStore()),
          fullRasters: PdfDiskCache(_FailingStore(), namespace: 'page-rasters'),
        ).forDocument('doc-1');
        final image = await solidImage(8, 8, const Color(0xFF000000));
        // neither of these may throw
        await cache.storeFullRaster(0, image,
            pageColor: 0xFFFFFFFF, annotations: true, rotation: null);
        image.dispose();
        expect(
          await cache.loadFullRaster(0,
              width: 8,
              height: 8,
              pageColor: 0xFFFFFFFF,
              annotations: true,
              rotation: null),
          isNull,
        );
      });
    });

    testWidgets('a single oversize raster is rejected without thrashing',
        (tester) async {
      await tester.runAsync(() async {
        // 64 KiB budget: a small raster fits, one over the whole budget must
        // be skipped outright rather than force-evicting everything and still
        // not fitting.
        final cache = _buildCache(PdfMemoryCacheStore(),
            fullBytes: 64 * 1024, format: PdfRasterDiskFormat.rawRgba);
        final small = await solidImage(40, 40, const Color(0xFF112233));
        await cache.storeFullRaster(0, small,
            pageColor: 0xFFFFFFFF, annotations: true, rotation: null);
        small.dispose();
        expect(await cache.fullRasters!.debugLength, 1);

        // 200x200 raw RGBA = 160 KB > the whole 64 KB budget.
        final huge = await solidImage(200, 200, const Color(0xFF445566));
        await cache.storeFullRaster(1, huge,
            pageColor: 0xFFFFFFFF, annotations: true, rotation: null);
        huge.dispose();

        expect(await cache.fullRasters!.debugLength, 1,
            reason: 'the oversize entry must not evict the entry that fits');
        expect(cache.fullRasters!.oversizeRejections, 1);
        expect(cache.fullRasters!.evictions, 0);

        // the survivor still reads back
        final restored = await cache.loadFullRaster(0,
            width: 40,
            height: 40,
            pageColor: 0xFFFFFFFF,
            annotations: true,
            rotation: null);
        expect(restored, isNotNull);
        restored!.dispose();
      });
    });

    testWidgets('the full-raster tier cannot evict previews or thumbnails',
        (tester) async {
      await tester.runAsync(() async {
        // Separate PdfDiskCache instances mean separate byte budgets. Fill the
        // (tiny) raster budget hard and prove the preview namespace is intact.
        final store = PdfMemoryCacheStore();
        final previews = PdfDiskCache(store, namespace: 'previews');
        final cache = PdfRasterCache(
          previews,
          fullRasters: PdfDiskCache(store,
              namespace: 'page-rasters', maxBytes: 32 * 1024),
          fullRasterFormat: PdfRasterDiskFormat.rawRgba,
        ).forDocument('doc-1');

        final preview = await solidImage(64, 48, const Color(0xFF223344));
        await cache.storePreview(0, preview);
        await cache.storeThumbnail(0, 64, preview);
        preview.dispose();
        final previewEntries = await previews.debugLength;
        expect(previewEntries, 2);

        // Ten 60x60 raw rasters = ~14 KB each; the 32 KB budget evicts most.
        for (var page = 0; page < 10; page++) {
          final raster = await solidImage(60, 60, const Color(0xFF556677));
          await cache.storeFullRaster(page, raster,
              pageColor: 0xFFFFFFFF, annotations: true, rotation: null);
          raster.dispose();
        }
        expect(cache.fullRasters!.evictions, greaterThan(0),
            reason: 'the raster budget must actually be enforced');
        expect(await previews.debugLength, previewEntries,
            reason: 'raster eviction must not touch the preview namespace');
        expect(await cache.readBytes(0), isNotNull);
        final thumbnail = await cache.loadThumbnail(0, 64);
        expect(thumbnail, isNotNull);
        thumbnail!.dispose();
      });
    });

    testWidgets('clearFullRasters empties only the raster namespace',
        (tester) async {
      await tester.runAsync(() async {
        final cache = _buildCache(PdfMemoryCacheStore());
        final image = await solidImage(16, 16, const Color(0xFF334455));
        await cache.storePreview(0, image);
        await cache.storeFullRaster(0, image,
            pageColor: 0xFFFFFFFF, annotations: true, rotation: null);
        image.dispose();
        expect(await cache.fullRasters!.debugLength, 1);

        await cache.clearFullRasters();
        expect(await cache.fullRasters!.debugLength, 0);
        expect(
          await cache.loadFullRaster(0,
              width: 16,
              height: 16,
              pageColor: 0xFFFFFFFF,
              annotations: true,
              rotation: null),
          isNull,
        );
        expect(await cache.readBytes(0), isNotNull,
            reason: 'previews are a different namespace');
      });
    });
  });

  group('PdfPagePreviewCache persistent full rasters', () {
    testWidgets('writes through on put and restores in a later session',
        (tester) async {
      const policy = PdfPageRasterCachePolicy(
        maxBytes: 8 * 1024 * 1024,
        maxEntryBytes: 8 * 1024 * 1024,
      );
      final document = PdfDocument.open(buildMultiPagePdf(2));
      final page = document.page(0);
      late PdfPagePreviewCache sessionB;

      await tester.runAsync(() async {
        final store = PdfMemoryCacheStore();
        final raster = _buildCache(store);

        final sessionA = PdfPagePreviewCache()..disk = raster;
        sessionA.configureFullRasterCache(policy);
        expect(sessionA.hasPersistentFullRasters, isTrue);

        final image = await solidImage(48, 64, const Color(0xFFEEEEEE));
        sessionA.putFullImage(0, page, image,
            pageColor: const Color(0xFFFFFFFF),
            annotations: true,
            rotation: null,
            revision: '0.0.0');
        image.dispose();
        // the store is fire-and-forget; give the drain a turn
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(raster.fullRasterStats.stores, 1);
        sessionA.dispose();

        // A fresh cache (the "reopened the app" case) restores it without
        // rendering anything.
        sessionB = PdfPagePreviewCache()..disk = raster;
        sessionB.configureFullRasterCache(policy);
        expect(sessionB.fullRasterCount, 0);

        final restored = await sessionB.loadFullFromDisk(0, page,
            width: 48,
            height: 64,
            pageColor: const Color(0xFFFFFFFF),
            annotations: true,
            rotation: null,
            revision: '0.0.0');
        expect(restored, isNotNull);
        expect(restored!.width, 48);
        restored.dispose();
      });

      addTearDown(sessionB.dispose);
      // admitted into memory, so the very next lookup is a RAM hit
      expect(sessionB.fullRasterCount, 1);
      final memory = sessionB.fullImageFor(0, page,
          width: 48,
          height: 64,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          rotation: null);
      expect(memory, isNotNull);
      memory!.dispose();
    });

    testWidgets('a disk hit too large for RAM still serves the page',
        (tester) async {
      final document = PdfDocument.open(buildMultiPagePdf(1));
      final page = document.page(0);
      late PdfPagePreviewCache reader;

      await tester.runAsync(() async {
        final raster = _buildCache(PdfMemoryCacheStore());
        final writer = PdfPagePreviewCache()..disk = raster;
        final image = await solidImage(64, 64, const Color(0xFFCCCCCC));
        writer.putFullImage(0, page, image,
            pageColor: const Color(0xFFFFFFFF),
            annotations: true,
            rotation: null);
        image.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        writer.dispose();

        // A memory policy that admits nothing at all.
        reader = PdfPagePreviewCache()..disk = raster;
        reader.configureFullRasterCache(
            const PdfPageRasterCachePolicy.disabled());

        final restored = await reader.loadFullFromDisk(0, page,
            width: 64,
            height: 64,
            pageColor: const Color(0xFFFFFFFF),
            annotations: true,
            rotation: null);
        expect(restored, isNotNull,
            reason: 'the page on screen may use it immediately');
        restored!.dispose();
      });

      addTearDown(reader.dispose);
      expect(reader.fullRasterCount, 0,
          reason: 'but it must not defeat the memory policy');
    });

    testWidgets('a session with no persistent tier keeps rasters in memory',
        (tester) async {
      final document = PdfDocument.open(buildMultiPagePdf(1));
      final page = document.page(0);
      late PdfPagePreviewCache memoryOnly;

      await tester.runAsync(() async {
        memoryOnly = PdfPagePreviewCache()
          ..disk = PdfRasterCache(PdfDiskCache(PdfMemoryCacheStore()))
              .forDocument('doc-1');
        expect(memoryOnly.hasPersistentFullRasters, isFalse);

        final image = await solidImage(32, 32, const Color(0xFF999999));
        memoryOnly.putFullImage(0, page, image,
            pageColor: const Color(0xFFFFFFFF),
            annotations: true,
            rotation: null);
        image.dispose();
        expect(
          await memoryOnly.loadFullFromDisk(0, page,
              width: 32,
              height: 32,
              pageColor: const Color(0xFFFFFFFF),
              annotations: true,
              rotation: null),
          isNull,
        );
      });

      addTearDown(memoryOnly.dispose);
      expect(memoryOnly.fullRasterCount, 1);
    });

    testWidgets('background writes yield while the host is busy',
        (tester) async {
      final document = PdfDocument.open(buildMultiPagePdf(1));
      final page = document.page(0);
      late PdfPagePreviewCache cache;

      await tester.runAsync(() async {
        final raster = _buildCache(PdfMemoryCacheStore());
        var busy = true;
        cache = PdfPagePreviewCache()
          ..disk = raster
          ..deferBackgroundIo = () => busy;

        final image = await solidImage(32, 32, const Color(0xFF777777));
        cache.putFullImage(0, page, image,
            pageColor: const Color(0xFFFFFFFF),
            annotations: true,
            rotation: null);
        image.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(raster.fullRasterStats.stores, 0,
            reason: 'the encode must wait while the viewer is scrolling');

        busy = false;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(raster.fullRasterStats.stores, 1);
      });
      addTearDown(cache.dispose);
    });

    testWidgets('clearPersistentFullRasters empties the tier and the queue',
        (tester) async {
      // Hosts must be able to wipe this: page rasters are pixel-exact copies
      // of document content, and a PDF may hold material a user needs gone.
      // A queued-but-unwritten raster has to go too, or the wipe leaks.
      final document = PdfDocument.open(buildMultiPagePdf(1));
      final page = document.page(0);
      late PdfPagePreviewCache cache;

      await tester.runAsync(() async {
        final raster = _buildCache(PdfMemoryCacheStore());
        var busy = false;
        cache = PdfPagePreviewCache()
          ..disk = raster
          ..deferBackgroundIo = () => busy;

        final first = await solidImage(24, 24, const Color(0xFF010101));
        cache.putFullImage(0, page, first,
            pageColor: const Color(0xFFFFFFFF),
            annotations: true,
            rotation: null);
        first.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(raster.fullRasterStats.stores, 1);
        expect(await raster.fullRasters!.debugLength, 1);

        // A second raster queues behind a busy viewer and is still pending.
        busy = true;
        final second = await solidImage(24, 24, const Color(0xFF020202));
        cache.putFullImage(1, page, second,
            pageColor: const Color(0xFFFFFFFF),
            annotations: true,
            rotation: null);
        second.dispose();

        await cache.clearPersistentFullRasters();
        expect(await raster.fullRasters!.debugLength, 0,
            reason: 'the stored raster is gone');

        busy = false;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(raster.fullRasterStats.stores, 1,
            reason: 'the queued raster was dropped, not written after the wipe');
        expect(await raster.fullRasters!.debugLength, 0);
      });
      addTearDown(cache.dispose);
    });

    testWidgets('the pending write queue is bounded', (tester) async {
      // Each queued write holds a clone of a page-sized raster. A viewer that
      // stays busy while pages stream past must not pin an unbounded number of
      // them - the oldest are dropped, newest kept.
      final document = PdfDocument.open(buildMultiPagePdf(4));
      final page = document.page(0);
      late PdfPagePreviewCache cache;

      await tester.runAsync(() async {
        final raster = _buildCache(PdfMemoryCacheStore());
        var busy = true;
        cache = PdfPagePreviewCache()
          ..disk = raster
          ..deferBackgroundIo = () => busy;

        // Four distinct pages queue behind a busy viewer; the cap is two.
        for (var index = 0; index < 4; index++) {
          final image =
              await solidImage(20 + index, 20, const Color(0xFF334455));
          cache.putFullImage(index, page, image,
              pageColor: const Color(0xFFFFFFFF),
              annotations: true,
              rotation: null);
          image.dispose();
        }
        busy = false;
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(raster.fullRasterStats.stores, 2,
            reason: 'the queue holds at most two pending writes');
        // The two newest survived; the two oldest were dropped.
        for (final index in const [2, 3]) {
          final kept = await raster.loadFullRaster(index,
              width: 20 + index,
              height: 20,
              pageColor: 0xFFFFFFFF,
              annotations: true,
              rotation: null);
          expect(kept, isNotNull, reason: 'page $index is one of the newest');
          kept!.dispose();
        }
        for (final index in const [0, 1]) {
          expect(
            await raster.loadFullRaster(index,
                width: 20 + index,
                height: 20,
                pageColor: 0xFFFFFFFF,
                annotations: true,
                rotation: null),
            isNull,
            reason: 'page $index was dropped from the queue',
          );
        }
      });
      addTearDown(cache.dispose);
    });

    testWidgets('a write contended for too long is dropped, not held',
        (tester) async {
      // The safety valve: ~3s of sustained foreground work and the queued
      // clone is released rather than pinned or forced through at the
      // expense of the page the user is looking at. The page re-queues when
      // the view settles.
      final document = PdfDocument.open(buildMultiPagePdf(1));
      final page = document.page(0);
      late PdfPagePreviewCache cache;

      await tester.runAsync(() async {
        final raster = _buildCache(PdfMemoryCacheStore());
        var busy = true;
        cache = PdfPagePreviewCache()
          ..disk = raster
          ..deferBackgroundIo = () => busy;

        final image = await solidImage(24, 24, const Color(0xFF667788));
        cache.putFullImage(0, page, image,
            pageColor: const Color(0xFFFFFFFF),
            annotations: true,
            rotation: null);
        image.dispose();

        // 60 deferrals x 50ms, plus slack for a loaded CI runner.
        await Future<void>.delayed(const Duration(milliseconds: 4000));
        expect(raster.fullRasterStats.stores, 0);

        busy = false;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(raster.fullRasterStats.stores, 0,
            reason: 'the contended write was dropped, not merely postponed');
      });
      addTearDown(cache.dispose);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('disposing mid-load releases the decoded raster',
        (tester) async {
      final document = PdfDocument.open(buildMultiPagePdf(1));
      final page = document.page(0);

      await tester.runAsync(() async {
        final raster = _buildCache(PdfMemoryCacheStore());
        final writer = PdfPagePreviewCache()..disk = raster;
        final image = await solidImage(28, 28, const Color(0xFFAABBCC));
        writer.putFullImage(0, page, image,
            pageColor: const Color(0xFFFFFFFF),
            annotations: true,
            rotation: null);
        image.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        writer.dispose();

        final reader = PdfPagePreviewCache()..disk = raster;
        final pending = reader.loadFullFromDisk(0, page,
            width: 28,
            height: 28,
            pageColor: const Color(0xFFFFFFFF),
            annotations: true,
            rotation: null);
        // the viewer is torn down while the read/decode is in flight
        reader.dispose();
        expect(await pending, isNull,
            reason: 'a disposed cache hands back nothing to paint');
      });
    });

    testWidgets('only the newest raster for a page is queued', (tester) async {
      final document = PdfDocument.open(buildMultiPagePdf(1));
      final page = document.page(0);
      late PdfPagePreviewCache cache;

      await tester.runAsync(() async {
        final raster = _buildCache(PdfMemoryCacheStore());
        var busy = true;
        cache = PdfPagePreviewCache()
          ..disk = raster
          ..deferBackgroundIo = () => busy;

        // Three renders of the same page land while the viewer is busy; only
        // the last one is worth a readback and a store.
        for (final size in const [24, 32, 40]) {
          final image = await solidImage(size, size, const Color(0xFF445566));
          cache.putFullImage(0, page, image,
              pageColor: const Color(0xFFFFFFFF),
              annotations: true,
              rotation: null);
          image.dispose();
        }
        busy = false;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(raster.fullRasterStats.stores, 1);

        final restored = await raster.loadFullRaster(0,
            width: 40,
            height: 40,
            pageColor: 0xFFFFFFFF,
            annotations: true,
            rotation: null);
        expect(restored, isNotNull, reason: 'the newest raster is the stored one');
        restored!.dispose();
      });
      addTearDown(cache.dispose);
    });
  });

  group('viewer integration', () {
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }

    testWidgets('a static document persists exact rasters', (tester) async {
      final store = PdfMemoryCacheStore();
      final fullRasters =
          PdfDiskCache(store, namespace: 'page-rasters', maxBytes: 64 << 20);
      final raster = PdfRasterCache(
        PdfDiskCache(store, namespace: 'previews'),
        fullRasters: fullRasters,
      );
      final document = PdfDocument.open(buildMultiPagePdf(3));
      final controller = PdfViewerController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            document: document,
            controller: controller,
            initialFit: PdfViewerFit.width,
            rasterCache: raster,
            documentId: 'doc-static',
          ),
        ),
      ));
      await tester.pump();
      for (var i = 0; i < 120 && raster.fullRasterStats.stores == 0; i++) {
        await settle(tester);
      }
      expect(raster.fullRasterStats.stores, greaterThan(0),
          reason: 'an on-screen render should persist its exact raster');
      expect(fullRasters.bytesWritten, greaterThan(0));
    });

    testWidgets('an edit session never reads or writes exact rasters',
        (tester) async {
      // Insert/remove/reorder shift the page index a stored raster was keyed
      // by, and a redaction burn removes content the stored pixels still show.
      // The viewer keeps an editing document off the persistent tier entirely.
      final store = PdfMemoryCacheStore();
      final fullRasters =
          PdfDiskCache(store, namespace: 'page-rasters', maxBytes: 64 << 20);
      final raster = PdfRasterCache(
        PdfDiskCache(store, namespace: 'previews'),
        fullRasters: fullRasters,
      );
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      final controller = PdfViewerController();
      addTearDown(controller.dispose);

      Widget build() => MaterialApp(
            home: Scaffold(
              body: PdfViewer(
                document: editing.document,
                editing: editing,
                controller: controller,
                initialFit: PdfViewerFit.width,
                rasterCache: raster,
                documentId: 'doc-edit',
              ),
            ),
          );

      await tester.pumpWidget(build());
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await settle(tester);
      }
      expect(raster.fullRasterStats.stores, 0);
      expect(raster.fullRasterStats.hits, 0);
      expect(fullRasters.bytesWritten, 0);

      editing.removePage(0);
      await tester.pumpWidget(build());
      for (var i = 0; i < 30; i++) {
        await settle(tester);
      }
      expect(raster.fullRasterStats.hits, 0,
          reason: 'a removed page must never surface a stale-by-index raster');
      expect(fullRasters.bytesWritten, 0);
    });

    testWidgets('a reopened static document restores a raster from disk',
        (tester) async {
      final store = PdfMemoryCacheStore();
      final raster = PdfRasterCache(
        PdfDiskCache(store, namespace: 'previews'),
        fullRasters:
            PdfDiskCache(store, namespace: 'page-rasters', maxBytes: 64 << 20),
      );
      final bytes = buildMultiPagePdf(3);

      Widget build(PdfDocument document, PdfViewerController controller) =>
          MaterialApp(
            home: Scaffold(
              body: PdfViewer(
                document: document,
                controller: controller,
                initialFit: PdfViewerFit.width,
                rasterCache: raster,
                documentId: 'doc-reopen',
              ),
            ),
          );

      final firstController = PdfViewerController();
      addTearDown(firstController.dispose);
      await tester.pumpWidget(build(PdfDocument.open(bytes), firstController));
      await tester.pump();
      for (var i = 0; i < 120 && raster.fullRasterStats.stores == 0; i++) {
        await settle(tester);
      }
      expect(raster.fullRasterStats.stores, greaterThan(0));

      // tear the viewer down completely, then mount a fresh one over the same
      // bytes and the same documentId - the "reopened the app" case
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);

      final secondController = PdfViewerController();
      addTearDown(secondController.dispose);
      await tester.pumpWidget(build(PdfDocument.open(bytes), secondController));
      await tester.pump();
      for (var i = 0; i < 120 && raster.fullRasterStats.hits == 0; i++) {
        await settle(tester);
      }
      expect(raster.fullRasterStats.hits, greaterThan(0),
          reason: 'the second session should serve a page straight from disk');
    });
  });
}
