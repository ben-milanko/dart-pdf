import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  // This suite exercises the legacy base-raster + single detail-patch path.
  // The deep-zoom tile pyramid - on by default on every platform now
  // (issues #314/#360) - composites through a CustomPaint layer that replaces
  // the patch, so a deep-zoom view shows one RawImage (the base) plus tiles
  // rather than base + patch. Pin the pyramid off here to test the patch path
  // deterministically; it has its own suites (tile_store_page_view_test.dart,
  // tile_layer_test.dart).
  final tilesDefault = PdfPageView.tileStoreDetail;
  final directPictureDefault = PdfPageView.directPicturePresentation;
  setUp(() {
    PdfPageView.tileStoreDetail = false;
    PdfPageView.directPicturePresentation = false;
  });
  tearDown(() {
    PdfPageView.tileStoreDetail = tilesDefault;
    PdfPageView.directPicturePresentation = directPictureDefault;
  });

  testWidgets('PdfPageView reserves the page aspect ratio', (tester) async {
    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(child: PdfPageView(page: doc.page(0))),
    );
    final size = tester.getSize(find.byType(PdfPageView));
    // US Letter: 612 x 792
    expect(
        size.width / size.height, moreOrLessEquals(612 / 792, epsilon: 1e-6));
  });

  testWidgets('raising scale re-rasterizes at higher resolution',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    // lay out at exactly the page's point width so scale is the only factor
    Widget at(double scale) => Center(
        child:
            SizedBox(width: 612, child: PdfPageView(page: page, scale: scale)));

    await tester.pumpWidget(at(1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final base = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(base.width, 612);

    await tester.pumpWidget(at(2.5));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final zoomed = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(zoomed.width, 1530);
  });

  testWidgets('lowering scale reuses a sharper base raster', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    Widget at(double scale) => Center(
          child: SizedBox(
            width: 612,
            child: PdfPageView(page: page, scale: scale),
          ),
        );

    await tester.pumpWidget(at(2));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final sharp = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(sharp.width, 1224);

    await tester.pumpWidget(at(1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final zoomedOut = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(zoomedOut, same(sharp),
        reason: 'zooming out must not replace an already-sharper raster');
  });

  testWidgets('bounded pages can present their retained picture directly',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    PdfPageView.directPicturePresentation = true;
    final page = PdfDocument.open(buildClassicPdf()).page(0);
    var ready = 0;

    Widget at(double scale) => Center(
          child: SizedBox(
            width: 612,
            child: PdfPageView(
              page: page,
              scale: scale,
              onRasterReady: () => ready++,
            ),
          ),
        );

    await tester.pumpWidget(at(1));
    for (var i = 0; i < 100; i++) {
      await tester.pump();
      if (find
          .byKey(const ValueKey('pdf-page-direct-picture'))
          .evaluate()
          .isNotEmpty) {
        await tester.pump();
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }

    expect(
      find.byKey(const ValueKey('pdf-page-direct-picture')),
      findsOneWidget,
    );
    expect(find.byType(RawImage), findsNothing,
        reason: 'the completed display list replaces the base readback');
    expect(ready, 1);

    await tester.pumpWidget(at(2));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('pdf-page-direct-picture')),
      findsOneWidget,
      reason: 'zoom reuses the retained display list without flattening it',
    );
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('a direct picture refines display-capped images at the live zoom',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    PdfPageView.directPicturePresentation = true;
    final bytes = buildSyntheticRasterUnderlaySheet(
      underlays: const [PdfUnderlaySpec(width: 1024, height: 1024)],
      layers: 1,
      ops: 0,
      pageW: 256,
      pageH: 256,
    );
    final document = PdfDocument.open(bytes);
    final worker = _RatioRecordingWorker(_LocalCommandWorker(bytes));
    addTearDown(worker.dispose);

    Widget at(double scale, int settleGeneration) => Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 256,
            child: PdfPageView(
              page: document.page(0),
              scale: scale,
              settleGeneration: settleGeneration,
              baseRasterScale: 1,
              renderWorker: worker,
            ),
          ),
        );

    await tester.pumpWidget(at(1, 0));
    for (var i = 0; i < 300; i++) {
      await tester.pump();
      if (find
          .byKey(const ValueKey('pdf-page-direct-picture'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(
      find.byKey(const ValueKey('pdf-page-direct-picture')),
      findsOneWidget,
      reason: 'the fit-size display list should be retained before zooming',
    );
    expect(worker.imageRatios, contains(moreOrLessEquals(2, epsilon: 0.01)),
        reason: 'the retained base picture uses fit-size decode headroom');

    await tester.pumpWidget(at(4, 1));
    for (var i = 0; i < 300; i++) {
      await tester.pump();
      if (worker.imageRatios.any((ratio) => ratio >= 3.9) &&
          find
              .byKey(const ValueKey('pdf-page-detail-image'))
              .evaluate()
              .isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }

    expect(
      find.byKey(const ValueKey('pdf-page-direct-picture')),
      findsOneWidget,
      reason: 'vector and text should remain transform-sharp',
    );
    expect(worker.imageRatios, contains(greaterThanOrEqualTo(3.9)),
        reason: 'the image-bearing visible region must decode at the live '
            'zoom instead of treating the fit-size picture as complete');
    expect(
      find.byKey(const ValueKey('pdf-page-detail-image')),
      findsOneWidget,
    );
  });

  testWidgets('a base scale keeps fit pixels and sharpens the visible slice',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    Widget at(double scale) => Center(
          child: SizedBox(
            width: 612,
            child: PdfPageView(
              page: page,
              scale: scale,
              baseRasterScale: 1,
            ),
          ),
        );

    await tester.pumpWidget(at(1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final fitRaster =
        tester.widgetList<RawImage>(find.byType(RawImage)).first.image!;
    expect(fitRaster.width, 612);

    await tester.pumpWidget(at(2.5));
    for (var i = 0; i < 100; i++) {
      await tester.pump();
      if (find
          .byKey(const ValueKey('pdf-page-detail-image'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    final images = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
    expect(images, hasLength(2));
    expect(images.first.image, same(fitRaster),
        reason: 'zoom must not replace the whole-page fit backing');
    final detail = images.last.image!;
    expect(detail.width, greaterThan(fitRaster.width));
  });

  testWidgets(
      'an off-screen page defers its cold and scale raster until visible',
      (tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    const firstKey = ValueKey('first-page-view');
    const secondKey = ValueKey('second-page-view');

    Widget pair(double scale, {required bool secondVisible}) => Stack(
          alignment: Alignment.topLeft,
          children: [
            Positioned(
              top: secondVisible ? 800 : 0,
              width: 612,
              child: SizedBox(
                key: firstKey,
                width: 612,
                child: PdfPageView(
                  page: page,
                  scale: scale,
                  focusDistance: secondVisible ? 1 : 0,
                ),
              ),
            ),
            Positioned(
              top: secondVisible ? 0 : 800,
              width: 612,
              child: SizedBox(
                key: secondKey,
                width: 612,
                child: PdfPageView(
                  page: page,
                  scale: scale,
                  focusDistance: secondVisible ? 0 : 1,
                ),
              ),
            ),
          ],
        );

    ui.Image imageUnder(Key key) => tester
        .widget<RawImage>(find.descendant(
          of: find.byKey(key),
          matching: find.byType(RawImage),
        ))
        .image!;

    Future<void> waitForWidth(Key key, int width) async {
      for (var i = 0; i < 100; i++) {
        await tester.pump();
        final images = find.descendant(
          of: find.byKey(key),
          matching: find.byType(RawImage),
        );
        if (images.evaluate().isNotEmpty && imageUnder(key).width == width) {
          return;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      fail('page under $key did not rasterize at width $width');
    }

    await tester.pumpWidget(pair(1, secondVisible: false));
    await waitForWidth(firstKey, 612);
    expect(
      find.descendant(
        of: find.byKey(secondKey),
        matching: find.byType(RawImage),
      ),
      findsNothing,
      reason: 'a cold cache-window neighbour must not compete with the page '
          'that is actually visible',
    );

    await tester.pumpWidget(pair(2, secondVisible: false));
    await waitForWidth(firstKey, 1224);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(secondKey),
        matching: find.byType(RawImage),
      ),
      findsNothing,
      reason: 'a scale change must not start the deferred cold render',
    );

    await tester.pumpWidget(pair(2, secondVisible: true));
    await waitForWidth(secondKey, 1224);
  });

  testWidgets('a worker result is not replayed after its page leaves viewport',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = buildClassicPdf();
    final document = PdfDocument.open(bytes);
    final worker = _DeferredRecordWorker(PdfRenderWorker.startUncached(bytes));
    addTearDown(worker.dispose);
    final progressiveDefault = PdfPageView.progressiveStreamingPaint;
    final fusedDefault = PdfPageView.fusedProgressiveRecord;
    PdfPageView.progressiveStreamingPaint = true;
    PdfPageView.fusedProgressiveRecord = true;
    addTearDown(() {
      PdfPageView.progressiveStreamingPaint = progressiveDefault;
      PdfPageView.fusedProgressiveRecord = fusedDefault;
    });
    var ready = 0;

    Widget at({required bool visible}) => Stack(
          alignment: Alignment.topLeft,
          children: [
            Positioned(
              top: visible ? 0 : 800,
              width: 612,
              child: PdfPageView(
                page: document.page(0),
                renderWorker: worker,
                focusDistance: visible ? 0 : 1,
                onScreen: visible,
                onRasterReady: () => ready++,
              ),
            ),
          ],
        );

    await tester.pumpWidget(at(visible: true));
    for (var i = 0; i < 100 && !worker.hasPending; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(worker.hasPending, isTrue);

    await tester.pumpWidget(at(visible: false));
    worker.release();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(find.byType(RawImage), findsNothing);
    expect(ready, 0,
        reason: 'an obsolete prefetch must not consume UI replay time');

    await tester.pumpWidget(at(visible: true));
    for (var i = 0; i < 100 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(find.byType(RawImage), findsOneWidget);
    expect(ready, 1);
  });

  testWidgets('both visible pages sharpen when the viewport spans a boundary',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final page = PdfDocument.open(buildClassicPdf()).page(0);
    const focusedKey = ValueKey('focused-page-view');
    const neighbourKey = ValueKey('visible-neighbour-page-view');

    Widget pair(double scale, {required bool neighbourFocused}) => Stack(
          alignment: Alignment.topLeft,
          children: [
            Positioned(
              top: 0,
              width: 612,
              child: SizedBox(
                key: focusedKey,
                child: PdfPageView(
                  page: page,
                  scale: scale,
                  focusDistance: neighbourFocused ? 1 : 0,
                ),
              ),
            ),
            Positioned(
              top: 500,
              width: 612,
              child: SizedBox(
                key: neighbourKey,
                child: PdfPageView(
                  page: page,
                  scale: scale,
                  focusDistance: neighbourFocused ? 0 : 1,
                ),
              ),
            ),
          ],
        );

    ui.Image imageUnder(Key key) => tester
        .widget<RawImage>(find.descendant(
          of: find.byKey(key),
          matching: find.byType(RawImage),
        ))
        .image!;

    Future<void> waitForWidth(Key key, int width) async {
      for (var i = 0; i < 100; i++) {
        await tester.pump();
        final images = find.descendant(
          of: find.byKey(key),
          matching: find.byType(RawImage),
        );
        if (images.evaluate().isNotEmpty && imageUnder(key).width == width) {
          return;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      fail('page under $key did not rasterize at width $width');
    }

    await tester.pumpWidget(pair(1, neighbourFocused: false));
    await waitForWidth(focusedKey, 612);
    await waitForWidth(neighbourKey, 612);

    await tester.pumpWidget(pair(2, neighbourFocused: false));
    await waitForWidth(focusedKey, 1224);
    await waitForWidth(neighbourKey, 1224);

    await tester.pumpWidget(pair(2, neighbourFocused: true));
    expect(imageUnder(focusedKey).width, 1224,
        reason: 'crossing the integer current-page boundary must not make the '
            'other still-visible page soft again');
  });

  testWidgets('layout zoom sharpens every visible page', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final page = PdfDocument.open(buildClassicPdf()).page(0);
    const focusedKey = ValueKey('layout-focused-page-view');
    const neighbourKey = ValueKey('layout-neighbour-page-view');

    Widget pair(
      double width, {
      required int settleGeneration,
      required bool neighbourFocused,
    }) =>
        Stack(
          alignment: Alignment.topLeft,
          children: [
            Positioned(
              top: 0,
              width: width,
              child: SizedBox(
                key: focusedKey,
                child: PdfPageView(
                  page: page,
                  settleGeneration: settleGeneration,
                  focusDistance: neighbourFocused ? 1 : 0,
                ),
              ),
            ),
            Positioned(
              top: 500,
              width: width,
              child: SizedBox(
                key: neighbourKey,
                child: PdfPageView(
                  page: page,
                  settleGeneration: settleGeneration,
                  focusDistance: neighbourFocused ? 0 : 1,
                ),
              ),
            ),
          ],
        );

    ui.Image imageUnder(Key key) => tester
        .widget<RawImage>(find.descendant(
          of: find.byKey(key),
          matching: find.byType(RawImage),
        ))
        .image!;

    Future<void> waitForWidth(Key key, int width) async {
      for (var i = 0; i < 100; i++) {
        await tester.pump();
        final images = find.descendant(
          of: find.byKey(key),
          matching: find.byType(RawImage),
        );
        if (images.evaluate().isNotEmpty && imageUnder(key).width == width) {
          return;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      fail('page under $key did not rasterize at width $width');
    }

    await tester.pumpWidget(pair(
      306,
      settleGeneration: 0,
      neighbourFocused: false,
    ));
    await waitForWidth(focusedKey, 306);
    await waitForWidth(neighbourKey, 306);

    await tester.pumpWidget(pair(
      612,
      settleGeneration: 1,
      neighbourFocused: false,
    ));
    await waitForWidth(focusedKey, 612);
    await waitForWidth(neighbourKey, 612);

    await tester.pumpWidget(pair(
      612,
      settleGeneration: 1,
      neighbourFocused: true,
    ));
    expect(imageUnder(focusedKey).width, 612,
        reason: 'both pages remain sharp while focus crosses the gap');
  });

  testWidgets('off-screen neighbours stay at fit raster resolution',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final page = PdfDocument.open(buildClassicPdf()).page(0);
    Widget at({required bool onScreen}) => Center(
          child: SizedBox(
            width: 612,
            child: PdfPageView(
              page: page,
              scale: 4,
              onScreen: onScreen,
              focusDistance: onScreen ? 0 : 1,
            ),
          ),
        );

    await tester.pumpWidget(at(onScreen: false));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final offScreenImages =
        tester.widgetList<RawImage>(find.byType(RawImage)).toList();
    expect(offScreenImages, hasLength(1),
        reason: 'an off-screen page must not allocate a detail patch');
    expect(offScreenImages.single.image!.width, 612,
        reason: 'global zoom must not allocate a sharp off-screen page');

    await tester.pumpWidget(at(onScreen: true));
    for (var i = 0; i < 100; i++) {
      await tester.pump();
      if (find
          .byKey(const ValueKey('pdf-page-detail-image'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    final visibleImages =
        tester.widgetList<RawImage>(find.byType(RawImage)).toList();
    expect(visibleImages, hasLength(2),
        reason: 'entering the viewport adds sharp visible detail');
    expect(visibleImages.first.image, same(offScreenImages.single.image),
        reason: 'the fit-resolution base remains a valid backing raster');
    expect(visibleImages.last.image!.width, 2448,
        reason: 'the visible detail promotes to the live zoom resolution');
  });

  testWidgets(
      'pages denser than retainedZoomReplayMaxCommands zoom via the '
      'cached-picture fallback', (tester) async {
    // Force every page over BOTH density ceilings: no scene is retained at all
    // (the tile ceiling would otherwise still retain one to feed tiles), so the
    // zoom re-raster must take the classic nested-picture path - the same code
    // retainedZoomReplay=false uses. Same assertions as the retained-path test
    // above: the two paths are byte-identical, so only the raster geometry is
    // observable.
    PdfPageView.retainedZoomReplayMaxCommands = 0;
    PdfPageView.retainedZoomReplayTileMaxCommands = 0;
    addTearDown(() {
      PdfPageView.retainedZoomReplayMaxCommands = 20000;
      PdfPageView.retainedZoomReplayTileMaxCommands = 400000;
    });
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    Widget at(double scale) => Center(
        child:
            SizedBox(width: 612, child: PdfPageView(page: page, scale: scale)));

    await tester.pumpWidget(at(1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final base = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(base.width, 612);

    await tester.pumpWidget(at(2.5));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final zoomed = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(zoomed.width, 1530);
  });

  testWidgets(
      'a page too dense for flat replay still retains a scene to feed tiles',
      (tester) async {
    // The gap this closes: a dense single-sheet drawing used to drop its scene
    // entirely, which disabled tiling, which made every pan step re-render the
    // whole viewport. Over the flat-replay ceiling but under the tile ceiling
    // the scene must be retained (so tiles can cull per region) while the
    // full-page base raster still comes from the cached picture - retaining
    // must not turn the base raster into a UI-thread flat replay.
    PdfPageView.retainedZoomReplayMaxCommands = 0; // "too dense to flat-replay"
    PdfPageView.retainedZoomReplayTileMaxCommands = 400000;
    addTearDown(() {
      PdfPageView.retainedZoomReplayMaxCommands = 20000;
      PdfPageView.retainedZoomReplayTileMaxCommands = 400000;
    });
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    Widget at(double scale) => Center(
        child:
            SizedBox(width: 612, child: PdfPageView(page: page, scale: scale)));

    await tester.pumpWidget(at(1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.width, 612);

    // Same observable geometry as the fallback path - the point is that the
    // raster stays correct while the scene is now available for tiling.
    await tester.pumpWidget(at(2.5));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.width, 1530);
  });

  testWidgets('an off-focus dense page does not enter the scene LRU',
      (tester) async {
    final oldFlatLimit = PdfPageView.retainedZoomReplayMaxCommands;
    final oldTileLimit = PdfPageView.retainedZoomReplayTileMaxCommands;
    final oldOffFocus = PdfPageView.retainDenseScenesOffFocus;
    PdfPageView.retainedZoomReplayMaxCommands = 0;
    PdfPageView.retainedZoomReplayTileMaxCommands = 400000;
    PdfPageView.retainDenseScenesOffFocus = false;
    addTearDown(() {
      PdfPageView.retainedZoomReplayMaxCommands = oldFlatLimit;
      PdfPageView.retainedZoomReplayTileMaxCommands = oldTileLimit;
      PdfPageView.retainDenseScenesOffFocus = oldOffFocus;
    });

    final doc = PdfDocument.open(buildClassicPdf());
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    await tester.pumpWidget(Center(
      child: SizedBox(
        width: 612,
        child: PdfPageView(
          page: doc.page(0),
          focusDistance: 1,
          previewCache: cache,
        ),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(RawImage), findsOneWidget);
    expect(cache.debugRetainedSceneCount, 0,
        reason: 'the raster remains reusable without pinning the dense '
            'command transcript and picture in the session LRU');
  });

  testWidgets('raster resolution grows with width and stays sharp after shrink',
      (tester) async {
    // Regression: rasters were sized from the page's nominal point size,
    // so a page stretched across a wide window (or a big external
    // display) was upscaled and blurry.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    Widget at(double width) =>
        Center(child: SizedBox(width: width, child: PdfPageView(page: page)));

    await tester.pumpWidget(at(800));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final wide = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(wide.width, 800);

    await tester.pumpWidget(at(306));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final narrow = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(narrow, same(wide));
    expect(narrow.width, 800,
        reason: 'a resize down must reuse the sharper existing raster');
  });

  testWidgets('a visible non-focused page reaches final image resolution',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = buildEmbeddedFontImagePdf();
    final document = PdfDocument.open(bytes);
    final worker = _RatioRecordingWorker(_LocalCommandWorker(bytes));
    final performance = PdfPerformanceController();
    addTearDown(worker.dispose);
    addTearDown(performance.dispose);

    await tester.pumpWidget(Center(
      child: SizedBox(
        width: 1224,
        child: PdfPageView(
          page: document.page(0),
          renderWorker: worker,
          performance: performance,
          workerImagePixelRatioCap: 1.25,
          focusDistance: 1,
          onScreen: true,
        ),
      ),
    ));
    for (var i = 0; i < 200 && worker.imageRatios.length < 2; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }

    expect(worker.imageRatios, hasLength(greaterThanOrEqualTo(2)));
    expect(worker.imageRatios.first, moreOrLessEquals(2, epsilon: 0.01),
        reason: 'first content should use the visible physical footprint');
    expect(worker.imageRatios.last, moreOrLessEquals(4, epsilon: 0.01),
        reason: 'the adaptive cap may reduce speculative neighbours, but '
            'every visible page must refine with resampling headroom above its '
            '2x physical raster');
  });

  testWidgets('a focused mount rejects a retained reduced-image scene',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = buildEmbeddedFontImagePdf();
    final document = PdfDocument.open(bytes);
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    final worker = _RatioRecordingWorker(_LocalCommandWorker(bytes));
    final performance = PdfPerformanceController();
    addTearDown(cache.dispose);
    addTearDown(worker.dispose);
    addTearDown(performance.dispose);

    late PdfRetainedScene scene;
    late ui.Picture picture;
    await tester.runAsync(() async {
      scene = await PdfRetainedScene.record(page, maxImagePixelRatio: 1.25);
      picture = scene.replay(pixelRatio: 1);
    });
    final producer = cache.retainScene(
      0,
      page,
      scene,
      plan: const PdfPageRenderPlan(),
      fromWorker: false,
      imagePixelRatio: 1.25,
      estimatedBytes: 1,
      picture: picture,
    );
    producer.dispose();

    await tester.pumpWidget(Center(
      child: SizedBox(
        width: 1224,
        child: PdfPageView(
          page: page,
          renderWorker: worker,
          performance: performance,
          previewCache: cache,
          focusDistance: 0,
          onScreen: true,
        ),
      ),
    ));
    for (var i = 0; i < 200 && worker.imageRatios.length < 2; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }

    expect(worker.imageRatios, hasLength(greaterThanOrEqualTo(2)),
        reason: 'the focused page must re-record instead of flattening the '
            'retained low-LoD scene into a final raster');
    expect(worker.imageRatios.first, moreOrLessEquals(2, epsilon: 0.01));
    expect(worker.imageRatios.last, moreOrLessEquals(4, epsilon: 0.01),
        reason: 'the retained scene may look sufficient before first layout, '
            'but must be re-evaluated against the focused physical width and '
            'its final-quality resampling headroom');
  });

  testWidgets('a structural epoch bump drops the slot\'s stale raster',
      (tester) async {
    // The lazy page list has no per-page key, so after an insert/remove/
    // reorder a page State is reused for a different page in the same slot.
    // A bumped pageEpoch must drop the previous page's raster so a fast
    // scroll can't paint it for the page now in the slot. renderHold (raised
    // by the viewer during a fast scroll) keeps the re-render pending, so the
    // raster shown between the swap and the new render is observable.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    // varied heights (792, 396, 1008) let us tell the pages apart by raster.
    final doc = PdfDocument.open(buildVariedHeightPdf(3));
    final hold = ValueNotifier<bool>(false);
    addTearDown(hold.dispose);
    Widget at(PdfPage page, int epoch) => Center(
        child: SizedBox(
            width: 612,
            child:
                PdfPageView(page: page, pageEpoch: epoch, renderHold: hold)));

    await tester.pumpWidget(at(doc.page(0), 0));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.height, 792);

    // Hold renders (as during a fast scroll). A same-epoch page change (a
    // content-only edit reused the slot): the old raster is intentionally
    // kept and re-rendered in place when the hold releases - no blank flash.
    hold.value = true;
    await tester.pumpWidget(at(doc.page(2), 0));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.height, 792,
        reason: 'a same-geometry edit keeps the raster while the render holds');

    // Bumped epoch (a structural change put a different page in this slot):
    // the stale raster must drop now, before the held render lands - else the
    // fast scroll paints page 0's image for page 2.
    await tester.pumpWidget(at(doc.page(2), 1));
    await tester.pump();
    expect(find.byType(RawImage), findsNothing,
        reason: 'a structural epoch bump drops the previous page raster');

    // Releasing the hold re-renders for the page now in the slot.
    hold.value = false;
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.height, 1008);
  });

  testWidgets(
      'an additive content edit keeps the raster; a destructive one '
      'drops it', (tester) async {
    // After finishing an ink markup on a heavy page the document swaps and
    // the page's contentStamp advances. The old raster must stay painted
    // until the new render lands (the just-drawn markup rides on top via the
    // editing overlay) - otherwise the whole page flashes blank while the
    // slow re-interpret runs. A redaction burn, by contrast, advances the
    // destructiveStamp and must drop the (un-redacted) raster at once.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    final hold = ValueNotifier<bool>(false);
    addTearDown(hold.dispose);
    Widget at({int content = 0, int destructive = 0}) => Center(
        child: SizedBox(
            width: 612,
            child: PdfPageView(
                page: page,
                contentStamp: content,
                destructiveStamp: destructive,
                renderHold: hold)));

    await tester.pumpWidget(at());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);

    // Hold renders (as the viewer does while a heavy page re-interprets).
    // An additive edit (contentStamp bump) keeps the raster on screen.
    hold.value = true;
    await tester.pumpWidget(at(content: 1));
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget,
        reason: 'an additive edit must not flash the page blank');

    // A destructive edit (destructiveStamp bump) drops the raster at once so
    // the removed content can't linger before the re-render lands.
    await tester.pumpWidget(at(content: 1, destructive: 1));
    await tester.pump();
    expect(find.byType(RawImage), findsNothing,
        reason: 'a destructive edit drops the stale raster immediately');

    // Releasing the hold re-renders.
    hold.value = false;
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('an additive content edit keeps the detail patch until refreshed',
      (tester) async {
    // At deep zoom a sharp detail patch paints above the capped base raster.
    // After an annotation commit, keep that sharp patch while the editing
    // overlay's commit afterimage covers the new annotation. The overlay only
    // clears once the fresh detail patch has replaced it.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    final hold = ValueNotifier<bool>(false);
    addTearDown(hold.dispose);
    var ready = 0;
    Widget at({int content = 0}) => Center(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: 6120,
              child: PdfPageView(
                page: page,
                contentStamp: content,
                renderHold: hold,
                onRasterReady: () => ready++,
              ),
            ),
          ),
        );

    await tester.pumpWidget(at());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(RawImage), findsNWidgets(2),
        reason: 'base raster plus deep-zoom detail patch');
    expect(ready, 1);

    hold.value = true;
    await tester.pumpWidget(at(content: 1));
    await tester.pump();

    expect(find.byType(RawImage), findsAtLeastNWidgets(2),
        reason: 'the stale exact patch (and any completed pan-ahead layer) '
            'stay up for sharpness');
    expect(ready, 1,
        reason: 'the annotation afterimage must stay until a fresh detail '
            'patch is ready');
  });

  testWidgets('raster resolution is capped at deep zoom', (tester) async {
    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(child: PdfPageView(page: doc.page(0), scale: 1000)),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final images = tester
        .widgetList<RawImage>(find.byType(RawImage))
        .map((w) => w.image!)
        .toList();
    // the base raster plus the deep-zoom detail patch
    expect(images, hasLength(2));
    for (final image in images) {
      final pixelLimit = identical(image, images.first)
          ? PdfPageRasterGeometry.maxPixels
          : PdfPageRasterGeometry.maxDetailPixels;
      expect(image.width * image.height, lessThan(pixelLimit * 1.001));
      expect(image.width, lessThanOrEqualTo(8192));
      expect(image.height, lessThanOrEqualTo(8192));
    }
  });

  testWidgets('no detail patch below the raster caps', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 612,
          child: PdfPageView(page: doc.page(0)),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('the detail patch is sharper than the capped base',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    // page laid out 10x wider than its point size: only a slice fits the
    // viewport, so the patch covers a fraction of the page (OverflowBox
    // lets the page exceed the test surface without overflow errors)
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(width: 6120, child: PdfPageView(page: doc.page(0))),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final rawImages = find.byType(RawImage);
    expect(rawImages, findsNWidgets(2));
    final base = tester.widgetList<RawImage>(rawImages).first.image!;
    final patch = tester.widgetList<RawImage>(rawImages).last.image!;
    // The whole-page backing is deliberately much softer than the visible
    // patch once the view crosses the bounded base-raster budget.
    final baseDensity = base.width / 612;
    expect(baseDensity, lessThan(3));
    // patch density: raster pixels per page point of the area it covers
    final patchLayoutWidth = tester.getSize(rawImages.last).width;
    final patchPoints = patchLayoutWidth / 6120 * 612;
    expect(patch.width / patchPoints,
        moreOrLessEquals(10, epsilon: 0.5)); // the uncapped desired ratio
  });

  testWidgets('zoom and pan sharpen exactly the visible viewport',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    final logs = <String>[];
    final oldPerfEnabled = PdfPerfLog.enabled;
    final oldPerfSink = PdfPerfLog.sink;
    PdfPerfLog.enabled = true;
    PdfPerfLog.sink = logs.add;
    addTearDown(() {
      PdfPerfLog.enabled = oldPerfEnabled;
      PdfPerfLog.sink = oldPerfSink;
    });
    const detailKey = ValueKey('pdf-page-detail-image');

    Widget at(double scale, int generation, {double dx = 0}) => Center(
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: SizedBox(
                width: 6120,
                child: PdfPageView(
                  page: page,
                  scale: scale,
                  settleGeneration: generation,
                ),
              ),
            ),
          ),
        );

    Future<RawImage> waitForDetail({Object? differentFrom}) async {
      for (var i = 0; i < 200; i++) {
        await tester.pump();
        if (find.byKey(detailKey).evaluate().isNotEmpty) {
          final image = tester.widget<RawImage>(find.byKey(detailKey));
          if (differentFrom == null || !identical(image.image, differentFrom)) {
            return image;
          }
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      fail('detail patch did not reach the expected state');
    }

    await tester.pumpWidget(at(1, 0));
    final initial = await waitForDetail();

    // A scale-changing settle covers exactly the 800x600 visible slice:
    // 80x60 page points at ratio 20.
    await tester.pumpWidget(at(2, 1));
    final tight = await waitForDetail(differentFrom: initial.image);
    expect(tight.image!.width, closeTo(1600, 2));
    expect(tight.image!.height, closeTo(1200, 2));

    // A later pan first sharpens the same exact-visible 80x60pt patch. The
    // historical 50%-per-side guard made this 4x larger and delayed the first
    // sharp frame on image-heavy CAD pages.
    await tester.pumpWidget(at(2, 2, dx: -200));
    final panned = await waitForDetail(differentFrom: tight.image);
    expect(panned.image!.width, closeTo(1600, 2));
    expect(panned.image!.height, closeTo(1200, 2));
    expect(
      find.byKey(const ValueKey('pdf-page-detail-headroom-image')),
      findsNothing,
      reason: 'the fallback must not start an unpreemptible second raster',
    );
    final paintLogs = logs.where((line) => line.contains('detail paint'));
    expect(paintLogs.length, greaterThanOrEqualTo(3));
    expect(paintLogs, everyElement(contains('pass=visible')),
        reason: 'foreground time-to-sharp observations must survive later '
            'pan-ahead scheduling');
  });

  testWidgets('detail adoption rebalances reclaimable live rasters',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final budget = PdfLiveRasterBudget.instance;
    final oldMax = budget.maxBytes;
    final reclaimable = _BudgetProbeHolder(bytes: 1, distance: 9);
    addTearDown(() {
      budget.unregister(reclaimable);
      budget.maxBytes = oldMax;
    });

    final doc = PdfDocument.open(buildClassicPdf());
    Widget page(double scale, int generation) => Center(
          child: SizedBox(
            width: 612,
            child: PdfPageView(
              page: doc.page(0),
              baseRasterScale: 4,
              scale: scale,
              settleGeneration: generation,
            ),
          ),
        );

    await tester.pumpWidget(page(1, 0));
    for (var i = 0; i < 200 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    // Drain the base raster's own post-frame rebalance before introducing the
    // probe. The scale change below retains that capped base and adds only the
    // exact deep-zoom detail allocation.
    await tester.pump();
    budget.register(reclaimable);
    budget.maxBytes = budget.totalBytes - 1;

    await tester.pumpWidget(page(8, 1));
    for (var i = 0; i < 300 && !reclaimable.evicted; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(reclaimable.evicted, isTrue,
        reason: 'retaining the new detail image must run the global budget');
  });

  testWidgets('deep zoom reuses a current fit raster as its base',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);

    Widget at(double scale) => Center(
          child: SizedBox(
            width: 612,
            child: PdfPageView(page: page, scale: scale),
          ),
        );

    await tester.pumpWidget(at(1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final fitRaster =
        tester.widgetList<RawImage>(find.byType(RawImage)).first.image!;
    expect(fitRaster.width, 612);

    await tester.pumpWidget(at(1000));
    for (var i = 0; i < 200; i++) {
      await tester.pump();
      if (find
          .byKey(const ValueKey('pdf-page-detail-image'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }

    final images = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
    expect(images, hasLength(2), reason: 'base raster plus sharp detail');
    expect(images.first.image, same(fitRaster),
        reason: 'deep zoom must not replace the whole-page backing raster');
  });

  testWidgets('exact detail reuse still validates current content',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    PdfPageView.debugDetailPatchReuses = 0;
    addTearDown(() => PdfPageView.debugDetailPatchReuses = 0);

    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    const detailKey = ValueKey('pdf-page-detail-image');

    Widget at(double dx, int generation, {int contentStamp = 0}) => Center(
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: SizedBox(
                width: 6120,
                child: PdfPageView(
                  page: page,
                  contentStamp: contentStamp,
                  settleGeneration: generation,
                ),
              ),
            ),
          ),
        );

    Object detailImage() =>
        tester.widget<RawImage>(find.byKey(detailKey)).image!;

    Future<void> waitForDetail({Object? differentFrom}) async {
      for (var i = 0; i < 200; i++) {
        await tester.pump();
        if (find.byKey(detailKey).evaluate().isNotEmpty) {
          final image = detailImage();
          if (differentFrom == null || !identical(image, differentFrom)) return;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      fail('detail patch did not reach the expected state');
    }

    await tester.pumpWidget(at(0, 0));
    await waitForDetail();
    final visible = detailImage();

    // A settle with unchanged geometry reuses the exact current patch.
    await tester.pumpWidget(at(0, 1));
    for (var i = 0; i < 20 && PdfPageView.debugDetailPatchReuses == 0; i++) {
      await tester.pump();
    }
    expect(PdfPageView.debugDetailPatchReuses, 1);
    expect(detailImage(), same(visible));

    // An additive edit leaves the old sharp patch painted while the
    // replacement is rendering. It must not be mistaken for reusable current
    // content even though its geometry still covers the viewport.
    await tester.pumpWidget(at(0, 2, contentStamp: 1));
    await waitForDetail(differentFrom: visible);
    final edited = detailImage();
    expect(PdfPageView.debugDetailPatchReuses, 1);

    // A moved viewport no longer fits the exact patch, so a replacement lands.
    await tester.pumpWidget(at(-1000, 3, contentStamp: 1));
    await waitForDetail(differentFrom: edited);
    expect(PdfPageView.debugDetailPatchReuses, 1);
  });
}

class _BudgetProbeHolder implements PdfLiveRasterHolder {
  _BudgetProbeHolder({required int bytes, required this.distance})
      : _bytes = bytes;

  int _bytes;
  final int distance;
  bool evicted = false;

  @override
  int get liveRasterBytes => _bytes;

  @override
  int get liveRasterDistance => distance;

  @override
  bool get liveRasterOnScreen => false;

  @override
  void evictLiveRaster() {
    evicted = true;
    _bytes = 0;
  }
}

class _DeferredRecordWorker extends PdfRenderWorker {
  _DeferredRecordWorker(this._inner);

  final PdfRenderWorker _inner;
  Completer<void>? _gate;
  bool _released = false;

  bool get hasPending => _gate != null;

  void release() {
    _released = true;
    final gate = _gate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  bool get isActive => _inner.isActive;

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
    final result = await _inner.record(
      pageIndex,
      annotations: annotations,
      priority: priority,
      imagePixelRatio: imagePixelRatio,
      decodeImages: decodeImages,
      commandLimit: commandLimit,
      imageDecodeRegion: imageDecodeRegion,
      onPartial: onPartial,
    );
    if (_released) return result;
    final gate = _gate = Completer<void>();
    await gate.future;
    _gate = null;
    return result;
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {
    // Deliberately keep the result alive: this test exercises the post-await
    // visibility gate rather than the worker cancellation path.
  }

  @override
  void dispose() {
    release();
    _inner.dispose();
  }
}

class _RatioRecordingWorker extends PdfRenderWorker {
  _RatioRecordingWorker(this._inner);

  final PdfRenderWorker _inner;
  final List<double> imageRatios = [];

  @override
  bool get isActive => _inner.isActive;

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
    if (decodeImages && imagePixelRatio != null) {
      imageRatios.add(imagePixelRatio);
    }
    return _inner.record(
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
  void cancel(int pageIndex, {int priority = 0}) =>
      _inner.cancel(pageIndex, priority: priority);

  @override
  void dispose() => _inner.dispose();
}

/// In-process command worker used by the image-LoD tests. The production
/// isolate may deliberately decline an inline-image buffer on some platforms,
/// which would exercise PdfPageView's single-pass local fallback instead of
/// the worker-backed staged refinement these tests pin.
class _LocalCommandWorker extends PdfRenderWorker {
  _LocalCommandWorker(List<int> bytes)
      : _document = PdfDocument.open(Uint8List.fromList(bytes));

  final PdfDocument _document;
  bool _disposed = false;

  @override
  bool get isActive => !_disposed;

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
    if (_disposed || pageIndex < 0 || pageIndex >= _document.pageCount) {
      return null;
    }
    final page = _document.page(pageIndex);
    final recorder = RecordingPdfDevice();
    final interpreter = PdfInterpreter(cos: _document.cos, device: recorder)
      ..drawPageContent(page, page.contentBytes());
    if (annotations) interpreter.drawAnnotations(page);
    return recorder.commands;
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() => _disposed = true;
}
