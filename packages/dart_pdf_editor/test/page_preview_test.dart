// Low-res fast-scroll previews: pages whose full render is pending (the
// render hold, or simply not interpreted yet) paint a small cached
// raster instead of blank paper - Bluebeam-style. The cache is fed for
// free from on-screen renders and by the viewer's background prerender.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<ui.Image> _solidImage(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

void main() {
  /// Lets the real async renderer make progress, then pumps a frame.
  Future<void> settle(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }

  // previews are ≤200px on their longest side; full rasters are far bigger
  final previewRaster = find.byWidgetPredicate((w) =>
      w is RawImage &&
      w.image != null &&
      w.image!.width <= 200 &&
      w.image!.height <= 200);
  final fullRaster = find.byWidgetPredicate((w) =>
      w is RawImage &&
      w.image != null &&
      (w.image!.width > 200 || w.image!.height > 200));

  testWidgets('cache stores, evicts least-recently-used, clones survive',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(4));
    final cache = PdfPagePreviewCache(capacity: 2);
    addTearDown(cache.dispose);
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await cache.renderPreview(i, document.page(i));
      }
    });
    expect(cache.has(0), isFalse); // oldest, evicted at capacity 2
    expect(cache.has(1), isTrue);
    expect(cache.has(2), isTrue);

    // a lookup counts as a use: 2 becomes the eviction candidate
    final clone = cache.imageFor(1)!;
    await tester.runAsync(() => cache.renderPreview(3, document.page(3)));
    expect(cache.has(2), isFalse);
    expect(cache.has(1), isTrue);

    // handed-out clones keep their pixels through clear()
    cache.clear();
    expect(cache.has(1), isFalse);
    expect(clone.width, greaterThan(0));
    expect(clone.width, lessThanOrEqualTo(200));
    clone.dispose();
  });

  testWidgets('a complete preview can satisfy a smaller physical raster',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    await tester.runAsync(() => cache.renderPreview(0, page));

    final preview = cache.imageFor(0)!;
    final sufficient = cache.completeImageFor(
      0,
      page,
      width: preview.width,
      height: preview.height,
    );
    expect(sufficient, isNotNull);
    sufficient!.dispose();
    expect(
      cache.completeImageFor(
        0,
        page,
        width: preview.width + 1,
        height: preview.height,
      ),
      isNull,
    );
    preview.dispose();
  });

  testWidgets('a complete intermediate preview satisfies a thumbnail',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    await tester.runAsync(() => cache.renderPreview(
          0,
          page,
          targetLongestSide: 400,
        ));

    final sufficient = cache.completeImageFor(
      0,
      page,
      width: 256,
      height: 330,
    );
    expect(sufficient, isNotNull,
        reason: 'the sharpest preview tier is not limited to the 200px base');
    final image = sufficient!;
    expect(math.max(image.width, image.height), 400);
    image.dispose();
  });

  testWidgets('a sufficient preview bypasses first-render hold',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    final scheduler = PdfPageRenderScheduler()..holding = true;
    addTearDown(cache.dispose);
    addTearDown(scheduler.dispose);
    await tester.runAsync(() => cache.renderPreview(0, page));
    var ready = 0;

    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          // Flutter widget tests default to a 3x device-pixel ratio. Keep the
          // physical target below the cache's 200 px preview ceiling.
          width: 40,
          child: PdfPageView(
            page: page,
            previewCache: cache,
            renderScheduler: scheduler,
            onRasterReady: () => ready++,
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(ready, 1);
    expect(scheduler.hasPending, isFalse,
        reason: 'an already-sharp complete preview needs no interpretation');
  });

  test('priceRetainedScene floors a scene at the raster it stands in for', () {
    // The engine's own picture estimate under-reports a text page by an order
    // of magnitude, which made the byte budget meaningless and mislead the
    // process-wide cache registry. The floor is the page's own raster.
    const letterPageRaster = 1224 * 1584 * 4; // ~7.8 MB
    expect(
      PdfPagePreviewCache.priceRetainedScene(
        commandCount: 38,
        pictureBytes: 490000,
        decodedImageBytes: 0,
        rasterBytes: letterPageRaster,
      ),
      letterPageRaster,
    );
    // A page whose own parts genuinely cost more than its raster keeps its
    // real price - decoded images are counted honestly and always add.
    expect(
      PdfPagePreviewCache.priceRetainedScene(
        commandCount: 200000,
        pictureBytes: 40 << 20,
        decodedImageBytes: 8 << 20,
        rasterBytes: letterPageRaster,
      ),
      200000 * 260 + (40 << 20) + (8 << 20),
    );
  });

  testWidgets('the retained-scene LRU holds a run of ordinary pages',
      (tester) async {
    // On the direct picture-presentation path a revisited page repaints from
    // its retained scene with no record, no replay and no worker round trip.
    // The entry cap used to be 4 for the whole document, so reading a long
    // text document threw away pages it had shown seconds earlier. Now the
    // byte budget decides, and it holds a run of them.
    const pages = 12;
    const pageRaster = 1224 * 1584 * 4; // ~7.8 MB, a letter page at fit width
    final document = PdfDocument.open(buildMultiPagePdf(pages));
    final cache = PdfPagePreviewCache(maxRetainedSceneBytes: 64 << 20);
    addTearDown(cache.dispose);
    for (var i = 0; i < pages; i++) {
      final page = document.page(i);
      late PdfRetainedScene scene;
      await tester.runAsync(() async {
        scene = await PdfRetainedScene.record(page);
      });
      cache
          .retainScene(
            i,
            page,
            scene,
            plan: const PdfPageRenderPlan(),
            fromWorker: true,
            estimatedBytes: PdfPagePreviewCache.priceRetainedScene(
              commandCount: scene.commands.length,
              pictureBytes: 490000,
              decodedImageBytes: 0,
              rasterBytes: pageRaster,
            ),
          )
          .dispose();
    }
    expect(cache.debugRetainedSceneCount, (64 << 20) ~/ pageRaster);
    // ...and they are the pages just read, not the ones read first.
    final recent = cache.retainedSceneFor(pages - 1, document.page(pages - 1),
        plan: const PdfPageRenderPlan());
    expect(recent, isNotNull);
    recent!.dispose();
    expect(
      cache.retainedSceneFor(0, document.page(0),
          plan: const PdfPageRenderPlan()),
      isNull,
    );
  });

  testWidgets('the retained-scene byte budget still governs heavy pages',
      (tester) async {
    // A document of dense sheets must still stop at the byte budget, exactly
    // as it did when the entry cap was the binding limit.
    final document = PdfDocument.open(buildMultiPagePdf(8));
    final cache = PdfPagePreviewCache(maxRetainedSceneBytes: 16 << 20);
    addTearDown(cache.dispose);
    for (var i = 0; i < 8; i++) {
      final page = document.page(i);
      late PdfRetainedScene scene;
      await tester.runAsync(() async {
        scene = await PdfRetainedScene.record(page);
      });
      cache
          .retainScene(
            i,
            page,
            scene,
            plan: const PdfPageRenderPlan(),
            fromWorker: true,
            estimatedBytes: 8 << 20, // a dense sheet's scene
          )
          .dispose();
    }
    expect(cache.debugRetainedSceneCount, 2);
    expect(cache.debugRetainedSceneBytes, 16 << 20);
  });

  testWidgets('retained scene leases survive LRU eviction until released',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(2));
    final first = document.page(0);
    final second = document.page(1);
    final cache = PdfPagePreviewCache(
      maxRetainedSceneBytes: 1024,
      maxRetainedSceneEntries: 1,
    );
    addTearDown(cache.dispose);
    late PdfRetainedScene firstScene;
    late PdfRetainedScene secondScene;
    await tester.runAsync(() async {
      firstScene = await PdfRetainedScene.record(first);
      secondScene = await PdfRetainedScene.record(second);
    });

    final firstLease = cache.retainScene(
      0,
      first,
      firstScene,
      plan: const PdfPageRenderPlan(),
      fromWorker: true,
      imagePixelRatio: 0.5,
      estimatedBytes: 1,
    );
    expect(cache.debugRetainedSceneCount, 1);
    final lookup = cache.retainedSceneFor(
      0,
      first,
      plan: const PdfPageRenderPlan(),
    );
    expect(lookup, isNotNull);
    expect(identical(lookup!.scene, firstScene), isTrue);
    expect(lookup.imagePixelRatio, 0.5,
        reason: 'a restored scene must preserve its embedded-image LoD');

    final secondLease = cache.retainScene(
      1,
      second,
      secondScene,
      plan: const PdfPageRenderPlan(),
      fromWorker: false,
      imagePixelRatio: null,
      estimatedBytes: 1,
    );
    expect(cache.debugRetainedSceneCount, 1);
    expect(
      cache.retainedSceneFor(0, first, plan: const PdfPageRenderPlan()),
      isNull,
      reason: 'the one-entry LRU evicts the first cache reference',
    );

    // Both outstanding leases still pin the evicted scene and can replay it.
    final picture = firstLease.scene.replay(pixelRatio: 1);
    picture.dispose();
    firstLease.dispose();
    final secondPicture = lookup.scene.replay(pixelRatio: 1);
    secondPicture.dispose();
    lookup.dispose();
    expect(() => firstScene.replay(pixelRatio: 1), throwsAssertionError,
        reason: 'the final lease releases an already-evicted scene');

    secondLease.dispose();
  });

  testWidgets('rebind preserves retained scenes for identity-stable pages',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(2));
    final cleanPage = document.page(0);
    final oldDirtyPage = document.page(1);
    final newDirtyPage = oldDirtyPage.forIncrementalRevision(
      document,
      oldDirtyPage.dict,
    );
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);

    for (final (index, page) in [cleanPage, oldDirtyPage].indexed) {
      late PdfRetainedScene scene;
      await tester.runAsync(() async {
        scene = await PdfRetainedScene.record(page);
      });
      cache
          .retainScene(
            index,
            page,
            scene,
            plan: const PdfPageRenderPlan(),
            fromWorker: false,
            estimatedBytes: 1,
          )
          .dispose();
    }

    cache.rebind([cleanPage, newDirtyPage], changed: (index) => index == 1);

    expect(cache.debugRetainedSceneCount, 1);
    final clean = cache.retainedSceneFor(
      0,
      cleanPage,
      plan: const PdfPageRenderPlan(),
    );
    expect(clean, isNotNull);
    clean!.dispose();
    expect(
      cache.retainedSceneFor(
        1,
        newDirtyPage,
        plan: const PdfPageRenderPlan(),
      ),
      isNull,
    );
  });

  testWidgets('cache promotes through a geometric preview ladder',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    const levels = [400.0, 800.0];
    final cache = PdfPagePreviewCache(
      lodPolicy: const PdfPagePreviewLodPolicy(
        intermediateLongestSides: levels,
        maxBytes: 8 * 1024 * 1024,
        maxEntryBytes: 4 * 1024 * 1024,
      ),
    );
    addTearDown(cache.dispose);

    await tester.runAsync(() async {
      await cache.renderPreview(0, page);
      await cache.renderPreview(0, page, targetLongestSide: levels[0]);
      await cache.renderPreview(0, page, targetLongestSide: levels[1]);
    });

    expect(cache.hasIntermediate(0, targetLongestSide: levels[0]), isTrue);
    expect(cache.hasIntermediate(0, targetLongestSide: levels[1]), isTrue);
    expect(cache.lodStats.baseEntries, 1);
    expect(cache.lodStats.intermediateEntries, 2);
    expect(
        cache.lodStats.intermediateBytes, lessThanOrEqualTo(8 * 1024 * 1024));

    final frame = cache.previewFor(0)!;
    expect(frame.lod, PdfPagePreviewLod.intermediate);
    expect(frame.targetLongestSide, levels[1]);
    expect(math.max(frame.image.width, frame.image.height),
        inInclusiveRange(790, 800),
        reason: 'preview ratios do not upscale a sub-800pt page past 1x');
    frame.image.dispose();
  });

  testWidgets('one interpret fills every rung of the preview ladder',
      (tester) async {
    // #699: the ladder's rungs differ only in raster size, so warming them
    // one call at a time walked the same content stream once per rung.
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    const levels = [400.0, 800.0];
    PdfPagePreviewCache build() => PdfPagePreviewCache(
          lodPolicy: const PdfPagePreviewLodPolicy(
            intermediateLongestSides: levels,
            maxBytes: 8 * 1024 * 1024,
            maxEntryBytes: 4 * 1024 * 1024,
          ),
        );

    final perRung = build();
    addTearDown(perRung.dispose);
    final shared = build();
    addTearDown(shared.dispose);

    late final int perRungOps;
    late final int sharedOps;
    await tester.runAsync(() async {
      PdfPerf.enabled = true;
      addTearDown(() => PdfPerf.enabled = false);
      PdfPerf.reset();
      await perRung.renderPreview(0, page);
      await perRung.renderPreview(0, page, targetLongestSide: levels[0]);
      await perRung.renderPreview(0, page, targetLongestSide: levels[1]);
      perRungOps = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
      PdfPerf.reset();
      await shared.renderPreview(0, page, alsoFillLongestSides: levels);
      sharedOps = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
    });

    expect(sharedOps, greaterThan(0));
    expect(perRungOps, sharedOps * 3,
        reason: 'a rung per call tokenizes the page three times over; the '
            'ladder build tokenizes it once and rasterizes each rung from '
            'that one record');
    for (final cache in [perRung, shared]) {
      expect(cache.isFresh(0, page, requireImages: true), isTrue);
      expect(cache.hasIntermediate(0, targetLongestSide: levels[0]), isTrue);
      expect(cache.hasIntermediate(0, targetLongestSide: levels[1]), isTrue);
    }
    final sharpest = shared.previewFor(0)!;
    expect(sharpest.targetLongestSide, levels[1]);
    expect(math.max(sharpest.image.width, sharpest.image.height),
        inInclusiveRange(790, 800),
        reason: 'the sharpest rung is rasterized at its own ratio, not '
            'upscaled from the base preview');
    sharpest.image.dispose();
  });

  testWidgets('the ladder builds every rung from a retained scene',
      (tester) async {
    // #699: the ladder was the half of the "build the page once" fix left
    // interpreting. A page the viewer is still holding has already been
    // walked; its retained scene carries exactly the commands a worker record
    // would ship back, so the whole ladder should cost replays and rasters -
    // no content-stream walk at all.
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    const levels = [400.0, 800.0];
    final cache = PdfPagePreviewCache(
      lodPolicy: const PdfPagePreviewLodPolicy(
        intermediateLongestSides: levels,
        maxBytes: 8 * 1024 * 1024,
        maxEntryBytes: 4 * 1024 * 1024,
      ),
    );
    addTearDown(cache.dispose);
    const plan = PdfPageRenderPlan(
      pageColor: Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );

    late final int ops;
    final logs = <String>[];
    await tester.runAsync(() async {
      final scene = await PdfRetainedScene.record(page, plan: plan);
      cache
          .retainScene(0, page, scene,
              plan: plan, fromWorker: false, estimatedBytes: 1 << 20)
          .dispose(); // the cache keeps its own reference
      PdfPerf.enabled = true;
      addTearDown(() => PdfPerf.enabled = false);
      PdfPerf.reset();
      PdfPerfLog.enabled = true;
      PdfPerfLog.sink = logs.add;
      addTearDown(() {
        PdfPerfLog.enabled = false;
        PdfPerfLog.sink = null;
      });
      await cache.renderPreview(0, page, alsoFillLongestSides: levels);
      ops = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
    });

    expect(ops, 0,
        reason: 'the retained scene is replayed, never re-interpreted');
    expect(cache.isFresh(0, page, requireImages: true), isTrue);
    expect(cache.hasIntermediate(0, targetLongestSide: levels[0]), isTrue);
    expect(cache.hasIntermediate(0, targetLongestSide: levels[1]), isTrue);
    expect(
      logs.where((line) => line.contains('prerender page=0')).length,
      3,
      reason: 'every rung still reports its own cost',
    );
    expect(logs.every((line) => !line.contains('prerender page=0') ||
        line.contains('retained ')), isTrue);
    final sharpest = cache.previewFor(0)!;
    expect(sharpest.targetLongestSide, levels[1]);
    expect(math.max(sharpest.image.width, sharpest.image.height),
        inInclusiveRange(790, 800));
    sharpest.image.dispose();
  });

  testWidgets('a ladder deferred mid-flight releases the scene it leased',
      (tester) async {
    // Taking a lease and then bailing out has to give it back: a leaked lease
    // pins the scene past the cache's own reference, so the memory the LRU
    // thinks it freed is still held. The motion gate makes this the common
    // exit, not a rare one.
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    const plan = PdfPageRenderPlan(
      pageColor: Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );

    late final PdfRetainedScene scene;
    await tester.runAsync(() async {
      scene = await PdfRetainedScene.record(page, plan: plan);
      cache
          .retainScene(0, page, scene,
              plan: plan, fromWorker: false, estimatedBytes: 1 << 20)
          .dispose(); // the cache keeps its own reference
      await cache.renderPreview(0, page, deferUiWork: () => true);
    });

    expect(cache.isFresh(0, page, requireImages: true), isFalse,
        reason: 'the pass declined before storing anything');
    cache.dispose(); // drops the cache's own reference
    expect(() => scene.replay(pixelRatio: 1), throwsAssertionError,
        reason: 'with the lease returned, disposing the cache frees the scene');
  });

  testWidgets('a soft-image retained scene is declined by the ladder',
      (tester) async {
    // The guard the reuse rests on: a scene whose images were decoded below
    // the sharpest rung's ratio would draw them softer than a fresh record,
    // so the ordinary interpret runs instead.
    final document = PdfDocument.open(buildSyntheticRasterUnderlaySheet(
      underlays: const [PdfUnderlaySpec(width: 256, height: 256)],
      layers: 1,
      ops: 0,
      pageW: 256,
      pageH: 256,
    ));
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    const plan = PdfPageRenderPlan(
      pageColor: Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );

    late final int ops;
    await tester.runAsync(() async {
      final scene = await PdfRetainedScene.record(page, plan: plan);
      cache
          .retainScene(0, page, scene,
              plan: plan,
              fromWorker: false,
              estimatedBytes: 1 << 20,
              imagePixelRatio: 0.1)
          .dispose();
      PdfPerf.enabled = true;
      addTearDown(() => PdfPerf.enabled = false);
      PdfPerf.reset();
      await cache.renderPreview(0, page);
      ops = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
    });

    expect(ops, greaterThan(0),
        reason: 'a scene decoded below the rung ratio must not serve it');
    expect(cache.isFresh(0, page, requireImages: true), isTrue);
  });

  testWidgets('a ladder build skips rungs that are already fresh',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    const levels = [400.0, 800.0];
    final cache = PdfPagePreviewCache(
      lodPolicy: const PdfPagePreviewLodPolicy(
        intermediateLongestSides: levels,
        maxBytes: 8 * 1024 * 1024,
        maxEntryBytes: 4 * 1024 * 1024,
      ),
    );
    addTearDown(cache.dispose);

    late final int ops;
    await tester.runAsync(() async {
      await cache.renderPreview(0, page, alsoFillLongestSides: levels);
      PdfPerf.enabled = true;
      addTearDown(() => PdfPerf.enabled = false);
      PdfPerf.reset();
      await cache.renderPreview(0, page, alsoFillLongestSides: levels);
      ops = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
    });

    expect(ops, 0,
        reason: 'nothing is missing, so the page is not recorded at all');
  });

  testWidgets('a late intermediate promotion cannot cross page revisions',
      (tester) async {
    final before = PdfDocument.open(buildClassicPdf());
    final after = PdfDocument.open(buildClassicPdf());
    final oldPage = before.page(0);
    final newPage = after.page(0);
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    cache.bindPages([oldPage]);

    await tester.runAsync(() async {
      final image = await PdfPageRenderer.renderImage(oldPage);
      cache.putFullImage(
        0,
        oldPage,
        image,
        pageColor: Colors.white,
        annotations: true,
        rotation: null,
      );
      // The 400/800px scales are asynchronous. Invalidate their source page
      // before they finish, exactly as a destructive edit does.
      cache.rebind([newPage], changed: (_) => true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      image.dispose();
    });

    expect(cache.hasIntermediate(0), isFalse);
    expect(cache.fullRasterCount, 0);
  });

  testWidgets('intermediate levels share a configurable byte LRU',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    const levels = [400.0, 800.0];
    final cache = PdfPagePreviewCache(
      lodPolicy: const PdfPagePreviewLodPolicy(
        intermediateLongestSides: levels,
        maxBytes: 8 * 1024 * 1024,
        maxEntryBytes: 4 * 1024 * 1024,
      ),
    );
    addTearDown(cache.dispose);
    await tester.runAsync(() async {
      await cache.renderPreview(0, page, targetLongestSide: levels[0]);
      await cache.renderPreview(0, page, targetLongestSide: levels[1]);
    });
    final sharp = cache.previewFor(0)!;
    final sharpBytes = sharp.image.width * sharp.image.height * 4;
    sharp.image.dispose();

    cache.configurePreviewLods(PdfPagePreviewLodPolicy(
      intermediateLongestSides: levels,
      maxBytes: sharpBytes,
      maxEntryBytes: sharpBytes,
    ));

    expect(cache.intermediateBytes, lessThanOrEqualTo(sharpBytes));
    expect(cache.intermediateCount, 1,
        reason: 'the shared budget should retain the touched 800px level');
    expect(cache.hasIntermediate(0, targetLongestSide: levels[0]), isFalse);
    expect(cache.hasIntermediate(0, targetLongestSide: levels[1]), isTrue);
  });

  testWidgets('exact raster cache enforces entry and total pixel budgets',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(2));
    final first = document.page(0);
    final second = document.page(1);
    final image = await PdfPageRenderer.renderImage(first, pixelRatio: 0.5);
    addTearDown(image.dispose);
    final pixels = image.width * image.height;
    final cache = PdfPagePreviewCache(
      maxFullRasterPixels: pixels + 1,
      maxFullRasterEntryPixels: pixels,
    );
    addTearDown(cache.dispose);

    void put(int index, PdfPage page) => cache.putFullImage(
          index,
          page,
          image,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          rotation: null,
        );

    put(0, first);
    expect(cache.debugFullRasterPixels, pixels);
    put(1, second);
    expect(cache.debugFullRasterPixels, pixels,
        reason: 'the second exact raster evicts the first under the budget');
    expect(
      cache.fullImageFor(
        0,
        first,
        width: image.width,
        height: image.height,
        pageColor: const Color(0xFFFFFFFF),
        annotations: true,
        rotation: null,
      ),
      isNull,
    );
    final retained = cache.fullImageFor(
      1,
      second,
      width: image.width,
      height: image.height,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    expect(retained, isNotNull);
    retained!.dispose();

    final rejecting = PdfPagePreviewCache(
      maxFullRasterPixels: pixels,
      maxFullRasterEntryPixels: pixels - 1,
    );
    addTearDown(rejecting.dispose);
    rejecting.putFullImage(
      0,
      first,
      image,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    expect(rejecting.debugFullRasterPixels, 0,
        reason: 'oversized pages remain on the scheduled render path');
  });

  testWidgets('byte policy raises and trims the visited-page raster cache',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(2));
    final first = document.page(0);
    final second = document.page(1);
    final image = await PdfPageRenderer.renderImage(first, pixelRatio: 0.5);
    addTearDown(image.dispose);
    final imageBytes = image.width * image.height * 4;
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);

    cache.configureFullRasterCache(PdfPageRasterCachePolicy(
      maxBytes: imageBytes * 2,
      maxEntryBytes: imageBytes,
    ));
    expect(cache.maxFullRasterBytes, imageBytes * 2);
    cache.putFullImage(
      0,
      first,
      image,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    cache.putFullImage(
      1,
      second,
      image,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    expect(cache.fullRasterCount, 2);
    expect(cache.fullRasterBytes, imageBytes * 2);

    cache.configureFullRasterCache(PdfPageRasterCachePolicy(
      maxBytes: imageBytes,
      maxEntryBytes: imageBytes,
    ));
    expect(cache.fullRasterCount, 1,
        reason: 'lowering the total budget trims the LRU immediately');
    expect(cache.fullRasterBytes, imageBytes);

    cache.configureFullRasterCache(PdfPageRasterCachePolicy(
      maxBytes: imageBytes,
      maxEntryBytes: imageBytes - 1,
    ));
    expect(cache.fullRasterCount, 0,
        reason: 'lowering the entry limit drops oversized retained pages');
  });

  testWidgets('geometry variants coexist; a stale revision does not',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(1));
    final page = document.page(0);
    final image = await PdfPageRenderer.renderImage(page, pixelRatio: 0.5);
    addTearDown(image.dispose);
    final zoomed = await PdfPageRenderer.renderImage(page, pixelRatio: 0.75);
    addTearDown(zoomed.dispose);
    final third = await PdfPageRenderer.renderImage(page, pixelRatio: 0.9);
    addTearDown(third.dispose);
    final bytes = image.width * image.height * 4;
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);

    cache.configureFullRasterCache(PdfPageRasterCachePolicy(
      maxBytes: bytes * 16,
      maxEntryBytes: bytes * 8,
    ));
    void put(ui.Image raster) => cache.putFullImage(
          0,
          page,
          raster,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          rotation: null,
        );
    ui.Image? lookup(ui.Image raster, {PdfPage? revision}) =>
        cache.fullImageFor(
          0,
          revision ?? page,
          width: raster.width,
          height: raster.height,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          rotation: null,
        );

    put(image);
    expect(cache.fullRasterCount, 1);

    // A lookup at another resolution is a miss - but it must NOT throw away the
    // fit-size raster, which is exactly what the idle warm bakes and what a
    // zoom back out will want. Keying the cache by page index alone meant
    // storing (or warming) one size overwrote the other.
    expect(lookup(zoomed), isNull);
    expect(cache.fullRasterCount, 1,
        reason: 'a lookup at another geometry leaves the entry it did not ask '
            'for alone');

    put(zoomed);
    expect(cache.fullRasterCount, 2, reason: 'both variants are retained');
    final fit = lookup(image);
    expect(fit, isNotNull, reason: 'the fit-size raster survived the zoom');
    fit!.dispose();

    // Two is the cap: a third resolution drops the least-recently-used exact
    // variant rather than letting a page accumulate stale rasters. The new
    // sharper variant can nevertheless satisfy a lookup at that evicted
    // intermediate size by scaling down, avoiding a redundant render.
    put(third);
    expect(cache.fullRasterCount, 2);
    final downsampled = lookup(zoomed);
    expect(downsampled, isNotNull);
    expect(downsampled!.width, third.width);
    expect(downsampled.height, third.height);
    downsampled.dispose();

    // The inverse is never allowed: a smaller retained raster must not be
    // stretched up to satisfy a sharper request.
    final tooSharp = cache.fullImageFor(
      0,
      page,
      width: third.width + 1,
      height: third.height + 1,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    expect(tooSharp, isNull);

    // Nor may a physically larger but differently-shaped image masquerade as
    // the same page geometry.
    final wrongShape = await _solidImage(
      third.width + 100,
      third.height,
      const Color(0xFF123456),
    );
    addTearDown(wrongShape.dispose);
    final wrongShapeCache = PdfPagePreviewCache();
    addTearDown(wrongShapeCache.dispose);
    wrongShapeCache.putFullImage(
      0,
      page,
      wrongShape,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    final aspectMismatch = wrongShapeCache.fullImageFor(
      0,
      page,
      width: third.width,
      height: third.height,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    expect(aspectMismatch, isNull);

    // A revision swap is different in kind: those pixels are of a page that no
    // longer exists, so every variant of it goes.
    final nextRevision = PdfDocument.open(buildMultiPagePdf(1)).page(0);
    expect(lookup(third, revision: nextRevision), isNull);
    expect(cache.fullRasterCount, 0,
        reason: 'a stale-revision raster is dropped, not left holding budget');
    expect(cache.fullRasterBytes, 0);
  });

  testWidgets('visited-page raster perf trace explains cache decisions',
      (tester) async {
    final logs = <String>[];
    PdfPerfLog.sink = logs.add;
    PdfPerfLog.enabled = true;
    addTearDown(() {
      PdfPerfLog.enabled = false;
      PdfPerfLog.sink = null;
    });

    final document = PdfDocument.open(buildMultiPagePdf(2));
    final first = document.page(0);
    final second = document.page(1);
    final image = await PdfPageRenderer.renderImage(first, pixelRatio: 0.5);
    addTearDown(image.dispose);
    final bytes = image.width * image.height * 4;
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);

    cache.configureFullRasterCache(PdfPageRasterCachePolicy(
      maxBytes: bytes,
      maxEntryBytes: bytes,
    ));
    cache.putFullImage(
      0,
      first,
      image,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    cache.putFullImage(
      1,
      second,
      image,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    final hit = cache.fullImageFor(
      1,
      second,
      width: image.width,
      height: image.height,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    hit?.dispose();
    expect(
      cache.fullImageFor(
        0,
        first,
        width: image.width,
        height: image.height,
        pageColor: const Color(0xFFFFFFFF),
        annotations: true,
        rotation: null,
      ),
      isNull,
    );

    cache.configureFullRasterCache(PdfPageRasterCachePolicy(
      maxBytes: bytes,
      maxEntryBytes: bytes - 1,
    ));
    cache.putFullImage(
      0,
      first,
      image,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );

    expect(
        logs.any((line) => line.contains('page-raster policy total=')), isTrue);
    expect(
        logs.any((line) => line.contains('page-raster store page=0')), isTrue);
    expect(
        logs.any((line) => line.contains('page-raster evict page=0')), isTrue);
    expect(logs.any((line) => line.contains('page-raster hit page=1')), isTrue);
    expect(
      logs.any((line) =>
          line.contains('page-raster miss page=0') &&
          line.contains('reason=empty')),
      isTrue,
    );
    expect(
      logs.any((line) =>
          line.contains('page-raster reject page=0') &&
          line.contains('reason=entry-limit')),
      isTrue,
    );
  });

  test('visited-page rasters join and leave process-wide accounting', () {
    final registry = PdfCacheRegistry.instance;
    final before = registry.registrationCount;
    final cache = PdfPagePreviewCache();

    cache.configureFullRasterCache(const PdfPageRasterCachePolicy());
    expect(registry.registrationCount, before + 1);
    expect(
      registry.snapshot().where((row) => row.label == 'page-full-raster'),
      isNotEmpty,
    );

    cache.dispose();
    expect(registry.registrationCount, before);
  });

  testWidgets('viewer applies page raster policy updates', (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    const generous = PdfPageRasterCachePolicy(
      maxBytes: 5 * 1024 * 1024 * 1024,
      maxEntryBytes: 64 * 1024 * 1024,
    );

    Widget viewer(PdfPageRasterCachePolicy policy) => MaterialApp(
          home: PdfViewer(
            document: document,
            controller: controller,
            pageRasterCachePolicy: policy,
          ),
        );

    await tester.pumpWidget(viewer(generous));
    expect(controller.pagePreviewCache!.maxFullRasterBytes, generous.maxBytes);

    await tester.pumpWidget(viewer(const PdfPageRasterCachePolicy.disabled()));
    expect(controller.pagePreviewCache!.maxFullRasterBytes, 0);
    expect(controller.pagePreviewCache!.fullRasterCount, 0);
  });

  testWidgets('viewer applies intermediate LoD policy updates', (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final controller = PdfViewerController();
    addTearDown(controller.dispose);

    Widget viewer(PdfPagePreviewLodPolicy policy) => MaterialApp(
          home: PdfViewer(
            document: document,
            controller: controller,
            pagePreviewLodPolicy: policy,
          ),
        );

    await tester.pumpWidget(viewer(const PdfPagePreviewLodPolicy.disabled()));
    expect(controller.pagePreviewCache!.intermediateLongestSides, isEmpty);

    const custom = PdfPagePreviewLodPolicy(
      intermediateLongestSides: [360, 720, 1440],
      intermediateWindow: 3,
      maxBytes: 64 * 1024 * 1024,
      maxEntryBytes: 8 * 1024 * 1024,
    );
    await tester.pumpWidget(viewer(custom));
    expect(controller.pagePreviewCache!.intermediateLongestSides,
        [360, 720, 1440]);
  });

  testWidgets('rebind drops previews of pages whose content changed',
      (tester) async {
    // A same-geometry edit revision rebinds previews to the new page objects
    // without re-rendering - except pages whose content actually changed (a
    // redaction burn), whose stale previews must be dropped so a fast scroll
    // can't flash the removed content.
    final document = PdfDocument.open(buildMultiPagePdf(3));
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await cache.renderPreview(i, document.page(i));
      }
    });
    expect(cache.has(0) && cache.has(1) && cache.has(2), isTrue);

    final next = PdfDocument.open(buildMultiPagePdf(3));
    final pages = [for (var i = 0; i < 3; i++) next.page(i)];
    cache.rebind(pages, changed: (i) => i == 1);

    // the changed page's stale preview is gone; the rest rebind to the new
    // page objects (so an on-screen render still treats them as fresh)
    expect(cache.has(1), isFalse, reason: 'changed page dropped, not rebound');
    expect(cache.has(0), isTrue);
    expect(cache.has(2), isTrue);
    expect(cache.isFresh(0, pages[0]), isTrue);
    expect(cache.isFresh(2, pages[2]), isTrue);
    // a dropped page is no longer fresh, so its next on-screen render refills
    // it (in the buggy rebind path it stayed "fresh" and could never refresh)
    expect(cache.isFresh(1, pages[1]), isFalse);
  });

  testWidgets('vector-first prerender upgrades to a full preview',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    final worker = _PreviewWorker();
    addTearDown(cache.dispose);

    await tester.runAsync(() =>
        cache.renderPreview(0, page, worker: worker, decodeImages: false));
    expect(worker.calls.single, (0, false, null));
    expect(cache.isFresh(0, page), isTrue,
        reason: 'a vector preview is good enough to paint while held');
    expect(cache.isFresh(0, page, requireImages: true), isFalse,
        reason: 'it must not suppress the later full-image warm');

    await tester.runAsync(
        () => cache.renderPreview(0, page, worker: worker, decodeImages: true));
    expect(worker.calls.last.$2, isTrue);
    expect(worker.calls.last.$3, isNotNull,
        reason: 'full preview decodes at the low preview ratio');
    expect(cache.isFresh(0, page, requireImages: true), isTrue);
  });

  testWidgets('worker-deferred preview images keep the 200px decode cap',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    final imageCache = PdfImageCache.instance;
    imageCache.clear();
    addTearDown(imageCache.clear);
    const nativeSize = 800;
    final stream = CosStream(
      CosDictionary({
        'Width': const CosInteger(nativeSize),
        'Height': const CosInteger(nativeSize),
        'BitsPerComponent': const CosInteger(8),
        'ColorSpace': const CosName('DeviceRGB'),
      }),
      Uint8List(nativeSize * nativeSize * 3),
    );
    final worker = _DeferredImageWorker(PdfImageRequest(
      stream: stream,
      transform: const PdfMatrix(612, 0, 0, 792, 0, 0),
    ));

    await tester.runAsync(() => cache.renderPreview(0, page, worker: worker));

    expect(cache.isFresh(0, page, requireImages: true), isTrue);
    expect(imageCache.bytes, greaterThan(0));
    expect(imageCache.bytes, lessThanOrEqualTo(200 * 200 * 4),
        reason: 'a worker-deferred image must inherit the preview ratio when '
            'it is decoded during UI-side replay');
  });

  testWidgets('command-limited previews stay partial without image draws',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    final worker = _VectorOnlyWorker();
    addTearDown(cache.dispose);

    await tester.runAsync(() => cache.renderPreview(0, page,
        worker: worker, decodeImages: false, commandLimit: 2000));

    expect(worker.commandLimits, [2000]);
    expect(cache.isFresh(0, page), isTrue);
    expect(cache.isFresh(0, page, requireImages: true), isFalse,
        reason: 'a capped command prefix must not masquerade as complete');
  });

  testWidgets('vector preview defers UI replay while motion is active',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    final worker = _VectorOnlyWorker();
    addTearDown(cache.dispose);

    var moving = true;
    await tester.runAsync(() => cache.renderPreview(0, page,
        worker: worker,
        decodeImages: false,
        commandLimit: 2000,
        deferUiWork: () => moving));

    expect(worker.commandLimits, [2000]);
    expect(cache.has(0), isFalse,
        reason: 'worker results must not replay/rasterize on the UI side '
            'during a live pan');

    moving = false;
    await tester.runAsync(() => cache.renderPreview(0, page,
        worker: worker,
        decodeImages: false,
        commandLimit: 2000,
        deferUiWork: () => moving));
    expect(worker.commandLimits, [2000, 2000]);
    expect(cache.isFresh(0, page), isTrue);
  });

  testWidgets('full page renders upgrade vector-only previews', (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    final worker = _PreviewWorker();
    addTearDown(cache.dispose);

    await tester.runAsync(() =>
        cache.renderPreview(0, page, worker: worker, decodeImages: false));
    expect(cache.isFresh(0, page), isTrue);
    expect(cache.isFresh(0, page, requireImages: true), isFalse);

    await tester.runAsync(() async {
      final picture = await PdfPageRenderer.renderPicture(page);
      try {
        await cache.putFromPicture(0, page, picture);
      } finally {
        picture.dispose();
      }
    });

    expect(cache.isFresh(0, page, requireImages: true), isTrue,
        reason: 'the completed on-screen render must replace vector previews');
  });

  testWidgets('worker-declined vector prefetch does not render locally',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    final worker = _DecliningWorker();
    addTearDown(cache.dispose);

    await tester.runAsync(() =>
        cache.renderPreview(0, page, worker: worker, decodeImages: false));

    expect(worker.calls, [(0, false, null)]);
    expect(cache.has(0), isFalse,
        reason: 'vector prefetch must skip pages the worker declines');
  });

  testWidgets('a held page paints the cached preview, then the full render',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    await tester.runAsync(() => cache.renderPreview(0, document.page(0)));

    final hold = ValueNotifier<bool>(true);
    addTearDown(hold.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          child: PdfPageView(
              page: document.page(0), renderHold: hold, previewCache: cache),
        ),
      ),
    ));
    await tester.pump();
    // held: the low-res preview shows instead of blank paper
    expect(previewRaster, findsOneWidget);
    expect(fullRaster, findsNothing);

    hold.value = false;
    for (var i = 0; i < 50 && fullRaster.evaluate().isEmpty; i++) {
      await settle(tester);
    }
    // the full render replaces the preview (which is dropped to free it)
    expect(fullRaster, findsOneWidget);
    expect(previewRaster, findsNothing);
  });

  testWidgets('a held page promotes through cached preview LoDs',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    await tester.runAsync(() => cache.renderPreview(0, page));

    final hold = ValueNotifier<bool>(true);
    addTearDown(hold.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          child: PdfPageView(
            page: page,
            renderHold: hold,
            previewCache: cache,
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(previewRaster, findsOneWidget);

    await tester
        .runAsync(() => cache.renderPreview(0, page, targetLongestSide: 400));
    await tester.pump();
    var image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(math.max(image.width, image.height), inInclusiveRange(399, 400));

    await tester
        .runAsync(() => cache.renderPreview(0, page, targetLongestSide: 800));
    await tester.pump();
    image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(math.max(image.width, image.height), inInclusiveRange(790, 800));
    expect(hold.value, isTrue,
        reason: 'preview promotion must not release the full render hold');
  });

  testWidgets('completed display raster seeds every intermediate LoD by blit',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    final image = await PdfPageRenderer.renderImage(page, pixelRatio: 2);
    addTearDown(image.dispose);

    cache.putFullImage(
      0,
      page,
      image,
      pageColor: const Color(0xFFFFFFFF),
      annotations: true,
      rotation: null,
    );
    for (var i = 0; i < 50 && cache.intermediateCount < 2; i++) {
      await settle(tester);
    }

    expect(cache.hasIntermediate(0, targetLongestSide: 400), isTrue);
    expect(cache.hasIntermediate(0, targetLongestSide: 800), isTrue);
    expect(cache.lodStats.intermediateEntries, 2);
  });

  testWidgets('a recycled page restores its exact raster through render hold',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);

    Widget pageView({PdfPageRenderScheduler? scheduler}) => MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              child: PdfPageView(
                page: page,
                previewCache: cache,
                renderScheduler: scheduler,
              ),
            ),
          ),
        );

    // First visit pays the normal interpret + GPU readback and leaves an
    // exact, bounded cache entry above the lazy page widget.
    await tester.pumpWidget(pageView());
    for (var i = 0;
        i < 50 &&
            (fullRaster.evaluate().isEmpty || cache.debugFullRasterPixels == 0);
        i++) {
      await settle(tester);
    }
    expect(fullRaster, findsOneWidget);
    expect(cache.debugFullRasterPixels, greaterThan(0));
    expect(cache.debugRetainedSceneCount, 1,
        reason: 'the complete command scene is retained with the raster');

    // Simulate the lazy list disposing the off-screen page, then revisit it
    // while fast-scroll hold is still raised. Reuse is safe ahead of the
    // scheduler because this exact physical-size raster already exists.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(cache.debugRetainedSceneCount, 1,
        reason: 'lazy page disposal releases its lease, not the LRU scene');
    final scheduler = PdfPageRenderScheduler()..holding = true;
    addTearDown(scheduler.dispose);
    await tester.pumpWidget(pageView(scheduler: scheduler));

    expect(fullRaster, findsOneWidget,
        reason: 'the first revisit frame should adopt the exact raster');
    expect(previewRaster, findsNothing);
    expect(scheduler.hasPending, isFalse,
        reason: 'a cache hit must not wait for scroll-settle release');
  });

  testWidgets('an off-screen cache hit promotes when it enters a zoomed view',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);

    Widget pageView({required double scale, required bool onScreen}) =>
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              child: PdfPageView(
                page: page,
                scale: scale,
                onScreen: onScreen,
                previewCache: cache,
              ),
            ),
          ),
        );

    // Seed the exact fit-size raster, then dispose the page state like the lazy
    // viewer does after it leaves the build window.
    await tester.pumpWidget(pageView(scale: 1, onScreen: true));
    for (var i = 0;
        i < 50 && (fullRaster.evaluate().isEmpty || cache.fullRasterCount == 0);
        i++) {
      await settle(tester);
    }
    final fitWidth = tester.widget<RawImage>(fullRaster).image!.width;
    expect(cache.fullRasterCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // A global viewer zoom also reaches lazy-list neighbours. Off-screen pages
    // deliberately stay at fit resolution, so this remount restores the cached
    // fit raster even though the live transform is at 4x.
    await tester.pumpWidget(pageView(scale: 4, onScreen: false));
    await tester.pump();
    expect(tester.widget<RawImage>(fullRaster).image!.width, fitWidth);

    // Crossing into the viewport must promote that cache-only raster. Before
    // the regression fix, onScreen was not a render-intent input and the cache
    // restore carried no picture/image-ratio metadata, so this stayed enlarged
    // from fit resolution forever.
    await tester.pumpWidget(pageView(scale: 4, onScreen: true));
    for (var i = 0; i < 100; i++) {
      await settle(tester);
      if (tester.widget<RawImage>(fullRaster).image!.width > fitWidth * 2) {
        break;
      }
    }
    expect(
      tester.widget<RawImage>(fullRaster).image!.width,
      greaterThan(fitWidth * 2),
      reason: 'an on-screen zoom must replace the fit-size cached raster',
    );
  });

  testWidgets('an on-screen render feeds the cache without re-interpreting',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    final page = document.page(0);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
            width: 400, child: PdfPageView(page: page, previewCache: cache)),
      ),
    ));
    for (var i = 0; i < 50 && !cache.isFresh(0, page); i++) {
      await settle(tester);
    }
    expect(cache.isFresh(0, page), isTrue);
  });

  testWidgets('full raster readiness precedes the preview downscale',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final cache = PdfPagePreviewCache();
    final events = <String>[];
    cache.addListener(() => events.add('preview'));
    addTearDown(cache.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          child: PdfPageView(
            page: document.page(0),
            previewCache: cache,
            onRasterReady: () => events.add('ready'),
          ),
        ),
      ),
    ));
    for (var i = 0;
        i < 50 && !(events.contains('ready') && events.contains('preview'));
        i++) {
      await settle(tester);
    }

    expect(events, containsAll(<String>['ready', 'preview']));
    expect(events.indexOf('ready'), lessThan(events.indexOf('preview')),
        reason: 'preview population must not delay requested-page readiness');
  });

  testWidgets('prerender warms previews of pages never seen on screen',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(8));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          // Warm the whole 8-page doc so the far pages (6, 7) pre-render from
          // idle; the default window is deliberately small (it bounds the
          // worker-decode flood) and would not reach distance 7.
          previewWindow: 8,
        ),
      ),
    ));
    await tester.pump();

    // the background prerender reaches the far pages while the viewer
    // idles - pages 6 and 7 have never been built
    final cache = controller.debugPreviewCache!;
    for (var i = 0; i < 100 && !(cache.has(6) && cache.has(7)); i++) {
      await settle(tester);
    }
    expect(cache.has(6), isTrue);
    expect(cache.has(7), isTrue);

    // A long jump now lands directly on the destination and may render it
    // fully right away. The contract this test pins is the background warm:
    // far pages received previews before they were ever built on screen.
    unawaited(controller.jumpToPage(6));
    for (var i = 0; i < 50 && fullRaster.evaluate().isEmpty; i++) {
      await settle(tester);
    }
    expect(fullRaster, findsWidgets);
  });

  testWidgets('same-geometry document swap clears previews and tile identity',
      (tester) async {
    final first = PdfDocument.open(buildClassicPdf());
    final second = PdfDocument.open(buildMultiPagePdf(1));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);

    Widget viewer(PdfDocument document, {required bool active}) => MaterialApp(
          home: Scaffold(
            body: PdfViewer(
              document: document,
              controller: controller,
              initialFit: PdfViewerFit.width,
              previewWindow: 1,
              active: active,
            ),
          ),
        );

    await tester.pumpWidget(viewer(first, active: true));
    final cache = controller.debugPreviewCache!;
    for (var i = 0; i < 100 && !cache.has(0); i++) {
      await settle(tester);
    }
    expect(cache.has(0), isTrue);
    final firstNamespace = controller.debugTileCacheNamespace;

    // Keep the replacement parked so it cannot refill the cache before the
    // assertion. The documents deliberately have identical page geometry:
    // geometry is not proof that their pixels share an identity.
    await tester.pumpWidget(viewer(second, active: false));
    expect(controller.debugTileCacheNamespace, isNot(same(firstNamespace)));
    expect(cache.has(0), isFalse,
        reason: 'the first document\'s preview must not survive the swap');
  });

  testWidgets('proactive previews wait for the configured idle delay',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(8));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          previewWindow: 8,
          previewIdleDelay: const Duration(seconds: 1),
        ),
      ),
    ));
    await tester.pump();

    // Let initial fitting settle and visible-page work finish. That settle
    // starts the quiet window from its final interaction boundary.
    await tester.pump(const Duration(milliseconds: 250));
    for (var i = 0; i < 50 && fullRaster.evaluate().isEmpty; i++) {
      await settle(tester);
    }
    final cache = controller.debugPreviewCache!;
    expect(cache.has(7), isFalse);

    await tester.pump(const Duration(milliseconds: 900));
    expect(cache.has(7), isFalse,
        reason: 'far-page warming must not steal the interaction tail');

    await tester.pump(const Duration(milliseconds: 150));
    for (var i = 0; i < 100 && !cache.has(7); i++) {
      await settle(tester);
    }
    expect(cache.has(7), isTrue,
        reason: 'the normal preview warm resumes once the viewer is idle');
  });

  testWidgets('foreground worker render starts before background previews',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(8));
    final controller = PdfViewerController();
    final worker = _BlockingPreviewWorker();
    addTearDown(controller.dispose);
    addTearDown(() {
      if (!worker.release.isCompleted) worker.release.complete();
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          renderWorker: worker,
          initialFit: PdfViewerFit.width,
          previewWindow: 8,
        ),
      ),
    ));
    await tester.pump();

    for (var i = 0; i < 20 && worker.calls.isEmpty; i++) {
      await tester.pump();
    }
    expect(worker.calls, isNotEmpty);
    expect(
      worker.calls.where((page) => page >= 2),
      isEmpty,
      reason: 'off-screen preview work must not enter the worker queue while '
          'the visible page render is still in flight',
    );

    worker.release.complete();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  });

  testWidgets('idle prerender promotes only the nearby LoD working set',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(8));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          previewWindow: 4,
          pagePreviewLodPolicy: const PdfPagePreviewLodPolicy(
            intermediateLongestSides: [400, 800],
            intermediateWindow: 2,
          ),
        ),
      ),
    ));
    await tester.pump();
    final cache = controller.debugPreviewCache!;

    // A page inside the LoD window fills its whole ladder from one interpret
    // (#699), so the sharp rungs can land before the wider base sweep gets
    // to page 4 - wait for both to settle rather than for whichever the
    // warm order happens to reach first.
    for (var i = 0;
        i < 150 &&
            !(cache.hasIntermediate(2, targetLongestSide: 800) &&
                cache.has(4));
        i++) {
      await settle(tester);
    }
    expect(cache.hasIntermediate(2, targetLongestSide: 400), isTrue);
    expect(cache.hasIntermediate(2, targetLongestSide: 800), isTrue);
    expect(cache.has(4), isTrue,
        reason: 'the inexpensive base level covers the wider preview window');
    expect(cache.hasIntermediate(4), isFalse,
        reason: 'middle levels stay inside their tighter byte working set');
    expect(controller.pagePreviewLodStats!.intermediateEntries,
        greaterThanOrEqualTo(2));
  });

  testWidgets('the prerender warms only a window of pages around the viewport',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(12));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          previewWindow: 3,
        ),
      ),
    ));
    await tester.pump();

    // a page within the window is warmed by the prerender; a far page is
    // never a candidate, so the loop runs out of work and leaves it cold
    final cache = controller.debugPreviewCache!;
    for (var i = 0; i < 100 && !cache.has(3); i++) {
      await settle(tester);
    }
    expect(cache.has(3), isTrue, reason: 'within ±3 of page 0');
    // give the loop ample idle time to prove it has gone quiet, not just
    // not reached the far page yet
    for (var i = 0; i < 30; i++) {
      await settle(tester);
    }
    expect(cache.has(11), isFalse, reason: 'far outside the window');
  });

  testWidgets('the window recenters as the user navigates', (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(12));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          previewWindow: 3,
        ),
      ),
    ));
    await tester.pump();
    final cache = controller.debugPreviewCache!;
    for (var i = 0; i < 100 && !cache.has(3); i++) {
      await settle(tester);
    }
    expect(cache.has(11), isFalse);

    // jump to the far end (plain pumps complete the animation; runAsync
    // interleaving would stall the clock) - the settle restarts the loop,
    // which now centers on the new current page and warms its neighbors
    unawaited(controller.jumpToPage(11));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(controller.currentPage, 11);
    for (var i = 0; i < 100 && !cache.has(8); i++) {
      await settle(tester);
    }
    expect(cache.has(8), isTrue, reason: 'within ±3 of page 11 now');
  });

  testWidgets('large documents shrink the full-image preview window',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(80));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          previewWindow: 8,
        ),
      ),
    ));
    await tester.pump();

    // Large documents cap full-image background warming to ±3 pages even when
    // the configured window is wider. Fast-scroll vector passes are tighter
    // still (the immediate neighbor only): their raster readback is useful
    // only near the live viewport, and they do not count as image-fresh.
    final cache = controller.debugPreviewCache!;
    for (var i = 0; i < 100 && !cache.has(3); i++) {
      await settle(tester);
    }
    expect(cache.has(3), isTrue, reason: 'inside the adaptive ±3 window');
    for (var i = 0; i < 30; i++) {
      await settle(tester);
    }
    expect(cache.isFresh(8, document.page(8), requireImages: true), isFalse,
        reason: 'outside the adaptive full-image window');
  });

  testWidgets('previewWindow <= 0 warms every page (short-doc behavior)',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(12));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          previewWindow: 0,
        ),
      ),
    ));
    await tester.pump();
    final cache = controller.debugPreviewCache!;
    // unbounded: the far page is still attempted and warmed
    for (var i = 0; i < 150 && !cache.has(11); i++) {
      await settle(tester);
    }
    expect(cache.has(11), isTrue);
  });

  testWidgets('a visited far page keeps its preview from the on-screen render',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(12));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          previewWindow: 3,
        ),
      ),
    ));
    await tester.pump();
    final cache = controller.debugPreviewCache!;

    // scroll the far page onto screen - its full render feeds the cache for
    // free (putFromPicture), independent of the prerender window (plain
    // pumps complete the jump; runAsync would stall the animation clock)
    unawaited(controller.jumpToPage(11));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(controller.currentPage, 11);
    for (var i = 0; i < 100 && !cache.has(11); i++) {
      await settle(tester);
    }
    expect(cache.has(11), isTrue);

    // back to the top: page 11 is now outside the ±3 window but its preview
    // survives (capacity 300, no eviction pressure)
    unawaited(controller.jumpToPage(0));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < 30; i++) {
      await settle(tester);
    }
    expect(cache.has(11), isTrue);
  });

  testWidgets('pagePreviews: false disables preview warming', (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(8));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          pagePreviews: false,
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 50 && fullRaster.evaluate().isEmpty; i++) {
      await settle(tester);
    }

    unawaited(controller.jumpToPage(6));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    // The fast-scroll hold now waits for a full 500 ms of quiet before the
    // sharp render starts. No preview should appear while that timer runs.
    await tester.pump(const Duration(milliseconds: 550));
    expect(controller.debugPreviewCache!.has(6), isFalse);
    expect(previewRaster, findsNothing);
    for (var i = 0; i < 50 && fullRaster.evaluate().isEmpty; i++) {
      await settle(tester);
    }
    expect(fullRaster, findsWidgets);
  });
}

class _PreviewWorker extends PdfRenderWorker {
  final calls = <(int, bool, double?)>[];

  @override
  bool get isActive => true;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial}) async {
    calls.add((pageIndex, decodeImages, imagePixelRatio));
    final request = PdfImageRequest(
      stream: CosStream(CosDictionary(), Uint8List(0)),
      transform: PdfMatrix.identity,
      decoded: decodeImages
          ? PdfDecodedPixels(Uint8List.fromList([0, 0, 0, 255]), 1, 1)
          : null,
    );
    return [PdfDrawImageCommand(request)];
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}

class _DeferredImageWorker extends PdfRenderWorker {
  _DeferredImageWorker(this.request);

  final PdfImageRequest request;

  @override
  bool get isActive => true;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
          {bool annotations = true,
          int priority = 0,
          double? imagePixelRatio,
          bool decodeImages = true,
          int? commandLimit,
          PdfRect? imageDecodeRegion,
          PdfPartialRecordSink? onPartial}) async =>
      [PdfDrawImageCommand(request)];

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}

class _BlockingPreviewWorker extends PdfRenderWorker {
  final calls = <int>[];
  final release = Completer<void>();

  @override
  bool get isActive => true;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial}) async {
    calls.add(pageIndex);
    await release.future;
    return const [];
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}

class _DecliningWorker extends PdfRenderWorker {
  final calls = <(int, bool, double?)>[];

  @override
  bool get isActive => true;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial}) async {
    calls.add((pageIndex, decodeImages, imagePixelRatio));
    return null;
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}

class _VectorOnlyWorker extends PdfRenderWorker {
  final commandLimits = <int?>[];

  @override
  bool get isActive => true;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial}) async {
    commandLimits.add(commandLimit);
    return const [PdfSaveCommand(), PdfRestoreCommand()];
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}
