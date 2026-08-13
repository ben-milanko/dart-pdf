// The background-isolate render worker: a page recorded off-thread must
// replay to pixels identical to the on-thread recorded render, image-bearing
// pages must decline (null → local render), and the worker's lifecycle
// (active, dispose, out-of-range) must behave. Runs on the Dart VM under
// flutter_test, which supports isolates; every body uses tester.runAsync so
// the isolate spawn and the GPU readback actually complete.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// The first image draw request in a recorded buffer, or null if it draws none.
PdfImageRequest? _firstImage(List<PdfRenderCommand> commands) {
  for (final c in commands) {
    if (c is PdfDrawImageCommand) return c.request;
  }
  return null;
}

/// A synchronous in-process [PdfRenderWorker] for widget tests: it records the
/// page on the test isolate (no background isolate to spawn or await), so
/// PdfPageView's worker render path - including the progressive vector-first
/// pass - runs deterministically under pump(). Honors [decodeImages] exactly
/// like the real backends.
class _SyncWorker extends PdfRenderWorker {
  _SyncWorker(this._bytes);

  final Uint8List _bytes;
  late final PdfDocument _doc = PdfDocument.open(_bytes);
  bool _disposed = false;
  final List<bool> decodeImageCalls = [];
  final List<(int page, int priority)> calls = [];

  @override
  bool get isActive => !_disposed;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial}) async {
    if (_disposed || pageIndex < 0 || pageIndex >= _doc.pageCount) return null;
    calls.add((pageIndex, priority));
    decodeImageCalls.add(decodeImages);
    final page = _doc.page(pageIndex);
    final previewOperationLimit = decodeImages ? null : commandLimit;
    final ops = ContentStreamParser.parse(page.contentBytes(),
        operationLimit: previewOperationLimit);
    final recorder = RecordingPdfDevice();
    final interpreter = PdfInterpreter(cos: _doc.cos, device: recorder)
      ..drawPageOperations(page, ops);
    if (annotations) interpreter.drawAnnotations(page);
    if (decodeImages &&
        onPartial != null &&
        recorder.imageRequests.isNotEmpty) {
      final partialBytes = serializeCommands(recorder.commands,
          cos: _doc.cos,
          decodeImages: false,
          maxImagePixelRatio: imagePixelRatio,
          imageDecodeRegion: imageDecodeRegion,
          imagePlaceholders: true,
          compactStateScopes: true);
      if (partialBytes != null) onPartial(deserializeCommands(partialBytes));
    }
    final bytes = serializeCommands(recorder.commands,
        cos: _doc.cos,
        decodeImages: decodeImages,
        maxImagePixelRatio: imagePixelRatio,
        imageDecodeRegion: imageDecodeRegion,
        imagePlaceholders: !decodeImages,
        commandLimit: commandLimit,
        compactStateScopes: true);
    return bytes == null ? null : deserializeCommands(bytes);
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() => _disposed = true;
}

/// The image of the first painted [RawImage], or null while none has rastered.
ui.Image? _firstRasteredImage(WidgetTester tester) {
  for (final raw in tester.widgetList<RawImage>(find.byType(RawImage))) {
    if (raw.image != null) return raw.image;
  }
  return null;
}

Future<Uint8List> _rasterBytes(ui.Picture picture, Size size) async {
  final image = await PdfPageRenderer.rasterize(picture, size, 1);
  try {
    final data = await image.toByteData();
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void main() {
  test('ordinary workers decline browser page surfaces by default', () {
    final worker = _CountingWorker();

    expect(worker.supportsPageSurfaces, isFalse);
    expect(worker.createPageSurface(Object()), isNull);
  });

  testWidgets('records a vector page off-thread, replays pixel-identically',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildClassicPdf();
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);

      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);
      expect(worker.isActive, isTrue);

      final commands = await worker.record(0);
      expect(commands, isNotNull,
          reason: 'an image-free page should serialize and offload');

      final size = PdfPageRenderer.pageSize(page);
      final workerPicture =
          await PdfPageRenderer.pictureFromCommands(page, commands!);
      final localPicture = await PdfPageRenderer.renderPictureRecorded(page);
      try {
        final workerPixels = await _rasterBytes(workerPicture, size);
        final localPixels = await _rasterBytes(localPicture, size);
        expect(workerPixels, equals(localPixels),
            reason: 'replayed worker buffer must match the local render');
      } finally {
        workerPicture.dispose();
        localPicture.dispose();
      }
    });
  });

  testWidgets('an image XObject page offloads and replays identically',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = PdfImageDocument.fromImageBytes([buildTestJpeg()]);
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);

      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);

      // The worker ships the image's indirect object reference; the main
      // thread resolves and decodes it. The result must match the local
      // recorded render pixel-for-pixel.
      final commands = await worker.record(0);
      expect(commands, isNotNull,
          reason: 'an image XObject serializes via its indirect reference');
      // A baseline JPEG needs the platform codec, so the worker can't decode
      // it off-thread: it ships un-decoded and decodes locally.
      expect(_firstImage(commands!)?.decoded, isNull,
          reason: 'a JPEG image declines the off-thread decode');

      final size = PdfPageRenderer.pageSize(page);
      final workerPicture =
          await PdfPageRenderer.pictureFromCommands(page, commands);
      final localPicture = await PdfPageRenderer.renderPictureRecorded(page);
      try {
        final workerPixels = await _rasterBytes(workerPicture, size);
        final localPixels = await _rasterBytes(localPicture, size);
        expect(workerPixels, equals(localPixels),
            reason: 'the decoded image must replay identically');
      } finally {
        workerPicture.dispose();
        localPicture.dispose();
      }
    });
  });

  testWidgets('an image with an /SMask (nested stream) replays identically',
      (tester) async {
    await tester.runAsync(() async {
      // A PNG with alpha embeds as a Flate RGB XObject plus an indirect /SMask
      // stream - so inlining must descend into and decrypt the nested stream,
      // and the decoder must rebuild the alpha. Compare worker vs local pixels.
      final bytes = PdfImageDocument.fromImageBytes([_alphaPng()]);
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);

      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);

      final commands = await worker.record(0);
      expect(commands, isNotNull,
          reason: 'the image XObject and its /SMask serialize together');
      // A Flate RGB base under a soft mask is purely decodable, so the worker
      // decodes it off-thread and ships premultiplied pixels - the offload.
      final decoded = _firstImage(commands!)?.decoded;
      expect(decoded, isNotNull,
          reason: 'a Flate+SMask image decodes off-thread');
      expect(decoded!.rgba.length, decoded.width * decoded.height * 4);

      final size = PdfPageRenderer.pageSize(page);
      final workerPicture =
          await PdfPageRenderer.pictureFromCommands(page, commands);
      final localPicture = await PdfPageRenderer.renderPictureRecorded(page);
      try {
        final workerPixels = await _rasterBytes(workerPicture, size);
        final localPixels = await _rasterBytes(localPicture, size);
        expect(workerPixels, equals(localPixels),
            reason: 'the soft-masked image must replay identically');
      } finally {
        workerPicture.dispose();
        localPicture.dispose();
      }
    });
  });

  testWidgets('a DCT soft mask is deferred to the platform consumer',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = _dctSoftMaskPdf();
      final document = PdfDocument.open(bytes);
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);

      final commands = await worker.record(0);
      expect(commands, isNotNull);
      final request = _firstImage(commands!);
      expect(request, isNotNull);
      expect(request!.decoded, isNull,
          reason: 'the background isolate must not run the portable JPEG '
              'decoder for a mask the Flutter codec can retain on the GPU');

      final size = PdfPageRenderer.pageSize(document.page(0));
      final workerPicture = await PdfPageRenderer.pictureFromCommands(
        document.page(0),
        commands,
      );
      final localPicture =
          await PdfPageRenderer.renderPictureRecorded(document.page(0));
      try {
        expect(
          await _rasterBytes(workerPicture, size),
          await _rasterBytes(localPicture, size),
          reason: 'deferral must preserve the exact soft-mask composite',
        );
      } finally {
        workerPicture.dispose();
        localPicture.dispose();
      }
    });
  });

  testWidgets('imagePixelRatio caps a decoded image to display resolution',
      (tester) async {
    await tester.runAsync(() async {
      // A Flate+SMask image decodes off-thread, so the worker ships its pixels
      // and the cap can shrink them. A tiny ratio must yield fewer pixels than
      // the uncapped record; the cap never upscales.
      final bytes = PdfImageDocument.fromImageBytes([_alphaPng()]);
      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);

      final native = _firstImage((await worker.record(0))!)?.decoded;
      final capped =
          _firstImage((await worker.record(0, imagePixelRatio: 0.01))!)
              ?.decoded;
      expect(native, isNotNull);
      expect(capped, isNotNull);
      expect(capped!.width * capped.height,
          lessThan(native!.width * native.height),
          reason: 'a tiny display ratio must downsample the shipped pixels');
      expect(capped.rgba.length, capped.width * capped.height * 4);
    });
  });

  testWidgets(
      'a thumbnail-ratio record is budgeted to the tile it fills '
      '(#603)', (tester) async {
    await tester.runAsync(() async {
      // The warm pass asks for a page at ~0.4 px per point to fill a 256px
      // tile. Before this the buffer it got back was budgeted against the
      // FULL-PAGE raster cap (17 MP) - so a layered sheet shipped megabytes of
      // decoded pixels the tile can never show, and the main thread paid for
      // every one of them again turning them into ui.Images at replay.
      final bytes = buildSyntheticRasterUnderlaySheet(
        underlays: const [
          PdfUnderlaySpec(width: 1400, height: 1000),
          PdfUnderlaySpec(width: 1400, height: 1000),
          PdfUnderlaySpec(width: 1400, height: 1000),
        ],
        layers: 2,
        ops: 40,
      );
      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);
      final size = PdfPageRenderer.pageSize(PdfDocument.open(bytes).page(0));

      const tilePixels = 256.0;
      final tileRatio = tilePixels / size.width;
      final commands = await worker.record(0, imagePixelRatio: tileRatio);
      expect(commands, isNotNull, reason: 'the sheet must offload');
      final (count, pixels) = PdfPageRenderer.decodedImageStats(commands!);
      expect(count, greaterThan(0), reason: 'nothing decoded - proves nothing');

      // The tile's own raster at display resolution. Slop: every image rounds
      // its scaled edges up, so a
      // page of them lands a hair over the budget by construction.
      final raster = tilePixels * (size.height * tileRatio);
      expect(pixels, lessThanOrEqualTo((raster * 1.02).ceil()),
          reason: '$pixels decoded pixels shipped to fill a '
              '${raster.round()}-pixel tile');

      // ...and the same page at its own resolution is not squeezed by it: the
      // budget follows the raster, it is not a blanket tightening.
      final full = await worker.record(0, imagePixelRatio: 2.0);
      final (_, fullPixels) = PdfPageRenderer.decodedImageStats(full!);
      expect(fullPixels, greaterThan(pixels * 8));
    });
  });

  testWidgets('decodeImages:false records vector/text but ships images raw',
      (tester) async {
    await tester.runAsync(() async {
      // The fast pass of progressive rendering: the page's image draws are
      // present (so a full pass is known to be needed) but carry no decoded
      // pixels, so the buffer comes back without paying the image decode.
      final bytes = PdfImageDocument.fromImageBytes([_alphaPng()]);
      final page = PdfDocument.open(bytes).page(0);
      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);

      final fast = await worker.record(0, decodeImages: false);
      expect(fast, isNotNull);
      expect(_firstImage(fast!)?.decoded, isNull,
          reason: 'decodeImages:false ships the image stream, not its pixels');
      expect(PdfPageRenderer.hasImageDraws(fast), isTrue,
          reason: 'the image draw command is still in the buffer');

      // includeImages:false replays the vector/text and skips the image, so the
      // picture builds without decoding anything - the fast first paint.
      final vector = await PdfPageRenderer.pictureFromCommands(page, fast,
          includeImages: false);
      addTearDown(vector.dispose);
      expect(PdfPageRenderer.decodedImageStats(fast), (0, 0));
    });
  });

  testWidgets('PdfPageView renders an image page through the worker',
      (tester) async {
    await tester.runAsync(() async {
      // A page that is only an image has no linework for the vector-first pass
      // to reveal. It must start the full decode immediately instead of paying
      // for a blank decodeImages:false record first.
      final bytes = PdfImageDocument.fromImageBytes([_alphaPng()]);
      final page = PdfDocument.open(bytes).page(0);
      final worker = _SyncWorker(bytes);
      addTearDown(worker.dispose);

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: PdfPageView(page: page, renderWorker: worker),
            ),
          ),
        ),
      ));

      // Drive the async passes and their GPU rasters to completion.
      ui.Image? rastered;
      for (var i = 0; i < 80 && rastered == null; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        // Without the interim vector readback, the first real engine task is
        // the platform image codec. Fake-time pumps do not give that task wall
        // time to answer, even inside runAsync, so yield briefly just as the
        // other GPU/codec tests in this file do.
        await Future<void>.delayed(const Duration(milliseconds: 1));
        rastered = _firstRasteredImage(tester);
      }
      expect(rastered, isNotNull,
          reason: 'the page rasterized through the worker render path; '
              'calls=${worker.decodeImageCalls}');
      expect(worker.decodeImageCalls, [true],
          reason: 'an image-only scan skips the empty vector-first request');
    });
  });

  testWidgets('page readiness schedules an idle command-warm frame',
      (tester) async {
    final oldRadius = PdfViewer.speculativePageWarmRadius;
    final oldHeavy = PdfViewer.speculativeHeavyPageWarmCount;
    final oldImages = PdfViewer.speculativePageWarmImages;
    final oldHandles = PdfViewer.speculativePageWarmPlatformImages;
    PdfViewer.speculativePageWarmRadius = 1;
    PdfViewer.speculativeHeavyPageWarmCount = 0;
    PdfViewer.speculativePageWarmImages = false;
    PdfViewer.speculativePageWarmPlatformImages = false;
    addTearDown(() {
      PdfViewer.speculativePageWarmRadius = oldRadius;
      PdfViewer.speculativeHeavyPageWarmCount = oldHeavy;
      PdfViewer.speculativePageWarmImages = oldImages;
      PdfViewer.speculativePageWarmPlatformImages = oldHandles;
    });

    final bytes = buildMultiPagePdf(3);
    final worker = _SyncWorker(bytes);
    final controller = PdfViewerController();
    addTearDown(worker.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: PdfDocument.open(bytes),
          controller: controller,
          initialFit: PdfViewerFit.width,
          pagePreviews: false,
          renderWorker: worker,
          autoRenderWorker: false,
        ),
      ),
    ));

    for (var i = 0; i < 100 && !worker.calls.any((call) => call.$2 == 3); i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }

    expect(worker.calls, contains((1, 3)),
        reason: 'onRasterReady commonly fires at endOfFrame; the viewer must '
            'request the follow-up frame itself so idle warming starts before '
            'the next user navigation');
  });

  testWidgets('retained command warm is adopted without a foreground record',
      (tester) async {
    final oldRadius = PdfViewer.speculativePageWarmRadius;
    final oldHeavy = PdfViewer.speculativeHeavyPageWarmCount;
    final oldImages = PdfViewer.speculativePageWarmImages;
    final oldScenes = PdfViewer.speculativePageWarmRetainedScenes;
    final oldDirect = PdfPageView.directPicturePresentation;
    PdfViewer.speculativePageWarmRadius = 1;
    PdfViewer.speculativeHeavyPageWarmCount = 0;
    PdfViewer.speculativePageWarmImages = true;
    PdfViewer.speculativePageWarmRetainedScenes = true;
    PdfPageView.directPicturePresentation = true;
    addTearDown(() {
      PdfViewer.speculativePageWarmRadius = oldRadius;
      PdfViewer.speculativeHeavyPageWarmCount = oldHeavy;
      PdfViewer.speculativePageWarmImages = oldImages;
      PdfViewer.speculativePageWarmRetainedScenes = oldScenes;
      PdfPageView.directPicturePresentation = oldDirect;
    });

    final bytes = buildMultiPagePdf(3);
    final document = PdfDocument.open(bytes);
    final worker = _SyncWorker(bytes);
    final controller = PdfViewerController();
    addTearDown(worker.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          pagePreviews: false,
          renderWorker: worker,
          autoRenderWorker: false,
        ),
      ),
    ));

    PdfRetainedSceneHandle? warmed;
    for (var i = 0; i < 160 && warmed == null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      warmed = controller.debugPreviewCache!.retainedSceneFor(
        1,
        document.page(1),
        plan: const PdfPageRenderPlan(rotation: 0),
      );
    }
    expect(warmed, isNotNull,
        reason: 'the next forward target was replayed and retained while idle; '
            'calls=${worker.calls}, cache='
            '${controller.debugPreviewCache!.debugRetainedSceneCount}');
    warmed!.dispose();
    expect(worker.calls, contains((1, 3)));

    unawaited(controller.jumpToPage(1));
    for (var i = 0; i < 100 && !controller.isPageRasterReady(1); i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.isPageRasterReady(1), isTrue);
    expect(worker.calls.where((call) => call == (1, 0)), isEmpty,
        reason: 'the arriving page must submit the retained picture instead '
            'of recording and replaying the page again');
  });

  testWidgets('a serial worker does not occupy its only lane with speculation',
      (tester) async {
    final oldRadius = PdfViewer.speculativePageWarmRadius;
    final oldHeavy = PdfViewer.speculativeHeavyPageWarmCount;
    final oldSerialMax = PdfViewer.speculativeSerialWarmMaxPages;
    final oldImages = PdfViewer.speculativePageWarmImages;
    final oldHandles = PdfViewer.speculativePageWarmPlatformImages;
    PdfViewer.speculativePageWarmRadius = 1;
    PdfViewer.speculativeHeavyPageWarmCount = 2;
    PdfViewer.speculativeSerialWarmMaxPages = -1;
    PdfViewer.speculativePageWarmImages = true;
    PdfViewer.speculativePageWarmPlatformImages = false;
    addTearDown(() {
      PdfViewer.speculativePageWarmRadius = oldRadius;
      PdfViewer.speculativeHeavyPageWarmCount = oldHeavy;
      PdfViewer.speculativeSerialWarmMaxPages = oldSerialMax;
      PdfViewer.speculativePageWarmImages = oldImages;
      PdfViewer.speculativePageWarmPlatformImages = oldHandles;
    });

    final bytes = buildMultiPagePdf(4);
    final worker = _SyncWorker(bytes);
    final controller = PdfViewerController();
    addTearDown(worker.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: PdfDocument.open(bytes),
          controller: controller,
          initialFit: PdfViewerFit.width,
          pagePreviews: false,
          renderWorker: worker,
          autoRenderWorker: false,
        ),
      ),
    ));

    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }

    expect(worker.calls.where((call) => call.$2 == 3), isEmpty,
        reason: 'a serial backend cannot reserve a foreground lane');
  });

  testWidgets('a small resource-simple web first paint bypasses worker startup',
      (tester) async {
    final bytes = buildClassicPdf();
    final page = PdfDocument.open(bytes).page(0);
    final worker = _SyncWorker(bytes);
    PdfPageView.debugWebLocalFirstPaintBackendOverride = true;
    addTearDown(() {
      PdfPageView.debugWebLocalFirstPaintBackendOverride = null;
      worker.dispose();
    });

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: PdfPageView(page: page, renderWorker: worker),
          ),
        ),
      ),
    ));

    for (var i = 0; i < 80 && _firstRasteredImage(tester) == null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_firstRasteredImage(tester), isNotNull);
    expect(worker.decodeImageCalls, isEmpty,
        reason: 'worker startup must not gate a cheap text/vector page');

    // The bypass is a one-shot startup hedge for this document worker. A page
    // first encountered later must stay asynchronous instead of interpreting
    // on the UI isolate during navigation.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: PdfPageView(page: page, renderWorker: worker),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 80 && worker.decodeImageCalls.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(worker.decodeImageCalls, isNotEmpty,
        reason: 'later first visits must use the now-started worker');
  });

  testWidgets('a mixed text/image page fuses vector and full records',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildEmbeddedFontImagePdf();
      final page = PdfDocument.open(bytes).page(0);
      final worker = _SyncWorker(bytes);
      addTearDown(worker.dispose);

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: PdfPageView(page: page, renderWorker: worker),
            ),
          ),
        ),
      ));

      for (var i = 0; i < 80 && worker.decodeImageCalls.length < 2; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(worker.decodeImageCalls, [true],
          reason: 'the decoding record emits its image-free first paint and '
              'must not walk the mixed page a second time');
    });
  });

  testWidgets('PdfPageView defers worker replay when render hold resumes',
      (tester) async {
    final bytes = buildClassicPdf();
    final document = PdfDocument.open(bytes);
    final page = document.page(0);
    final scheduler = PdfPageRenderScheduler();
    final previewCache = PdfPagePreviewCache();
    final worker = _ManualWorker();
    addTearDown(scheduler.dispose);
    addTearDown(previewCache.dispose);
    addTearDown(worker.dispose);

    await tester.runAsync(() => previewCache.renderPreview(0, page));

    var rasters = 0;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 1),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            child: PdfPageView(
              page: page,
              previewIndex: 0,
              renderWorker: worker,
              renderScheduler: scheduler,
              previewCache: previewCache,
              onRasterReady: () => rasters++,
            ),
          ),
        ),
      ),
    ));

    for (var i = 0; i < 20 && worker.calls.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(worker.calls.single.$3, isTrue,
        reason: 'the fresh preview skips the vector-first pass');

    scheduler.holding = true;
    worker.completeAll();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(rasters, 0,
        reason: 'a worker result that arrives after motion restarts must not '
            'replay/rasterize on the UI side');

    scheduler.holding = false;
    for (var i = 0; i < 20 && worker.calls.length < 2; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(worker.calls.length, 2,
        reason: 'the render is queued again and drains after the hold drops');
    worker.completeAll();
    for (var i = 0; i < 40 && rasters == 0; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(rasters, 1);
  });

  test('PdfCachingRenderWorker times out wedged records and retries', () async {
    final previousTimeout = pdfRenderWorkerRecordTimeout;
    pdfRenderWorkerRecordTimeout = const Duration(milliseconds: 1);
    addTearDown(() => pdfRenderWorkerRecordTimeout = previousTimeout);

    final inner = _HangingWorker();
    final worker = PdfCachingRenderWorker(inner);
    addTearDown(worker.dispose);

    final result = await worker.record(0);
    expect(result, isNull);
    expect(inner.calls, 1);
    expect(inner.cancels, [(0, 0)]);
    expect(inner.active, isFalse,
        reason: 'a timed-out worker snapshot must be retired');

    inner.hang = false;
    final retry = await worker.record(0);
    expect(retry, isNull,
        reason: 'future requests should fail fast into the local-render path');
    expect(inner.calls, 1);
  });

  testWidgets('PdfPageView cancels recycled worker requests by renderPriority',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(2));
    final worker = _ManualWorker();
    addTearDown(worker.dispose);

    Widget view(int index, int priority) => MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 120,
                height: 120,
                child: PdfPageView(
                  page: document.page(index),
                  previewIndex: index,
                  renderWorker: worker,
                  renderPriority: priority,
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(view(0, -997));
    for (var i = 0; i < 10 && worker.calls.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(worker.calls.single.$1, 0);

    await tester.pumpWidget(view(1, -996));
    expect(worker.cancels, contains((0, -997)),
        reason: 'lazy-list reuse must cancel the old queued priority');
  });

  testWidgets('an inline image still declines (null → local render)',
      (tester) async {
    await tester.runAsync(() async {
      // A 4x4 inline image (BI .. ID .. EI) - declined because its /CS can name
      // a page-resource colour space unreachable from the stream alone.
      final bytes = _inlineImagePdf();
      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);

      final commands = await worker.record(0);
      expect(commands, isNull,
          reason:
              'an inline image is not serialized; the page renders locally');
    });
  });

  testWidgets('an inline image records vector-only placeholders',
      (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.start(_inlineImagePdf());
      addTearDown(worker.dispose);

      final commands = await worker.record(0, decodeImages: false);
      expect(commands, isNotNull);
      expect(PdfPageRenderer.hasImageDraws(commands!), isTrue,
          reason: 'the placeholder keeps the full-pass image signal');
      expect(_firstImage(commands)!.decoded, isNull,
          reason: 'vector-only records must not decode image pixels');
    });
  });

  testWidgets('out-of-range page returns null', (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.start(buildClassicPdf());
      addTearDown(worker.dispose);
      expect(await worker.record(999), isNull);
      expect(await worker.record(-1), isNull);
    });
  });

  testWidgets('dispose stops the worker and fails further records to null',
      (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.start(buildClassicPdf());
      // record once so the isolate is fully spawned, then tear it down
      expect(await worker.record(0), isNotNull);
      worker.dispose();
      expect(worker.isActive, isFalse);
      expect(await worker.record(0), isNull);
      worker.dispose(); // idempotent
    });
  });

  testWidgets('priority: the on-screen page preempts queued prefetch',
      (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.startUncached(buildMultiPagePdf(2));
      addTearDown(worker.dispose);
      await worker.record(0); // warm up: the isolate is now spawned and idle

      // Fire six prefetch records (priority 1) then one on-screen record
      // (priority 0), all synchronously - so the first prefetch is in flight
      // and the rest queue behind it. The high-priority request must be served
      // next, ahead of the five still queued: completion order is
      // [low0, HIGH, low1, ...]. Deterministic because record() enqueues
      // synchronously before any isolate response can arrive.
      final order = <String>[];
      final futures = <Future<void>>[
        for (var i = 0; i < 6; i++)
          worker.record(0, priority: 1).then((_) => order.add('low$i')),
        worker.record(1, priority: 0).then((_) => order.add('HIGH')),
      ];
      await Future.wait(futures);

      expect(order.length, 7);
      expect(order.indexOf('HIGH'), 1,
          reason: 'high priority is served right after the in-flight prefetch');
    });
  });

  testWidgets('serves many pages over one long-lived isolate', (tester) async {
    await tester.runAsync(() async {
      final bytes = buildMultiPagePdf(3);
      final doc = PdfDocument.open(bytes);
      final worker = PdfRenderWorker.start(bytes);
      addTearDown(worker.dispose);

      for (var i = 0; i < doc.pageCount; i++) {
        final commands = await worker.record(i);
        // multi-page fixture pages are vector text, so all should offload
        expect(commands, isNotNull, reason: 'page $i should offload');
        final picture =
            await PdfPageRenderer.pictureFromCommands(doc.page(i), commands!);
        picture.dispose();
      }
    });
  });

  testWidgets('cancel drops a queued request without disturbing others',
      (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.startUncached(buildMultiPagePdf(3));
      addTearDown(worker.dispose);
      await worker.record(0); // warm up: the isolate is spawned and idle

      // record() enqueues synchronously, so these resolve deterministically:
      // page 0 goes in flight, pages 1 and 2 queue behind it.
      final inFlight = worker.record(0, priority: 1);
      final stale = worker.record(1, priority: 1);
      final wanted = worker.record(2, priority: 1);
      // Page 1 "scrolled away" before its turn - drop it from the queue.
      worker.cancel(1, priority: 1);

      expect(await stale, isNull,
          reason: 'a cancelled queued request resolves to a local render');
      expect(await inFlight, isNotNull,
          reason: 'the in-flight request is untouched and still completes');
      expect(await wanted, isNotNull,
          reason: 'an unrelated queued request still completes');
    });
  });

  testWidgets('cancel does not preempt the in-flight request', (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.startUncached(buildMultiPagePdf(2));
      addTearDown(worker.dispose);
      await worker.record(0); // warm up

      final inFlight = worker.record(0, priority: 1); // now in flight
      worker.cancel(0, priority: 1); // targets page 0, but it already started
      expect(await inFlight, isNotNull,
          reason: 'the single in-flight request cannot be cancelled');
    });
  });

  testWidgets('cancel only matches the given page and priority',
      (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.startUncached(buildMultiPagePdf(3));
      addTearDown(worker.dispose);
      await worker.record(0); // warm up

      final inFlight = worker.record(0, priority: 1);
      final otherPriority = worker.record(1, priority: 2);
      final target = worker.record(1, priority: 1);
      // Same page as otherPriority, but a different priority bucket: only the
      // priority-1 request for page 1 is dropped.
      worker.cancel(1, priority: 1);

      expect(await target, isNull, reason: 'the matching request is cancelled');
      expect(await inFlight, isNotNull);
      expect(await otherPriority, isNotNull,
          reason: 'a same-page request at another priority is left alone');
    });
  });

  testWidgets('a higher-priority request preempts the in-flight job',
      (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.startUncached(buildMultiPagePdf(2));
      addTearDown(worker.dispose);
      await worker.record(0); // warm up: the isolate is spawned and idle

      // Start a low-priority prefetch - it goes in flight.
      final prefetch = worker.record(0, priority: 1);
      // The prefetch is now executing on the isolate. Queue a high-priority
      // on-screen request: _pump sees the higher priority and sends a cancel
      // signal to the isolate, so the in-flight prefetch is abandoned and the
      // high-priority request is served next.
      final onScreen = worker.record(1, priority: 0);

      final onScreenResult = await onScreen;
      await prefetch; // may be null (preempted) or non-null (completed first)
      // The key invariant: the on-screen page always completes.
      expect(onScreenResult, isNotNull,
          reason: 'the high-priority on-screen page always completes');
    });
  });

  group('PdfCachingRenderWorker', () {
    test('forwards browser page-surface sessions without caching them',
        () async {
      final inner = _SurfaceWorker();
      final worker = PdfCachingRenderWorker(inner);
      final surface = Object();
      const region = PdfPageSurfaceRegion(
        left: 10,
        top: 20,
        right: 210,
        bottom: 170,
        pixelRatio: 3,
      );

      expect(worker.supportsPageSurfaces, isTrue);
      final session = worker.createPageSurface(surface);
      expect(session, isNotNull);
      expect(inner.surfaces.single, same(surface));

      expect(
        await session!.render(
          3,
          annotations: false,
          width: 640,
          height: 480,
          pageColor: 0xff112233,
          region: region,
          rotation: 90,
          priority: -10,
        ),
        isTrue,
      );
      expect(inner.sessions.single.renders.single, {
        'pageIndex': 3,
        'annotations': false,
        'width': 640,
        'height': 480,
        'pageColor': 0xff112233,
        'region': region,
        'rotation': 90,
        'priority': -10,
      });

      session.dispose();
      expect(inner.sessions.single.disposed, isTrue);
    });

    test('a repeat record for the same key hits the cache (no re-decode)',
        () async {
      final inner = _CountingWorker();
      final worker = PdfCachingRenderWorker(inner);
      final first = await worker.record(7, imagePixelRatio: 2.0);
      final second = await worker.record(7, imagePixelRatio: 2.0);
      expect(inner.calls.length, 1, reason: 'the second record is a cache hit');
      expect(identical(first, second), isTrue,
          reason: 'the cached buffer is reused as-is');
    });

    test('releaseCachedPage drops every variant for only that page', () async {
      final inner = _CountingWorker();
      final worker = PdfCachingRenderWorker(inner);
      addTearDown(worker.dispose);

      await worker.record(7, imagePixelRatio: 1);
      await worker.record(7, imagePixelRatio: 2);
      await worker.record(8, imagePixelRatio: 1);
      expect(worker.cachedEntryCount, 3);

      worker.releaseCachedPage(7);
      expect(worker.cachedEntryCount, 1);
      await worker.record(8, imagePixelRatio: 1);
      expect(inner.calls.length, 3, reason: 'the unrelated page stayed warm');
      await worker.record(7, imagePixelRatio: 1);
      expect(inner.calls.length, 4,
          reason: 'the promoted page no longer has duplicate cache ownership');
    });

    test('a concurrent record for an in-flight key shares one decode',
        () async {
      final inner = _CountingWorker();
      final worker = PdfCachingRenderWorker(inner);
      // Both fire before the first resolves - the second must share, not
      // start a second decode (the fast-scroll re-grant storm).
      final f1 = worker.record(3, imagePixelRatio: 2.0);
      final f2 = worker.record(3, imagePixelRatio: 2.0);
      final r1 = await f1;
      final r2 = await f2;
      expect(inner.calls.length, 1, reason: 'one decode shared by both');
      expect(identical(r1, r2), isTrue);
      // Once it completed it is cached, so a later record still hits.
      await worker.record(3, imagePixelRatio: 2.0);
      expect(inner.calls.length, 1);
    });

    test('a foreground join promotes an in-flight speculative record',
        () async {
      final inner = _ManualWorker();
      final worker = PdfCachingRenderWorker(inner);
      addTearDown(worker.dispose);

      final warm = worker.record(3, priority: 3, imagePixelRatio: 2);
      final visible = worker.record(3, priority: 0, imagePixelRatio: 2);

      expect(identical(warm, visible), isTrue,
          reason: 'all callers keep sharing one cache-level result');
      expect(inner.priorities, [3, 0],
          reason: 'the same key is re-enqueued at foreground priority');
      expect(inner.cancels, [(3, 3)],
          reason: 'a queued speculative copy is removed before promotion');

      const promoted = [PdfSaveCommand(), PdfRestoreCommand()];
      inner._pending[1].complete(promoted);
      expect(await visible, same(promoted));
      expect(await warm, same(promoted));

      // A late completion from the superseded dispatch neither replaces the
      // promoted result nor poisons the completed cache entry.
      inner._pending[0].complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(await worker.record(3, imagePixelRatio: 2), same(promoted));
      expect(inner.calls.length, 2);
    });

    test('ratio bucket, annotations, and decodeImages are part of the key',
        () async {
      final inner = _CountingWorker();
      final worker = PdfCachingRenderWorker(inner);
      await worker.record(0, imagePixelRatio: 2.0);
      await worker.record(0, imagePixelRatio: 2.0); // hit
      await worker.record(0, imagePixelRatio: 4.0); // miss: different zoom
      await worker.record(0, imagePixelRatio: 2.0, annotations: false); // miss
      await worker.record(0, imagePixelRatio: 2.0, decodeImages: false); // miss
      await worker.record(0, imagePixelRatio: 2.01); // hit: same bucket as 2.0
      expect(inner.calls.length, 4);
    });

    test('image decode region is part of the full-image cache key', () async {
      final inner = _CountingWorker(decodedPixels: 64);
      final worker = PdfCachingRenderWorker(inner);
      const top = PdfRect(0, 400, 200, 600);
      const sameBucket = PdfRect(0.01, 400, 200, 600);
      const bottom = PdfRect(0, 0, 200, 200);

      await worker.record(0, imagePixelRatio: 2.0, imageDecodeRegion: top);
      await worker.record(0, imagePixelRatio: 2.0, imageDecodeRegion: top);
      await worker.record(0,
          imagePixelRatio: 2.0, imageDecodeRegion: sameBucket);
      expect(inner.calls.length, 1,
          reason: 'minor region jitter stays in the same cache bucket');

      await worker.record(0, imagePixelRatio: 2.0, imageDecodeRegion: bottom);
      expect(inner.calls.length, 2,
          reason: 'a different viewport slice needs its own cropped buffer');

      await worker.record(0,
          imagePixelRatio: 2.0, decodeImages: false, imageDecodeRegion: bottom);
      await worker.record(0,
          imagePixelRatio: 2.0, decodeImages: false, imageDecodeRegion: top);
      expect(inner.calls.length, 3,
          reason: 'vector-only buffers ignore region because no images decode');
    });

    test('weight-0 region buffers reuse the page-wide cache key', () async {
      final inner = _CountingWorker();
      final worker = PdfCachingRenderWorker(inner);
      const top = PdfRect(0, 400, 200, 600);
      const bottom = PdfRect(0, 0, 200, 200);

      await worker.record(0, imagePixelRatio: 2.0, imageDecodeRegion: top);
      await worker.record(0, imagePixelRatio: 2.0, imageDecodeRegion: bottom);
      await worker.record(0, imagePixelRatio: 2.0);

      expect(inner.calls.length, 1,
          reason: 'vector-only pages must not cache duplicate region slices');
    });

    test('a tiny ratio wobble stays in the same bucket', () async {
      final inner = _CountingWorker();
      final worker = PdfCachingRenderWorker(inner);
      await worker.record(0, imagePixelRatio: 2.50);
      await worker.record(0,
          imagePixelRatio: 2.55); // 2.50*8=20, 2.55*8≈20.4→20
      expect(inner.calls.length, 1);
    });

    test('LRU eviction past the byte budget forces a re-decode', () async {
      // Each record weighs 8x8x4 = 256 bytes; a 300-byte budget holds one.
      final inner = _CountingWorker(decodedPixels: 64);
      final worker = PdfCachingRenderWorker(inner, budgetBytes: 300);
      await worker.record(0, imagePixelRatio: 2.0); // cache: {0}
      await worker.record(1, imagePixelRatio: 2.0); // cache: {1}, 0 evicted
      await worker.record(0, imagePixelRatio: 2.0); // miss: 0 was evicted
      expect(inner.calls.length, 3);
      await worker.record(0, imagePixelRatio: 2.0); // hit: 0 is now newest
      expect(inner.calls.length, 3);
    });

    test('reports decoded-byte cache pressure', () async {
      final inner = _CountingWorker(decodedPixels: 64);
      final worker = PdfCachingRenderWorker(inner, budgetBytes: 512);

      expect(worker.cacheBudgetBytes, 512);
      expect(worker.cachedBytes, 0);
      expect(worker.cachePressure, 0);

      await worker.record(0, imagePixelRatio: 2.0);
      expect(worker.cachedBytes, 256);
      expect(worker.cachePressure, 0.5);

      await worker.record(1, imagePixelRatio: 2.0);
      expect(worker.cachedBytes, 512);
      expect(worker.cachePressure, 1);
    });

    test('uses the runtime default cache budget when not overridden', () {
      final previous = pdfRenderWorkerCacheBudgetBytes;
      addTearDown(() => pdfRenderWorkerCacheBudgetBytes = previous);

      pdfRenderWorkerCacheBudgetBytes = 384;
      final worker = PdfCachingRenderWorker(_CountingWorker());
      addTearDown(worker.dispose);

      expect(worker.cacheBudgetBytes, 384);
    });

    test('explicit cache budget overrides the runtime default', () {
      final previous = pdfRenderWorkerCacheBudgetBytes;
      addTearDown(() => pdfRenderWorkerCacheBudgetBytes = previous);

      pdfRenderWorkerCacheBudgetBytes = 384;
      final worker =
          PdfCachingRenderWorker(_CountingWorker(), budgetBytes: 512);
      addTearDown(worker.dispose);

      expect(worker.cacheBudgetBytes, 512);
    });

    test('commandLimit is part of the vector-only cache key', () async {
      final inner = _CountingWorker();
      final worker = PdfCachingRenderWorker(inner);

      await worker.record(0, decodeImages: false, commandLimit: 500);
      await worker.record(0, decodeImages: false, commandLimit: 500);
      expect(inner.commandLimits, [500]);

      await worker.record(0, decodeImages: false, commandLimit: 2000);
      expect(inner.commandLimits, [500, 2000]);

      await worker.record(0, decodeImages: true, commandLimit: 500);
      await worker.record(0, decodeImages: true, commandLimit: 2000);
      expect(inner.commandLimits, [500, 2000, null],
          reason: 'full-image renders ignore preview command limits');
    });

    test('weight-0 buffers survive eviction of heavy pages', () async {
      // Budget holds one heavy (256-byte) page. The vector-first pass
      // (decodeImages: false) weighs nothing, so blowing the budget with heavy
      // full-image pages must not discard it - it would only be re-decoded.
      final inner = _CountingWorker(decodedPixels: 64);
      final worker = PdfCachingRenderWorker(inner, budgetBytes: 300);
      await worker.record(0, imagePixelRatio: 2.0, decodeImages: false); // 0 B
      await worker.record(1, imagePixelRatio: 2.0); // heavy, _bytes=256
      await worker.record(2, imagePixelRatio: 2.0); // heavy, evicts page 1 only
      expect(inner.calls.length, 3);
      // The costless vector-first buffer is still cached: a hit, not a re-ask.
      await worker.record(0, imagePixelRatio: 2.0, decodeImages: false);
      expect(inner.calls.length, 3, reason: 'weight-0 buffer must be kept');
      // The heavy page evicted to make room does have to re-decode.
      await worker.record(1, imagePixelRatio: 2.0);
      expect(inner.calls.length, 4, reason: 'page 1 was evicted');
    });

    test('null results are not cached', () async {
      final inner = _CountingWorker(returnNull: true);
      final worker = PdfCachingRenderWorker(inner);
      await worker.record(0, imagePixelRatio: 2.0);
      await worker.record(0, imagePixelRatio: 2.0);
      expect(inner.calls.length, 2, reason: 'a declined page must re-ask');
    });

    test('the record count is bounded so weight-0 pages cannot grow unbounded',
        () async {
      // Every record weighs 0 (image-free), so the byte budget never trips.
      // Without the entry cap these would pile up one-per-page for the whole
      // life of the worker - the unbounded growth issue #283 measured.
      final inner = _CountingWorker();
      final worker = PdfCachingRenderWorker(inner, maxEntries: 3);
      addTearDown(worker.dispose);
      for (var page = 0; page < 10; page++) {
        await worker.record(page, decodeImages: false);
      }
      expect(worker.cachedEntryCount, 3,
          reason: 'the cache is capped, not one entry per page scrolled');
      expect(inner.calls.length, 10);
      // The oldest pages were evicted, so page 0 must re-record.
      await worker.record(0, decodeImages: false);
      expect(inner.calls.length, 11, reason: 'the evicted page 0 re-records');
      // The most-recent survivors still hit.
      await worker.record(9, decodeImages: false);
      await worker.record(8, decodeImages: false);
      expect(inner.calls.length, 11, reason: 'recent pages stayed cached');
    });

    test('count eviction removes the least-recently-used record', () async {
      final inner = _CountingWorker();
      final worker = PdfCachingRenderWorker(inner, maxEntries: 3);
      addTearDown(worker.dispose);
      await worker.record(0, decodeImages: false); // {0}
      await worker.record(1, decodeImages: false); // {0,1}
      await worker.record(2, decodeImages: false); // {0,1,2}
      await worker.record(0, decodeImages: false); // hit: 0 now MRU -> {1,2,0}
      expect(inner.calls.length, 3);
      await worker.record(3, decodeImages: false); // count 4>3: evict LRU (1)
      expect(inner.calls.length, 4);
      expect(worker.cachedEntryCount, 3);
      await worker.record(0, decodeImages: false); // still cached
      await worker.record(2, decodeImages: false); // still cached
      expect(inner.calls.length, 4, reason: 'touched pages survived');
      await worker.record(1, decodeImages: false); // 1 was the LRU eviction
      expect(inner.calls.length, 5,
          reason: 'the least-recently-used page went');
    });

    test('count eviction of a heavy record frees its decoded bytes', () async {
      final inner = _CountingWorker(decodedPixels: 64); // 256 bytes each
      // A byte budget wide enough to never trip, so only the count cap evicts.
      final worker =
          PdfCachingRenderWorker(inner, budgetBytes: 1 << 20, maxEntries: 2);
      addTearDown(worker.dispose);
      await worker.record(0, imagePixelRatio: 2.0); // {0} bytes=256
      await worker.record(1, imagePixelRatio: 2.0); // {0,1} bytes=512
      await worker.record(2, imagePixelRatio: 2.0); // evict LRU 0, bytes=512
      expect(worker.cachedEntryCount, 2);
      expect(worker.cachedBytes, 256 * 2,
          reason: 'evicting the LRU heavy record decremented the byte total');
    });

    test('uses the runtime default cache max entries when not overridden', () {
      final previous = pdfRenderWorkerCacheMaxEntries;
      addTearDown(() => pdfRenderWorkerCacheMaxEntries = previous);

      pdfRenderWorkerCacheMaxEntries = 7;
      final worker = PdfCachingRenderWorker(_CountingWorker());
      addTearDown(worker.dispose);

      expect(worker.cacheMaxEntries, 7);
    });

    test('explicit max entries overrides the runtime default', () {
      final previous = pdfRenderWorkerCacheMaxEntries;
      addTearDown(() => pdfRenderWorkerCacheMaxEntries = previous);

      pdfRenderWorkerCacheMaxEntries = 7;
      final worker = PdfCachingRenderWorker(_CountingWorker(), maxEntries: 9);
      addTearDown(worker.dispose);

      expect(worker.cacheMaxEntries, 9);
    });

    test('retained command slots evict dense records by LRU', () async {
      final inner = _CountingWorker(commandCount: 4);
      final worker = PdfCachingRenderWorker(
        inner,
        maxEntries: 64,
        maxRetainedCommands: 5,
      );
      addTearDown(worker.dispose);

      await worker.record(0, decodeImages: false); // {0}: four slots
      expect(worker.cachedRetainedCommandCount, 4);
      await worker.record(1, decodeImages: false); // {1}: evicts page 0
      expect(worker.cachedEntryCount, 1);
      expect(worker.cachedRetainedCommandCount, 4);

      await worker.record(1, decodeImages: false); // hot page still hits
      expect(inner.calls.length, 2);
      await worker.record(0, decodeImages: false); // page 0 was the LRU
      expect(inner.calls.length, 3);
    });

    test('one oversize dense record remains reusable', () async {
      final inner = _CountingWorker(commandCount: 8);
      final worker = PdfCachingRenderWorker(
        inner,
        maxRetainedCommands: 5,
      );
      addTearDown(worker.dispose);

      await worker.record(0, decodeImages: false);
      expect(worker.cachedEntryCount, 1);
      expect(worker.cachedRetainedCommandCount, 8);
      await worker.record(0, decodeImages: false);
      expect(inner.calls.length, 1,
          reason: 'the newest difficult page must remain a hot cache hit');
    });

    test('uses the runtime default retained-command budget when not overridden',
        () {
      final previous = pdfRenderWorkerCacheMaxRetainedCommands;
      addTearDown(() => pdfRenderWorkerCacheMaxRetainedCommands = previous);

      pdfRenderWorkerCacheMaxRetainedCommands = 7;
      final worker = PdfCachingRenderWorker(_CountingWorker());
      addTearDown(worker.dispose);

      expect(worker.cacheMaxRetainedCommands, 7);
    });

    test('explicit retained-command budget overrides the runtime default', () {
      final previous = pdfRenderWorkerCacheMaxRetainedCommands;
      addTearDown(() => pdfRenderWorkerCacheMaxRetainedCommands = previous);

      pdfRenderWorkerCacheMaxRetainedCommands = 7;
      final worker = PdfCachingRenderWorker(
        _CountingWorker(),
        maxRetainedCommands: 9,
      );
      addTearDown(worker.dispose);

      expect(worker.cacheMaxRetainedCommands, 9);
    });

    test('record bypasses the cache while the inner worker is inactive',
        () async {
      final inner = _CountingWorker()..active = false;
      final worker = PdfCachingRenderWorker(inner);
      expect(worker.isActive, isFalse);
      expect(await worker.record(0, imagePixelRatio: 2.0), isNull);
    });

    test('dispose clears the cache and tears down the inner worker', () async {
      final inner = _CountingWorker();
      final worker = PdfCachingRenderWorker(inner);
      await worker.record(0, imagePixelRatio: 2.0);
      worker.dispose();
      expect(inner.disposed, isTrue);
    });
  });

  group('PdfPooledRenderWorker', () {
    test('reports record capacity through the cache wrapper', () {
      final pool = PdfPooledRenderWorker.fromWorkers([
        _CountingWorker(),
        _CountingWorker(),
        _CountingWorker(),
      ]);
      final cached = PdfCachingRenderWorker(pool);
      addTearDown(cached.dispose);

      expect(pool.concurrentRecordCapacity, 3);
      expect(cached.concurrentRecordCapacity, 3);
      expect(_CountingWorker().concurrentRecordCapacity, 1);
    });

    test('binds surfaces only to capable workers and balances sessions', () {
      final unsupported = _CountingWorker();
      final first = _SurfaceWorker();
      final second = _SurfaceWorker();
      final pool = PdfPooledRenderWorker.fromWorkers([
        unsupported,
        first,
        second,
      ]);
      addTearDown(pool.dispose);

      expect(pool.supportsPageSurfaces, isTrue);
      final surface1 = Object();
      final surface2 = Object();
      final firstSession = pool.createPageSurface(surface1);
      final secondSession = pool.createPageSurface(surface2);

      expect(firstSession, isNotNull);
      expect(secondSession, isNotNull);
      expect(first.surfaces, [same(surface1)]);
      expect(second.surfaces, [same(surface2)]);

      // Disposing a binding releases its long-lived pool load, so the next
      // surface can reuse that worker. Double-dispose must not underflow it.
      firstSession!
        ..dispose()
        ..dispose();
      final surface3 = Object();
      expect(pool.createPageSurface(surface3), isNotNull);
      expect(first.surfaces, [same(surface1), same(surface3)]);
      expect(second.surfaces, [same(surface2)]);
    });

    test('declines when no active pool worker supports page surfaces', () {
      final capableButInactive = _SurfaceWorker()..active = false;
      final pool = PdfPooledRenderWorker.fromWorkers([
        _CountingWorker(),
        capableButInactive,
      ]);
      addTearDown(pool.dispose);

      expect(pool.supportsPageSurfaces, isFalse);
      expect(pool.createPageSurface(Object()), isNull);
      expect(capableButInactive.surfaces, isEmpty);
    });

    test('binds one page surface family to the same warm worker', () {
      final first = _SurfaceWorker();
      final second = _SurfaceWorker();
      final pool = PdfPooledRenderWorker.fromWorkers([first, second]);
      addTearDown(pool.dispose);

      final base = Object();
      final detail = Object();
      expect(pool.createPageSurface(base, pageIndex: 7), isNotNull);
      expect(pool.createPageSurface(detail, pageIndex: 7), isNotNull);

      expect(first.surfaces, [same(base), same(detail)]);
      expect(second.surfaces, isEmpty,
          reason: 'the detail reuses the base transcript and image cache');
    });

    test('speculative records keep one worker idle for foreground', () async {
      final workers = [_ManualWorker(), _ManualWorker(), _ManualWorker()];
      final pool = PdfPooledRenderWorker.fromWorkers(workers);
      // All three pages hash to worker 1 under page % 3. Keeping the futures
      // outstanding makes the second spill to worker 0. The third queues on an
      // occupied speculative lane, preserving worker 2 for visible work.
      final speculative = [
        pool.record(1, priority: 1),
        pool.record(4, priority: 1),
        pool.record(7, priority: 1),
      ];
      expect(workers[0].calls.map((c) => c.$1), [4]);
      expect(workers[1].calls.map((c) => c.$1), [1, 7]);
      expect(workers[2].calls, isEmpty);

      final foreground = pool.record(10, priority: 0);
      expect(workers[2].calls.map((c) => c.$1), [10],
          reason: 'foreground spills immediately onto the reserved idle lane');
      for (final worker in workers) {
        worker.completeAll();
      }
      await Future.wait([...speculative, foreground]);
    });

    test('cancel routes to the worker chosen by load routing', () async {
      final workers = [_ManualWorker(), _ManualWorker(), _ManualWorker()];
      final pool = PdfPooledRenderWorker.fromWorkers(workers);
      final hot = pool.record(1, priority: 1); // static target worker 1
      final rerouted = pool.record(4, priority: 1); // spills to worker 0
      pool.cancel(4, priority: 1);
      expect(workers[0].cancels, [(4, 1)]);
      expect(workers[1].cancels, isEmpty);
      expect(workers[2].cancels, isEmpty);
      for (final worker in workers) {
        worker.completeAll();
      }
      await Future.wait([hot, rerouted]);
    });

    test('same page and priority reuse one worker until completion', () async {
      final workers = [_ManualWorker(), _ManualWorker(), _ManualWorker()];
      final pool = PdfPooledRenderWorker.fromWorkers(workers);
      final first = pool.record(1, priority: 1);
      final second = pool.record(1, priority: 1, decodeImages: false);
      expect(workers[1].calls.map((c) => c.$1), [1, 1]);
      expect(workers[0].calls, isEmpty);
      expect(workers[2].calls, isEmpty);

      pool.cancel(1, priority: 1);
      expect(workers[1].cancels, [(1, 1)]);
      for (final worker in workers) {
        worker.completeAll();
      }
      await Future.wait([first, second]);
    });

    test('a run of consecutive heavy pages spreads across the pool', () async {
      final workers = [_ManualWorker(), _ManualWorker(), _ManualWorker()];
      final pool = PdfPooledRenderWorker.fromWorkers(workers);
      final futures = [
        for (final page in [16, 17, 18, 19, 20, 21]) pool.record(page),
      ];
      // No worker gets more than its even share of the heavy cluster.
      expect(workers.map((w) => w.calls.length), everyElement(2));
      for (final worker in workers) {
        worker.completeAll();
      }
      await Future.wait(futures);
    });

    test('stays active while any worker is alive', () {
      final workers = [_CountingWorker(), _CountingWorker()];
      final pool = PdfPooledRenderWorker.fromWorkers(workers);
      expect(pool.isActive, isTrue);
      workers[0].active = false;
      expect(pool.isActive, isTrue,
          reason: 'one live worker keeps the pool up');
      workers[1].active = false;
      expect(pool.isActive, isFalse);
    });

    test('inactive workers are skipped while any sibling is active', () async {
      final live = _CountingWorker(decodedPixels: 16);
      final dead = _CountingWorker()..active = false; // returns null
      final pool = PdfPooledRenderWorker.fromWorkers([live, dead]);
      expect(await pool.record(0), isNotNull, reason: 'page 0 -> live worker');
      expect(await pool.record(1), isNotNull,
          reason: 'page 1 would hash to the dead worker, but routes to live');
      expect(dead.calls, isEmpty);
    });

    test('dispose tears down every worker', () {
      final workers = [_CountingWorker(), _CountingWorker(), _CountingWorker()];
      PdfPooledRenderWorker.fromWorkers(workers).dispose();
      expect(workers.every((w) => w.disposed), isTrue);
    });

    test('a pool of one is just a single worker with routing', () async {
      final only = _CountingWorker();
      final pool = PdfPooledRenderWorker.fromWorkers([only]);
      await pool.record(5, imagePixelRatio: 2.0);
      pool.cancel(5);
      expect(only.calls.single.$1, 5);
      expect(only.cancels.single, (5, 0));
    });

    test('a page keeps its sticky worker while loads are equal', () async {
      final workers = [_ManualWorker(), _ManualWorker()];
      final pool = PdfPooledRenderWorker.fromWorkers(workers);
      // Page 0 sticks to worker 0; page 1 loads worker 1 to the same level.
      final first = pool.record(0, priority: 1);
      final other = pool.record(1, priority: 0);
      final repeat = pool.record(0, priority: 0);
      expect(workers[0].calls.map((c) => c.$1), [0, 0],
          reason: 'equal load keeps the sticky worker (the transcript hit '
              'is never traded away to break a tie)');
      expect(workers[1].calls.map((c) => c.$1), [1]);
      for (final worker in workers) {
        worker.completeAll();
      }
      await Future.wait([first, other, repeat]);
    });

    test('a page re-routes from unrelated work to an idle worker', () async {
      final workers = [_ManualWorker(), _ManualWorker()];
      final pool = PdfPooledRenderWorker.fromWorkers(workers);
      // Establish page 0's affinity, then occupy that worker with another
      // page. The on-screen page must not queue behind unrelated work.
      final first = pool.record(0, priority: 1);
      workers[0].completeAll();
      await first;
      final background = pool.record(2, priority: 1);
      final onScreen = pool.record(0, priority: 0);
      expect(workers[0].calls.map((c) => c.$1), [0, 2]);
      expect(workers[1].calls.map((c) => c.$1), [0],
          reason: 'a strictly-less-loaded active worker wins over stickiness');
      for (final worker in workers) {
        worker.completeAll();
      }
      await Future.wait([background, onScreen]);
    });

    test('a visible page stays with its in-flight speculative warm', () async {
      final workers = [_ManualWorker(), _ManualWorker(), _ManualWorker()];
      final pool = PdfPooledRenderWorker.fromWorkers(workers);
      final warm = pool.record(1, priority: 3);
      final onScreen = pool.record(1, priority: 0);

      expect(workers[1].calls.map((c) => c.$1), [1, 1],
          reason: 'the foreground enqueue preempts/resumes the warm transcript '
              'instead of cold-starting on the reserved lane');
      expect(workers[0].calls, isEmpty);
      expect(workers[2].calls, isEmpty);
      for (final worker in workers) {
        worker.completeAll();
      }
      await Future.wait([warm, onScreen]);
    });

    test('a re-routed page follows its new worker afterwards', () async {
      final workers = [_ManualWorker(), _ManualWorker()];
      final pool = PdfPooledRenderWorker.fromWorkers(workers);
      final first = pool.record(0, priority: 1);
      workers[0].completeAll();
      await first;
      final background = pool.record(2, priority: 1);
      final onScreen = pool.record(0, priority: 0); // re-routes to worker 1
      for (final worker in workers) {
        worker.completeAll();
      }
      await Future.wait([background, onScreen]);

      final revisit = pool.record(0);
      expect(workers[1].calls.map((c) => c.$1), [0, 0],
          reason: 'the page sticks to the worker it was re-routed to');
      expect(workers[0].calls.map((c) => c.$1), [0, 2]);
      workers[1].completeAll();
      await revisit;
    });

    test('a single-worker pool always routes to worker 0', () async {
      final only = _ManualWorker();
      final pool = PdfPooledRenderWorker.fromWorkers([only]);
      final first = pool.record(3, priority: 1);
      final second = pool.record(3, priority: 0);
      expect(only.calls.map((c) => c.$1), [3, 3],
          reason: 'with one worker there is no alternative to re-route to');
      only.completeAll();
      await Future.wait([first, second]);
    });

    test(
        'every worker is seeded from one shared byte snapshot, not a '
        'per-worker copy', () {
      final source = Uint8List.fromList(List.generate(64, (i) => i & 0xff));
      final seeds = <Uint8List>[];
      final pool = PdfPooledRenderWorker.withSpawner(source, 3, (bytes) {
        seeds.add(bytes);
        return _SeedWorker(bytes);
      });
      addTearDown(pool.dispose);

      expect(seeds, hasLength(3), reason: 'three workers were spawned');
      // All three got the very same instance - no private per-worker copy.
      expect(identical(seeds[0], seeds[1]), isTrue);
      expect(identical(seeds[1], seeds[2]), isTrue);
      // And it is the pool's own snapshot, decoupled from the caller's bytes.
      expect(identical(seeds[0], source), isFalse);
      expect(seeds[0], equals(source));
    });

    test('the urgent one-off lane shares the same snapshot as the workers',
        () async {
      final source = Uint8List.fromList(List.generate(64, (i) => i & 0xff));
      final seeds = <Uint8List>[];
      final pool = PdfPooledRenderWorker.withSpawner(source, 2, (bytes) {
        seeds.add(bytes);
        return _SeedWorker(bytes);
      });
      addTearDown(pool.dispose);

      final workerSeed = seeds.first;
      // Priority -2000 routes past the pool into the lazily-spawned urgent
      // worker, which must reuse the snapshot rather than copy again.
      await pool.record(0, priority: -2000);
      expect(seeds, hasLength(3), reason: 'the urgent worker was spawned');
      expect(identical(seeds.last, workerSeed), isTrue);
    });

    test('copySource: false seeds directly from the caller buffer, no copy',
        () {
      final source = Uint8List.fromList(List.generate(64, (i) => i & 0xff));
      final seeds = <Uint8List>[];
      final pool = PdfPooledRenderWorker.withSpawner(source, 3, (bytes) {
        seeds.add(bytes);
        return _SeedWorker(bytes);
      }, copySource: false);
      addTearDown(pool.dispose);

      // Every worker is seeded from the caller's very buffer - no per-pool
      // snapshot allocation (#359: skip a full-document copy on stable bytes).
      expect(seeds, hasLength(3));
      expect(identical(seeds[0], source), isTrue);
      expect(identical(seeds[1], source), isTrue);
      expect(identical(seeds[2], source), isTrue);
    });
  });
}

/// A [PdfRenderWorker] that records the byte view it was constructed with, for
/// asserting the pool seeds every worker from one shared snapshot. Declines
/// every record (null → local), which is all the sharing tests need.
class _SeedWorker extends PdfRenderWorker {
  _SeedWorker(this.seed);

  final Uint8List seed;
  bool disposed = false;

  @override
  bool get isActive => !disposed;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
          {bool annotations = true,
          int priority = 0,
          double? imagePixelRatio,
          bool decodeImages = true,
          int? commandLimit,
          PdfRect? imageDecodeRegion,
          PdfPartialRecordSink? onPartial}) async =>
      null;

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() => disposed = true;
}

/// A [PdfRenderWorker] that records each [record] call and returns a synthetic
/// buffer of a chosen decoded weight - for exercising [PdfCachingRenderWorker]
/// without a real isolate or document.
class _CountingWorker extends PdfRenderWorker {
  _CountingWorker({
    this.decodedPixels = 0,
    this.returnNull = false,
    this.commandCount = 2,
  });

  /// Decoded pixels carried by each returned buffer (an N×N image, so the
  /// cache weight is decodedPixels*4 bytes). 0 returns image-free commands.
  final int decodedPixels;
  final bool returnNull;
  final int commandCount;
  final calls = <(int, bool, bool, double?)>[];
  final commandLimits = <int?>[];
  final cancels = <(int, int)>[];
  bool active = true;
  bool disposed = false;

  @override
  bool get isActive => active;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial}) async {
    calls.add((pageIndex, annotations, decodeImages, imagePixelRatio));
    commandLimits.add(commandLimit);
    if (returnNull || !active) return null;
    // A vector-first pass (decodeImages: false) ships no decoded pixels, so its
    // cached buffer weighs nothing - mirror that so the cache's weight-aware
    // eviction can be exercised.
    if (decodedPixels == 0 || !decodeImages) {
      return List<PdfRenderCommand>.unmodifiable(List.generate(
        commandCount,
        (index) =>
            index.isEven ? const PdfSaveCommand() : const PdfRestoreCommand(),
      ));
    }
    final side = math.sqrt(decodedPixels).round();
    final pixels = PdfDecodedPixels(Uint8List(side * side * 4), side, side);
    final request = PdfImageRequest(
      stream: CosStream(CosDictionary(), Uint8List(0)),
      transform: PdfMatrix.identity,
      decoded: pixels,
    );
    return [PdfDrawImageCommand(request)];
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) =>
      cancels.add((pageIndex, priority));

  @override
  void dispose() {
    active = false;
    disposed = true;
  }
}

class _SurfaceWorker extends _CountingWorker {
  final surfaces = <Object>[];
  final sessions = <_ProbePageSurfaceSession>[];

  @override
  bool get supportsPageSurfaces => active;

  @override
  PdfPageSurfaceSession? createPageSurface(
    Object surface, {
    int? pageIndex,
  }) {
    if (!active) return null;
    surfaces.add(surface);
    final session = _ProbePageSurfaceSession();
    sessions.add(session);
    return session;
  }
}

class _ProbePageSurfaceSession extends PdfPageSurfaceSession {
  final renders = <Map<String, Object?>>[];
  bool disposed = false;

  @override
  Future<bool> render(
    int pageIndex, {
    required bool annotations,
    required int width,
    required int height,
    required int pageColor,
    PdfPageSurfaceRegion? region,
    int? rotation,
    int priority = 0,
  }) async {
    renders.add({
      'pageIndex': pageIndex,
      'annotations': annotations,
      'width': width,
      'height': height,
      'pageColor': pageColor,
      'region': region,
      'rotation': rotation,
      'priority': priority,
    });
    return true;
  }

  @override
  void dispose() => disposed = true;
}

class _ManualWorker extends PdfRenderWorker {
  final calls = <(int, bool, bool, double?)>[];
  final priorities = <int>[];
  final cancels = <(int, int)>[];
  final _pending = <Completer<List<PdfRenderCommand>?>>[];
  bool active = true;
  bool disposed = false;

  @override
  bool get isActive => active;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial}) {
    calls.add((pageIndex, annotations, decodeImages, imagePixelRatio));
    priorities.add(priority);
    final completer = Completer<List<PdfRenderCommand>?>();
    _pending.add(completer);
    return completer.future;
  }

  void completeAll() {
    for (final completer in _pending.toList()) {
      if (!completer.isCompleted) {
        completer.complete(const [PdfSaveCommand(), PdfRestoreCommand()]);
      }
    }
    _pending.clear();
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) =>
      cancels.add((pageIndex, priority));

  @override
  void dispose() {
    active = false;
    disposed = true;
    for (final completer in _pending.toList()) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
  }
}

class _HangingWorker extends PdfRenderWorker {
  final callsByKey = <(int, int), int>{};
  final cancels = <(int, int)>[];
  final _pending = <Completer<List<PdfRenderCommand>?>>[];
  bool active = true;
  bool hang = true;

  int get calls => callsByKey.values.fold(0, (sum, value) => sum + value);

  @override
  bool get isActive => active;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial}) {
    if (!active) return Future.value(null);
    callsByKey[(pageIndex, priority)] =
        (callsByKey[(pageIndex, priority)] ?? 0) + 1;
    if (!hang) {
      return Future.value(const [PdfSaveCommand(), PdfRestoreCommand()]);
    }
    final completer = Completer<List<PdfRenderCommand>?>();
    _pending.add(completer);
    return completer.future;
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {
    cancels.add((pageIndex, priority));
  }

  @override
  void dispose() {
    active = false;
    for (final completer in _pending.toList()) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
  }
}

/// A small RGBA PNG with a varying alpha channel (so it embeds with an /SMask).
Uint8List _alphaPng() {
  final image = img.Image(width: 8, height: 8, numChannels: 4);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      image.setPixelRgba(x, y, x * 32, y * 32, 128, (x + y) * 16);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// A one-page PDF whose only content is a 4x4 inline image (BI .. ID .. EI).
Uint8List _inlineImagePdf() {
  const content = 'q 100 0 0 100 50 50 cm '
      'BI /W 4 /H 4 /CS /RGB /BPC 8 /F /AHx ID\n'
      'e63030 ffffff e63030 ffffff\n'
      'ffffff e63030 ffffff e63030\n'
      'e63030 ffffff e63030 ffffff\n'
      'ffffff e63030 ffffff e63030 >\nEI Q\n';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    buffer.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

/// A tiny uncompressed RGB image under a DCT-encoded grayscale soft mask.
/// This is the shape the native worker must leave for Flutter's platform JPEG
/// codec instead of decoding through package:image in the background isolate.
Uint8List _dctSoftMaskPdf() {
  const width = 8;
  const height = 4;
  final gray = img.Image(width: width, height: height);
  for (final pixel in gray) {
    final value = pixel.x < width ~/ 2 ? 255 : 0;
    pixel
      ..r = value
      ..g = value
      ..b = value;
  }
  final maskBytes = Uint8List.fromList(img.encodeJpg(gray, quality: 100));
  final builder = CosDocumentBuilder();
  final mask = builder.add(CosStream(
    CosDictionary({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Image'),
      'Width': const CosInteger(width),
      'Height': const CosInteger(height),
      'ColorSpace': const CosName('DeviceGray'),
      'BitsPerComponent': const CosInteger(8),
      'Filter': const CosName('DCTDecode'),
      'Length': CosInteger(maskBytes.length),
    }),
    maskBytes,
  ));
  final rgb = Uint8List(width * height * 3);
  for (var i = 0; i < width * height; i++) {
    rgb[i * 3] = 220;
    rgb[i * 3 + 1] = 40;
    rgb[i * 3 + 2] = 20;
  }
  final image = builder.add(CosStream(
    CosDictionary({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Image'),
      'Width': const CosInteger(width),
      'Height': const CosInteger(height),
      'ColorSpace': const CosName('DeviceRGB'),
      'BitsPerComponent': const CosInteger(8),
      'SMask': mask,
      'Length': CosInteger(rgb.length),
    }),
    rgb,
  ));
  final contentBytes = Uint8List.fromList(
    'q 200 0 0 100 0 0 cm /Im0 Do Q'.codeUnits,
  );
  final content = builder.add(CosStream(
    CosDictionary({'Length': CosInteger(contentBytes.length)}),
    contentBytes,
  ));
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final pagesRef = builder.add(pages);
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      const CosInteger(200),
      const CosInteger(100),
    ]),
    'Resources': CosDictionary({
      'XObject': CosDictionary({'Im0': image}),
    }),
    'Contents': content,
  }));
  pages
    ..['Kids'] = CosArray([page])
    ..['Count'] = const CosInteger(1);
  final root = builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pagesRef,
  }));
  return builder.build(root: root);
}
