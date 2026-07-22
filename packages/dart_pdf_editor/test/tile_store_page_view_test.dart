// With PdfPageView.tileStoreDetail on, a deep-zoom page must composite tiles
// from the store instead of the single detail patch, while the base raster
// keeps showing through. Kept in its own file so the global flag mutation can't
// leak into other page-view tests.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  testWidgets('tile path composites deep-zoom tiles instead of the patch',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfPageView.tileStoreDetail = false;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
    });

    final doc = PdfDocument.open(buildClassicPdf());
    // Laid out 10x wider than its point size: only a slice fits, so the tile
    // layer covers the visible fraction and the base raster shows underneath.
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(width: 6120, child: PdfPageView(page: doc.page(0))),
        ),
      ),
    );
    // Let the base render, the tile-geometry refresh, and the tile rasters land.
    for (var i = 0; i < 4; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    // The tile layer replaced the single detail patch.
    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-page-detail-image')), findsNothing);
    // The base raster is still the only RawImage (tiles paint via CustomPaint).
    expect(find.byType(RawImage), findsOneWidget);
    // Real tiles rastered from the page's retained scene.
    expect(store.tileCount, greaterThan(0));
  });

  testWidgets('a view over the tile budget falls back to the single patch',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    // Capacity 2 tiles (8 MB floor / 4 MB per 1024² tile) → the 75% fit
    // threshold is 1 tile, so the multi-tile deep-zoom slice below cannot tile
    // and must fall back to the single detail patch instead of thrashing.
    final store = PdfTileStore(
      tilePixels: 1024,
      maxBytes: 8 << 20,
      registerForMemoryPressure: false,
    );
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfPageView.tileStoreDetail = false;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
    });

    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(width: 6120, child: PdfPageView(page: doc.page(0))),
        ),
      ),
    );

    // Poll until the fallback patch lands (the tile path never engages).
    final detail = find.byKey(const ValueKey('pdf-page-detail-image'));
    var landed = false;
    for (var i = 0; i < 500 && !landed; i++) {
      await tester.pump();
      final exception = tester.takeException();
      if (exception != null) fail('detail patch failed: $exception');
      landed = detail.evaluate().isNotEmpty;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    expect(landed, isTrue, reason: 'over budget → the single detail patch');
    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsNothing);
    expect(store.tileCount, 0, reason: 'nothing rastered into the pyramid');
  });

  testWidgets('a soft-mask-free scene reports region-cullable', (tester) async {
    // Guards the fallback-adapter gate: classic pages are cullable, so they
    // take the tile path; a soft-mask page would keep the legacy patch.
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildClassicPdf());
      final scene = await PdfRetainedScene.record(doc.page(0));
      expect(scene.supportsRegionRaster, isTrue);
      scene.dispose();
    });
  });
}
