// PdfRetainedScene correctness: a replayed scene must rasterize
// byte-identically to the shipping cached-picture zoom path at every scale -
// same commands, same decoded images, same canvas transform stack, so any
// divergence is a bug in the scene's plumbing.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<ByteData> _bytes(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;

void main() {
  testWidgets('retained-scene replay matches the cached-picture raster',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildClassicPdf());
      final page = doc.page(0);
      const plan = PdfPageRenderPlan();
      final size = plan.pageSize(page);

      final picture =
          await PdfPageRenderer.renderPictureRecordedWithPlan(page, plan);
      final scene = await PdfRetainedScene.record(page, plan: plan);

      for (final ratio in [0.7, 1.0, 2.4]) {
        final current = await PdfPageRenderer.rasterize(picture, size, ratio);
        final retained = await scene.rasterize(pixelRatio: ratio);
        expect(retained.width, current.width, reason: 'ratio $ratio');
        expect(retained.height, current.height, reason: 'ratio $ratio');
        final a = await _bytes(current);
        final b = await _bytes(retained);
        expect(a.buffer.asUint8List(), b.buffer.asUint8List(),
            reason: 'raster mismatch at ratio $ratio');
        current.dispose();
        retained.dispose();
      }

      // Region replay mirrors rasterizeRegion.
      final region = Rect.fromLTWH(
          size.width / 4, size.height / 4, size.width / 2, size.height / 2);
      final currentRegion =
          await PdfPageRenderer.rasterizeRegion(picture, region, 3.0);
      final retainedRegion =
          await scene.rasterizeRegion(region, pixelRatio: 3.0);
      expect(retainedRegion.width, currentRegion.width);
      expect(retainedRegion.height, currentRegion.height);
      final a = await _bytes(currentRegion);
      final b = await _bytes(retainedRegion);
      expect(a.buffer.asUint8List(), b.buffer.asUint8List(),
          reason: 'region raster mismatch');
      currentRegion.dispose();
      retainedRegion.dispose();

      // Replay is synchronous and reusable: two replays from one recording.
      final p1 = scene.replay(pixelRatio: 1.0);
      final p2 = scene.replay(pixelRatio: 2.0);
      expect(scene.commands, isNotEmpty);
      p1.dispose();
      p2.dispose();

      scene.dispose();
      picture.dispose();
    });
  });

  testWidgets('retained scene exposes its already-decoded images',
      (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildEmbeddedFontImagePdf()).page(0);
      final scene = await PdfRetainedScene.record(page);
      addTearDown(scene.dispose);
      final imageCommand =
          scene.commands.whereType<PdfDrawImageCommand>().first;
      final image = scene.imageFor(imageCommand.request);
      expect(image, isNotNull);
      expect(image!.width, greaterThan(0));
      expect(image.height, greaterThan(0));
    });
  });

  testWidgets('local retained scenes can be re-recorded for overprint retry',
      (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final source = await PdfRetainedScene.record(
        page,
        maxImagePixelRatio: 1.5,
        imageDecodeHeadroom: 1,
      );
      final retryFuture = source.rerecordWithOverprintMaxDimension(768);
      expect(retryFuture, isNotNull);
      final retry = await retryFuture!;
      expect(retry.page, same(source.page));
      expect(retry.plan, same(source.plan));
      expect(retry.commands.length, source.commands.length);

      final imported = await PdfRetainedScene.fromCommands(
        page,
        source.commands,
        includeImages: false,
      );
      final completeImported = await PdfRetainedScene.fromCommands(
        page,
        source.commands,
        allowOverprintRerecord: true,
      );
      final filtered = await PdfRetainedScene.record(
        page,
        skipAnnotation: (_) => false,
      );
      expect(imported.rerecordWithOverprintMaxDimension(768), isNull);
      final importedRetryFuture =
          completeImported.rerecordWithOverprintMaxDimension(768);
      expect(importedRetryFuture, isNotNull);
      final importedRetry = await importedRetryFuture!;
      expect(filtered.rerecordWithOverprintMaxDimension(768), isNull);

      filtered.dispose();
      importedRetry.dispose();
      completeImported.dispose();
      imported.dispose();
      retry.dispose();
      source.dispose();
    });
  });

  testWidgets('retained scene releases uploaded worker RGBA', (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildEmbeddedFontImagePdf()).page(0);
      final source = await PdfRetainedScene.record(page);
      final original = source.commands.whereType<PdfDrawImageCommand>().first;
      final request = PdfImageRequest(
        stream: original.request.stream,
        transform: original.request.transform,
        alpha: original.request.alpha,
        isStencil: original.request.isStencil,
        stencilColor: original.request.stencilColor,
        isInline: original.request.isInline,
        sourceReference: original.request.sourceReference,
        decoded: PdfDecodedPixels(Uint8List.fromList([255, 0, 0, 255]), 1, 1),
      );
      final scene = await PdfRetainedScene.fromCommands(
        page,
        [PdfDrawImageCommand(request)],
      );
      addTearDown(source.dispose);
      addTearDown(scene.dispose);

      expect(request.decoded, isNull,
          reason: 'the engine image now owns the uploaded pixels');
      expect(request.decodedWidth, 1);
      expect(request.decodedHeight, 1);
      final image = scene.imageFor(request);
      expect(image, isNotNull);
      expect(image!.width, 1);
      expect(image.height, 1);
    });
  });

  testWidgets('disposing an uncompiled GPU scene releases worker RGBA',
      (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildEmbeddedFontImagePdf()).page(0);
      final source = await PdfRetainedScene.record(page);
      addTearDown(source.dispose);
      final original = source.commands.whereType<PdfDrawImageCommand>().first;
      final request = PdfImageRequest(
        stream: original.request.stream,
        transform: original.request.transform,
        decoded: PdfDecodedPixels(Uint8List.fromList([255, 0, 0, 255]), 1, 1),
      );
      final scene = await PdfRetainedScene.fromCommands(
        page,
        [PdfDrawImageCommand(request)],
        retainDecodedPixels: true,
      );

      expect(request.decoded, isNotNull,
          reason: 'the direct-upload backend still owns the worker payload');
      scene.dispose();
      expect(request.decoded, isNull,
          reason: 'an evicted speculative scene may never compile a GPU '
              'session, so disposal must close the ownership path');
    });
  });

  testWidgets(
      'region replay selects paints, preserves clips, and stays bounded',
      (tester) async {
    await tester.runAsync(() async {
      final previousEnabled = PdfRetainedScene.spatialRegionReplay;
      final previousMax = PdfRetainedScene.spatialRegionReplayMaxCommands;
      addTearDown(() {
        PdfRetainedScene.spatialRegionReplay = previousEnabled;
        PdfRetainedScene.spatialRegionReplayMaxCommands = previousMax;
      });
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final commands = <PdfRenderCommand>[
        const PdfSaveCommand(),
        PdfClipPathCommand(_rectPath(0, 580, 220, 792), PdfFillRule.nonzero),
        PdfFillPathCommand(
          _rectPath(20, 650, 100, 740),
          const PdfColor(1, 0, 0),
          PdfFillRule.nonzero,
          1,
        ),
        PdfFillPathCommand(
          _rectPath(420, 650, 500, 740),
          const PdfColor(0, 0, 1),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfRestoreCommand(),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        PdfStrokePathCommand(
          const PdfPath([
            PdfMoveTo(30, 620),
            PdfLineTo(180, 620),
          ]),
          const PdfColor(0, 0, 0),
          const PdfStroke(width: 3),
          1,
        ),
        PdfFillPathCommand(
          _rectPath(440, 200, 520, 280),
          const PdfColor(0, 1, 0),
          PdfFillRule.nonzero,
          1,
        ),
      ];
      final scene = await PdfRetainedScene.fromCommands(
        page,
        commands,
        includeImages: false,
      );
      addTearDown(scene.dispose);
      expect(scene.debugHasRegionReplayIndex, isFalse,
          reason: 'full-page creation must not build region metadata');
      final fullPicture = scene.replay(pixelRatio: 1);
      fullPicture.dispose();
      expect(scene.debugHasRegionReplayIndex, isFalse,
          reason: 'full-page replay remains on its unchanged fast path');

      const region = Rect.fromLTWH(0, 0, 220, 220);
      PdfRetainedScene.spatialRegionReplay = false;
      final expected = await scene.rasterizeRegion(region, pixelRatio: 2);
      PdfRetainedScene.spatialRegionReplay = true;
      final actual = await scene.rasterizeRegion(region, pixelRatio: 2);
      expect(
        (await _bytes(actual)).buffer.asUint8List(),
        (await _bytes(expected)).buffer.asUint8List(),
      );
      expected.dispose();
      actual.dispose();

      expect(scene.debugLastRegionReplayWasSelective, isTrue);
      expect(
          scene.debugLastRegionReplayCommandCount, lessThan(commands.length));
      expect(scene.debugRegionReplayUnitCount, 3,
          reason: 'the clipped-away and far-right paints are not indexed');
      expect(scene.debugRegionReplayEstimatedBytes, lessThan(512));
      final selected = scene.selectRegion(region)!;
      expect(selected.map((unit) => unit.commandIndex), [2, 6]);
      expect(selected.first.clips?.command, same(commands[1]));
      expect(selected.first.blendMode, PdfBlendMode.normal);
      expect(selected.last.blendMode, PdfBlendMode.multiply);
      scene.dispose();
      expect(scene.debugHasRegionReplayIndex, isFalse,
          reason: 'disposing the scene releases retained index metadata');
    });
  });

  testWidgets('groups and over-budget transcripts fall back to full replay',
      (tester) async {
    await tester.runAsync(() async {
      final previousMax = PdfRetainedScene.spatialRegionReplayMaxCommands;
      final previousGridMax = PdfRetainedScene.spatialGridReplayMaxCommands;
      addTearDown(() {
        PdfRetainedScene.spatialRegionReplayMaxCommands = previousMax;
        PdfRetainedScene.spatialGridReplayMaxCommands = previousGridMax;
      });
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final grouped = await PdfRetainedScene.fromCommands(
        page,
        [
          const PdfBeginGroupCommand(.5),
          PdfFillPathCommand(
            _rectPath(20, 650, 100, 740),
            const PdfColor(1, 0, 0),
            PdfFillRule.nonzero,
            1,
          ),
          const PdfEndGroupCommand(),
        ],
        includeImages: false,
      );
      addTearDown(grouped.dispose);
      final image = await grouped.rasterizeRegion(
        const Rect.fromLTWH(0, 0, 220, 220),
        pixelRatio: 2,
      );
      image.dispose();
      expect(grouped.debugLastRegionReplayWasSelective, isFalse);
      expect(grouped.debugRegionReplaySupported, isFalse);

      // Over BOTH ceilings (linear and grid): genuine full-replay fallback.
      PdfRetainedScene.spatialRegionReplayMaxCommands = 1;
      PdfRetainedScene.spatialGridReplayMaxCommands = 1;
      final commands = [
        PdfFillPathCommand(
          _rectPath(20, 650, 100, 740),
          const PdfColor(1, 0, 0),
          PdfFillRule.nonzero,
          1,
        ),
        PdfFillPathCommand(
          _rectPath(420, 650, 500, 740),
          const PdfColor(0, 0, 1),
          PdfFillRule.nonzero,
          1,
        ),
      ];
      final bounded = await PdfRetainedScene.fromCommands(page, commands,
          includeImages: false);
      addTearDown(bounded.dispose);
      final boundedImage = await bounded.rasterizeRegion(
        const Rect.fromLTWH(0, 0, 220, 220),
        pixelRatio: 2,
      );
      boundedImage.dispose();
      expect(bounded.debugLastRegionReplayWasSelective, isFalse);
      expect(bounded.debugRegionReplaySupported, isFalse);

      // Over the linear ceiling but UNDER the grid ceiling: escalates to the
      // grid spatial index rather than full-replaying the transcript.
      PdfRetainedScene.spatialGridReplayMaxCommands = 1000;
      final escalated = await PdfRetainedScene.fromCommands(page, commands,
          includeImages: false);
      addTearDown(escalated.dispose);
      final escalatedImage = await escalated.rasterizeRegion(
        const Rect.fromLTWH(0, 0, 220, 220),
        pixelRatio: 2,
      );
      escalatedImage.dispose();
      expect(escalated.debugRegionReplaySupported, isTrue);
      expect(escalated.debugLastRegionReplayWasSelective, isTrue);
    });
  });
}

PdfPath _rectPath(double left, double bottom, double right, double top) =>
    PdfPath([
      PdfMoveTo(left, bottom),
      PdfLineTo(right, bottom),
      PdfLineTo(right, top),
      PdfLineTo(left, top),
      const PdfClosePath(),
    ]);
