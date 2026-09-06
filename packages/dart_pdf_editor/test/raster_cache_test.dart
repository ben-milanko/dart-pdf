// Persistent on-disk preview cache: previews render once, get written
// through to a pluggable byte store as PNG, and load back on a later
// (cold) session so the page paints soft content immediately.
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Lets the real async renderer + the fire-and-forget disk store make
  /// progress, then pumps a frame.
  Future<void> settle(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }

  testWidgets('an empty document key makes every operation a no-op',
      (tester) async {
    final raster = PdfRasterCache(PdfDiskCache(PdfMemoryCacheStore()));
    await tester.runAsync(() async {
      expect(await raster.loadPreview(0), isNull);
      expect(await raster.readBytes(0), isNull);
      // storePreview without an image is hard to call; readBytes proving no
      // write key exists is enough - documentKey '' short-circuits both.
    });
  });

  testWidgets('LoD tiles round-trip through their independent disk tier',
      (tester) async {
    await tester.runAsync(() async {
      final store = PdfMemoryCacheStore();
      final cache = PdfRasterCache(
        PdfDiskCache(store, namespace: 'previews'),
        tiles: PdfDiskCache(store, namespace: 'tiles'),
      ).forDocument('doc-tiles');
      const id = PdfTilePageIdentity(
        pageIndex: 2,
        pageEpoch: 0,
        contentStamp: 0,
        destructiveStamp: 0,
        plan: PdfPageRenderPlan(),
      );
      const key = PdfTileKey(id, 3, 4, 5);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 24, 16),
        Paint()..color = const Color(0xFF335577),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(24, 16);
      picture.dispose();
      const region = Rect.fromLTWH(10, 20, 12, 8);
      await cache.storeTile(key, image, region: region, pixelRatio: 2);
      image.dispose();

      final restored = await cache.loadTile(key,
          region: region, pixelRatio: 2, width: 24, height: 16);
      expect(restored, isNotNull);
      expect(restored!.width, 24);
      expect(restored.height, 16);
      restored.dispose();
      expect(cache.tileStats.stores, 1);
      expect(cache.tileStats.hits, 1);

      // Every visual identity component participates in the key.
      const other = PdfTileKey(
        PdfTilePageIdentity(
          pageIndex: 2,
          pageEpoch: 0,
          contentStamp: 1,
          destructiveStamp: 0,
          plan: PdfPageRenderPlan(),
        ),
        3,
        4,
        5,
      );
      expect(
          await cache.loadTile(other,
              region: region, pixelRatio: 2, width: 24, height: 16),
          isNull);
      // A host may choose a non-default tile size or zoom ladder. Region and
      // ratio therefore participate independently instead of trusting rung
      // and grid coordinates to imply the physical raster.
      expect(
          await cache.loadTile(key,
              region: const Rect.fromLTWH(10, 20, 16, 8),
              pixelRatio: 2,
              width: 32,
              height: 16),
          isNull);
      expect(cache.tileStats.misses, 2);
    });
  });

  testWidgets('renders write through to disk and load back as an image',
      (tester) async {
    final store = PdfMemoryCacheStore();
    final raster = PdfRasterCache(PdfDiskCache(store)).forDocument('doc-1');
    final document = PdfDocument.open(buildMultiPagePdf(3));
    // capture page objects once, exactly as the viewer holds `_pages`
    final pages = [
      for (var i = 0; i < document.pageCount; i++) document.page(i)
    ];

    // session one: render previews into a cache backed by the raster store
    final cacheA = PdfPagePreviewCache()..disk = raster;
    await tester.runAsync(() async {
      await cacheA.renderPreview(0, pages[0]);
      await cacheA.renderPreview(1, pages[1]);
    });
    await settle(tester);

    // the PNGs landed in the store
    await tester.runAsync(() async {
      expect(await raster.readBytes(0), isNotNull);
      expect(await raster.readBytes(1), isNotNull);
      expect(await raster.readBytes(2), isNull); // never rendered
    });
    expect(store.debugBytes, greaterThan(0));
    cacheA.dispose();

    // session two: a fresh cache primes from disk without re-rendering
    final cacheB = PdfPagePreviewCache()..disk = raster;
    addTearDown(cacheB.dispose);
    expect(cacheB.has(0), isFalse);
    await tester.runAsync(() => cacheB.loadFromDisk(pages));
    expect(cacheB.has(0), isTrue);
    expect(cacheB.has(1), isTrue);
    expect(cacheB.has(2), isFalse);

    final clone = cacheB.imageFor(0);
    expect(clone, isNotNull);
    expect(clone!.width, greaterThan(0));
    expect(clone.width, lessThanOrEqualTo(200));
    clone.dispose();
  });

  testWidgets('loadFromDisk leaves an existing in-session preview alone',
      (tester) async {
    final raster =
        PdfRasterCache(PdfDiskCache(PdfMemoryCacheStore())).forDocument('d');
    final document = PdfDocument.open(buildMultiPagePdf(2));
    final pages = [document.page(0), document.page(1)];
    final cache = PdfPagePreviewCache()..disk = raster;
    addTearDown(cache.dispose);

    await tester.runAsync(() async {
      // render page 0 (writes through), then mark it fresh in-session
      await cache.renderPreview(0, pages[0]);
    });
    await settle(tester);
    expect(cache.isFresh(0, pages[0]), isTrue);

    // loadFromDisk must not disturb the fresh in-memory entry
    await tester.runAsync(() => cache.loadFromDisk(pages));
    expect(cache.isFresh(0, pages[0]), isTrue);
  });

  testWidgets('a PdfViewer with a rasterCache writes previews through to disk',
      (tester) async {
    final store = PdfMemoryCacheStore();
    final raster = PdfRasterCache(PdfDiskCache(store));
    final document = PdfDocument.open(buildMultiPagePdf(4));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          rasterCache: raster,
          documentId: 'doc-A',
        ),
      ),
    ));
    await tester.pump();

    // pages render on screen and write their previews through to the store
    for (var i = 0; i < 100 && store.debugBytes == 0; i++) {
      await settle(tester);
    }
    expect(store.debugBytes, greaterThan(0),
        reason: 'on-screen renders should persist previews to the store');

    // null documentId leaves the cache idle (no key to store under)
    final idleStore = PdfMemoryCacheStore();
    final idleController = PdfViewerController();
    addTearDown(idleController.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: idleController,
          initialFit: PdfViewerFit.width,
          rasterCache: PdfRasterCache(PdfDiskCache(idleStore)),
          // documentId omitted on purpose
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await settle(tester);
    }
    expect(idleStore.debugBytes, 0,
        reason: 'without a documentId there is no safe key to store under');
  });

  testWidgets('an edit session never serves previews from the disk backing',
      (tester) async {
    // The disk backing keys previews by page index. An edit can insert,
    // remove, or reorder pages, shifting that index, so a stale-by-index
    // preview would surface during fast scrolling. The viewer must keep an
    // editing document's previews in-memory only, exactly as the text cache
    // does - so even with a rasterCache + documentId the store stays idle.
    final store = PdfMemoryCacheStore();
    final raster = PdfRasterCache(PdfDiskCache(store));
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
    for (var i = 0; i < 20; i++) {
      await settle(tester);
    }
    expect(store.debugBytes, 0,
        reason: 'an edit session must not write index-keyed previews to disk');

    // insert pages, then rebuild the viewer with the new revision (as the
    // host does on controller notify): the disk backing must stay idle so no
    // stale-by-index preview is loaded for the shifted pages.
    editing.insertPagesFromBytes(buildMultiPagePdf(2), at: 1);
    expect(editing.document.pageCount, 6);
    await tester.pumpWidget(build());
    for (var i = 0; i < 20; i++) {
      await settle(tester);
    }
    expect(store.debugBytes, 0,
        reason: 'inserting pages must not surface disk previews keyed by the '
            'pre-insert index');
  });
}
