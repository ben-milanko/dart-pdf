// A page whose content is one big raster (a scan, a CAD underlay) gets no
// sharpness from the tile pyramid unless its IMAGES are re-decoded for the
// visible slice: vectors and text replay resolution-independently, but an image
// draw can only ever be as sharp as the pixels the retained scene holds, and
// those are capped at the full-page raster's ratio.
//
// The tile path used to short-circuit `_updateDetail` and rasterize every tile
// from that capped decode, so a 200 dpi scan on a large page stayed at the base
// raster's ~120 dpi no matter how far in you zoomed - visibly fuzzier than
// PDFium/PDF.js, which sample the native JPEG for the window they draw. These
// tests pin the region-scoped re-decode that closes the gap.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// A page dominated by one image denser than the full-page raster cap lets the
/// base scene decode - the scanned-document shape.
///
/// The page is deliberately long and narrow: the cap that binds is the raster's
/// 8192-px max edge, so an elongated page reaches it at a modest image size and
/// the fixture stays small enough to build in a test. On the real 21x52in,
/// 200 dpi scan that motivated this (a 4258x10457 JPEG) the same cap holds the
/// base decode to ~61% linear.
Uint8List _scannedSheet() => buildSyntheticRasterUnderlaySheet(
      underlays: const [PdfUnderlaySpec(width: 2048, height: 1024)],
      layers: 1,
      ops: 8,
      pageW: 600,
      pageH: 6000,
    );

Future<void> _settle(WidgetTester tester, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
}

void main() {
  late PdfTileStore store;
  late PdfRenderWorker worker;

  void setUpTiles(Uint8List bytes) {
    store = PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
    worker = PdfRenderWorker.startUncached(bytes);
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    PdfPageView.debugTileImageDetailAdoptions = 0;
    PdfPageView.debugTileImageDetailRatio = null;
  }

  tearDown(() {
    PdfPageView.tileStoreDetail = false;
    PdfPageView.debugTileStoreOverride = null;
    PdfPageView.debugTileImageDetailAdoptions = 0;
    PdfPageView.debugTileImageDetailRatio = null;
    worker.dispose();
    store.dispose();
  });

  testWidgets('deep zoom re-decodes the page image for the visible slice',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = _scannedSheet();
    setUpTiles(bytes);
    final doc = PdfDocument.open(bytes);
    final page = doc.page(0);

    // Laid out several times its point width: only a slice fits, and the zoom
    // asks for far more resolution than the capped full-page raster can hold.
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: page.mediaBox.width * 6,
            child: PdfPageView(page: page, renderWorker: worker),
          ),
        ),
      ),
    );
    await _settle(tester, rounds: 40);

    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsOneWidget,
        reason: 'the tile path must be the one driving this view');
    expect(
      PdfPageView.debugTileImageDetailAdoptions,
      greaterThan(0),
      reason: 'tiles must not magnify the base scene\'s capped image decode',
    );
    // The re-decode happens at the zoom's own resolution, not the page
    // raster's - that difference IS the fix.
    final adopted = PdfPageView.debugTileImageDetailRatio!;
    final pageRasterCap = math.min(
      math.sqrt((1 << 24) / (page.mediaBox.width * page.mediaBox.height)),
      8192 / math.max(page.mediaBox.width, page.mediaBox.height),
    );
    expect(adopted, greaterThan(pageRasterCap));
  });

  testWidgets('a page the base raster already covers asks for no re-decode',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = _scannedSheet();
    setUpTiles(bytes);
    final doc = PdfDocument.open(bytes);
    final page = doc.page(0);

    // Fit-width at 1x: the base raster is already at the resolution the view
    // asks for, so there is no deep-zoom slice and nothing to sharpen.
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: PdfPageView(page: page, renderWorker: worker),
        ),
      ),
    );
    await _settle(tester, rounds: 20);

    expect(PdfPageView.debugTileImageDetailAdoptions, 0);
  });
}
