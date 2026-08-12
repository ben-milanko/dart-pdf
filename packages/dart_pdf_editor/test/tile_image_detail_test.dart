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
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/region_replay_index.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// A page dominated by layered images denser than the full-page raster cap
/// lets the base scene decode - the scanned/CAD-underlay shape.
///
/// The page is deliberately long and narrow: the cap that binds is the raster's
/// 8192-px max edge, so an elongated page reaches it at a modest image size and
/// the fixture stays small enough to build in a test. On the real 21x52in,
/// 200 dpi scan that motivated this (a 4258x10457 JPEG) the same cap holds the
/// base decode to ~61% linear.
Uint8List _scannedSheet() => buildSyntheticRasterUnderlaySheet(
      underlays: const [PdfUnderlaySpec(width: 2048, height: 1024)],
      layers: 2,
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
    PdfPageView.debugTileImageDetailRegion = null;
  }

  tearDown(() {
    PdfPageView.tileStoreDetail = false;
    PdfPageView.debugTileStoreOverride = null;
    PdfPageView.debugTileImageDetailAdoptions = 0;
    PdfPageView.debugTileImageDetailRatio = null;
    PdfPageView.debugTileImageDetailRegion = null;
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
    // Five deliberately lies between tile-pyramid rungs: it rounds up to
    // sqrt(2)^5. A detail decode at 5x cannot sharpen a tile rasterized at
    // 5.657x, so the decode must use the snapped tile ratio.
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: page.mediaBox.width * 5,
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
    // The re-decode happens above the tile rung's resolution, not merely at
    // the continuous view ratio or the page raster's ratio. The same 2x image
    // headroom used by visible full-page rendering keeps raster underlays from
    // looking softer than vectors after the tile is flattened and presented.
    final adopted = PdfPageView.debugTileImageDetailRatio!;
    final tileRatio = store.ladder.ratioFor(store.ladder.rungAtOrAbove(5));
    final pageRasterCap = math.min(
      math.sqrt(PdfPageRasterGeometry.maxPixels /
          (page.mediaBox.width * page.mediaBox.height)),
      8192 / math.max(page.mediaBox.width, page.mediaBox.height),
    );
    expect(adopted, greaterThan(pageRasterCap));
    expect(
      adopted,
      closeTo(tileRatio * PdfPageView.focusedImageDecodeHeadroom, 1e-9),
    );

    // Every retained exact-rung tile must fit inside the image-detail decode.
    // Previously the decode followed the visible rectangle while the store
    // rasterized whole cells. A partially covered cell then used the blurry
    // base scene and was cached forever at this sharp rung.
    final detailRegion = PdfPageView.debugTileImageDetailRegion!;
    final retained = store
        .debugTileFractionsForPage(0)
        .where((tile) => tile.rung == store.ladder.rungAtOrAbove(5));
    expect(retained, isNotEmpty);
    for (final tile in retained) {
      final region = Rect.fromLTRB(
        tile.fraction.left * page.mediaBox.width,
        tile.fraction.top * page.mediaBox.height,
        tile.fraction.right * page.mediaBox.width,
        tile.fraction.bottom * page.mediaBox.height,
      );
      expect(
        region.left,
        greaterThanOrEqualTo(detailRegion.left - 1e-6),
      );
      expect(region.top, greaterThanOrEqualTo(detailRegion.top - 1e-6));
      expect(region.right, lessThanOrEqualTo(detailRegion.right + 1e-6));
      expect(region.bottom, lessThanOrEqualTo(detailRegion.bottom + 1e-6));
    }
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

  testWidgets('tiles retain the completed visible patch while sharpening',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = _scannedSheet();
    setUpTiles(bytes);
    final doc = PdfDocument.open(bytes);
    final page = doc.page(0);

    Widget at(int settleGeneration) => Center(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: page.mediaBox.width * 5,
              child: PdfPageView(
                page: page,
                settleGeneration: settleGeneration,
                renderWorker: worker,
              ),
            ),
          ),
        );

    // First take the single-patch route. It is the quick visible answer that
    // used to disappear as soon as the reusable pyramid engaged.
    PdfPageView.tileStoreDetail = false;
    await tester.pumpWidget(at(0));
    for (var i = 0; i < 100; i++) {
      await tester.pump();
      if (find
          .byKey(const ValueKey('pdf-page-detail-image'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(
      find.byKey(const ValueKey('pdf-page-detail-image')),
      findsOneWidget,
      reason: 'the visible-region refinement must land before tile prefetch',
    );

    // A translation settle switches back to the reusable tile pyramid. The
    // completed patch remains the visual fallback under its sparse tiles;
    // previously the two widgets were mutually exclusive and the page fell
    // back to its low-resolution full raster until the tile image scene landed.
    PdfPageView.tileStoreDetail = true;
    await tester.pumpWidget(at(1));
    for (var i = 0; i < 20; i++) {
      await tester.pump();
      if (find
          .byKey(const ValueKey('pdf-page-tile-layer'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-page-detail-image')), findsOneWidget,
        reason: 'engaging tiles must not hide already-sharp visible pixels');
    final painter = tester
        .widget<CustomPaint>(find.byKey(const ValueKey('pdf-page-tile-layer')))
        .painter as dynamic;
    expect(painter.fallbackOcclusionFraction, isNotNull,
        reason: 'a coarse retained rung must not cover the sharper patch');
  });

  testWidgets('an older detail patch cannot hide a sharper fallback rung',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = _scannedSheet();
    setUpTiles(bytes);
    final doc = PdfDocument.open(bytes);
    final page = doc.page(0);

    Widget at(double widthFactor, int settleGeneration) => Center(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: page.mediaBox.width * widthFactor,
              child: PdfPageView(
                key: const ValueKey('quality-monotonic-page'),
                page: page,
                settleGeneration: settleGeneration,
                renderWorker: worker,
              ),
            ),
          ),
        );

    // Land a 2x single-patch refinement first.
    PdfPageView.tileStoreDetail = false;
    await tester.pumpWidget(at(2, 0));
    for (var i = 0; i < 100; i++) {
      await tester.pump();
      if (find
          .byKey(const ValueKey('pdf-page-detail-image'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(find.byKey(const ValueKey('pdf-page-detail-image')), findsOneWidget);

    // At 5x the requested exact rung is 5.657x and its sharpest fallback is
    // 4x. The retained 2x patch should remain as backing pixels, but it must
    // not clip that sharper 4x fallback out of the tile layer.
    PdfPageView.tileStoreDetail = true;
    await tester.pumpWidget(at(5, 1));
    for (var i = 0; i < 20; i++) {
      await tester.pump();
      if (find
          .byKey(const ValueKey('pdf-page-tile-layer'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-page-detail-image')), findsOneWidget);
    final painter = tester
        .widget<CustomPaint>(find.byKey(const ValueKey('pdf-page-tile-layer')))
        .painter as dynamic;
    expect(
      painter.fallbackOcclusionFraction,
      isNull,
      reason: 'a lower-density patch must not hide a sharper cached rung',
    );
  });

  testWidgets('panning coalesces tile image detail behind one worker record',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = _scannedSheet();
    store = PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
    final blocking = _BlockingFirstDetailWorker(
      PdfRenderWorker.startUncached(bytes),
    );
    worker = blocking;
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;

    final doc = PdfDocument.open(bytes);
    final page = doc.page(0);
    Widget at(double dy, int settleGeneration) => Center(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.translate(
              // The synthetic page is 6000pt tall. Moving by 3000 layout
              // pixels shifts the requested PDF region by 600pt while the
              // page remains on screen, well beyond one viewport of decode
              // headroom.
              offset: Offset(0, dy),
              child: SizedBox(
                width: page.mediaBox.width * 5,
                child: PdfPageView(
                  key: const ValueKey('coalesced-detail-page'),
                  page: page,
                  settleGeneration: settleGeneration,
                  renderWorker: blocking,
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(at(0, 0));
    for (var i = 0; i < 100 && blocking.detailRecords == 0; i++) {
      await _settle(tester, rounds: 1);
    }
    expect(blocking.detailRecords, 1,
        reason: 'the first viewport should start one region record');

    // Move far enough that the first region no longer covers the viewport,
    // while leaving that first decode deliberately blocked. This used to
    // enqueue another record after every settle and produced 20-36 second
    // worker queue waits in the CAD trace.
    await tester.pumpWidget(at(-3000, 1));
    await _settle(tester, rounds: 10);
    expect(blocking.detailRecords, 1,
        reason: 'a new viewport must coalesce behind the active decode');
    expect(blocking.maxActiveDetails, 1);

    blocking.releaseFirst();
    for (var i = 0; i < 150 && blocking.detailRecords < 2; i++) {
      await _settle(tester, rounds: 1);
    }
    expect(blocking.detailRecords, 2,
        reason: 'completion should immediately re-evaluate the latest view');
    expect(blocking.maxActiveDetails, 1,
        reason: 'tile image detail records must remain serialized');
  });

  testWidgets('a worker that declines the region record still lets tiles land',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = _scannedSheet();
    store = PdfTileStore(tilePixels: 256, registerForMemoryPressure: false);
    final declining = _DecliningDetailWorker(
      PdfRenderWorker.startUncached(bytes),
    );
    worker = declining;
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    PdfPageView.debugTileImageDetailAdoptions = 0;

    final doc = PdfDocument.open(bytes);
    final page = doc.page(0);
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: page.mediaBox.width * 6,
            child: PdfPageView(page: page, renderWorker: declining),
          ),
        ),
      ),
    );
    await _settle(tester, rounds: 40);

    expect(declining.declinedDetailRecords, greaterThan(0),
        reason: 'the detail request must have been made and refused');
    expect(PdfPageView.debugTileImageDetailAdoptions, 0);
    // The veto that holds tiles back until sharp pixels arrive MUST clear when
    // they never arrive. Otherwise a page whose worker declines the region
    // record stops tiling altogether - strictly worse than the capped-decode
    // tiles this change replaced.
    expect(store.tileCount, greaterThan(0),
        reason: 'a declined detail must fall back to base-scene tiles');
  });
}

/// A worker that serves ordinary page records but refuses every region-scoped
/// one - the shape of a backend whose scope cannot honour `imageDecodeRegion`.
class _DecliningDetailWorker extends PdfRenderWorker {
  _DecliningDetailWorker(this.inner);

  final PdfRenderWorker inner;
  int declinedDetailRecords = 0;

  @override
  bool get isActive => inner.isActive;

  @override
  Future<List<PdfRenderCommand>?> record(
    int pageIndex, {
    bool annotations = true,
    int priority = 0,
    double? imagePixelRatio,
    bool decodeImages = true,
    int? commandLimit,
    PdfRect? imageDecodeRegion,
    PdfPartialRecordSink? onPartial,
  }) {
    if (imageDecodeRegion != null) {
      declinedDetailRecords++;
      return Future<List<PdfRenderCommand>?>.value();
    }
    return inner.record(
      pageIndex,
      annotations: annotations,
      priority: priority,
      imagePixelRatio: imagePixelRatio,
      decodeImages: decodeImages,
      commandLimit: commandLimit,
      imageDecodeRegion: imageDecodeRegion,
      onPartial: onPartial,
    );
  }

  @override
  Future<PdfRegionReplayIndex?> buildRegionIndex(
    int pageIndex, {
    required bool annotations,
    required int maxCommands,
    required bool buildGrid,
    int priority = 0,
  }) =>
      inner.buildRegionIndex(
        pageIndex,
        annotations: annotations,
        maxCommands: maxCommands,
        buildGrid: buildGrid,
        priority: priority,
      );

  @override
  void cancel(int pageIndex, {int priority = 0}) =>
      inner.cancel(pageIndex, priority: priority);

  @override
  void dispose() => inner.dispose();
}

class _BlockingFirstDetailWorker extends PdfRenderWorker {
  _BlockingFirstDetailWorker(this.inner);

  final PdfRenderWorker inner;
  final Completer<void> _firstRelease = Completer<void>();
  int detailRecords = 0;
  int activeDetails = 0;
  int maxActiveDetails = 0;

  void releaseFirst() {
    if (!_firstRelease.isCompleted) _firstRelease.complete();
  }

  @override
  bool get isActive => inner.isActive;

  @override
  Future<List<PdfRenderCommand>?> record(
    int pageIndex, {
    bool annotations = true,
    int priority = 0,
    double? imagePixelRatio,
    bool decodeImages = true,
    int? commandLimit,
    PdfRect? imageDecodeRegion,
    PdfPartialRecordSink? onPartial,
  }) async {
    if (imageDecodeRegion != null) {
      detailRecords++;
      activeDetails++;
      maxActiveDetails = math.max(maxActiveDetails, activeDetails);
      try {
        if (detailRecords == 1) await _firstRelease.future;
        // The scheduling behavior under test does not depend on pixel data;
        // complete immediately once released so fake-async time is spent on
        // the PageView state machine, not a second synthetic image decode.
        return const <PdfRenderCommand>[];
      } finally {
        activeDetails--;
      }
    }
    return inner.record(
      pageIndex,
      annotations: annotations,
      priority: priority,
      imagePixelRatio: imagePixelRatio,
      decodeImages: decodeImages,
      commandLimit: commandLimit,
      imageDecodeRegion: imageDecodeRegion,
      onPartial: onPartial,
    );
  }

  @override
  Future<PdfRegionReplayIndex?> buildRegionIndex(
    int pageIndex, {
    required bool annotations,
    required int maxCommands,
    required bool buildGrid,
    int priority = 0,
  }) =>
      inner.buildRegionIndex(
        pageIndex,
        annotations: annotations,
        maxCommands: maxCommands,
        buildGrid: buildGrid,
        priority: priority,
      );

  @override
  void cancel(int pageIndex, {int priority = 0}) =>
      inner.cancel(pageIndex, priority: priority);

  @override
  void dispose() {
    releaseFirst();
    inner.dispose();
  }
}
