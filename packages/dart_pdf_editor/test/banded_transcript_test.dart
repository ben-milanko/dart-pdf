// X-strip transcript banding: retention/eviction of the retained
// PdfRenderCommand transcript along the horizontal pan axis. The contract is
// (1) a resident-strip replay is byte-identical to the whole-transcript region
// replay, (2) retained bytes scale with the resident strips, not the whole
// page, and (3) an evicted strip re-materializes to an identical replay.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/banded_transcript.dart';
import 'package:dart_pdf_editor/src/region_replay_index.dart';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<ByteData> _bytes(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;

PdfPath _rectPath(double left, double bottom, double right, double top) =>
    PdfPath([
      PdfMoveTo(left, bottom),
      PdfLineTo(right, bottom),
      PdfLineTo(right, top),
      PdfLineTo(left, top),
      const PdfClosePath(),
    ]);

PdfFillPathCommand _box(
        double left, double bottom, double right, double top, PdfColor color) =>
    PdfFillPathCommand(
        _rectPath(left, bottom, right, top), color, PdfFillRule.nonzero, 1);

/// A wide, extreme-aspect transcript: a row of coloured boxes spread along X
/// (the pan axis) plus one wide stroke that spans several strips.
List<PdfRenderCommand> _wideTranscript() => [
      _box(0, 400, 80, 480, const PdfColor(1, 0, 0)),
      _box(200, 400, 280, 480, const PdfColor(0, 1, 0)),
      _box(400, 400, 480, 480, const PdfColor(0, 0, 1)),
      _box(600, 400, 680, 480, const PdfColor(1, 1, 0)),
      _box(800, 400, 880, 480, const PdfColor(1, 0, 1)),
      // Spans strips 1..4 of a 0..1000 X range.
      PdfStrokePathCommand(
        const PdfPath([PdfMoveTo(150, 300), PdfLineTo(850, 300)]),
        const PdfColor(0, 0, 0),
        const PdfStroke(width: 4),
        1,
      ),
      _box(950, 400, 1000, 480, const PdfColor(0, 1, 1)),
    ];

/// Replays a page-space [region] of [bands] into a raster the same way
/// PdfRetainedScene.rasterizeRegion would, for pixel comparison.
Future<ui.Image> _rasterBand(
  PdfPage page,
  PdfBandedTranscript bands,
  Rect region,
  double pixelRatio,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(pixelRatio)
    ..translate(-region.left, -region.top);
  const plan = PdfPageRenderPlan();
  PdfPageRenderer.preparePageCanvas(canvas, page, plan);
  final device = CanvasPdfDevice(canvas, images: const {});
  bands.replayRegion(
    _pageSpaceRegion(page, plan, region),
    device,
    canvas,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(
      (region.width * pixelRatio).ceil(),
      (region.height * pixelRatio).ceil(),
    );
  } finally {
    picture.dispose();
  }
}

PdfRect _pageSpaceRegion(PdfPage page, PdfPageRenderPlan plan, Rect region) {
  final size = plan.pageSize(page);
  final inverse = PdfPageRenderer.pageToDeviceMatrix(
    page,
    size,
    page.cropBox,
    rotation: plan.rotation,
    pixelRatio: 1,
  ).inverted()!;
  final corners = [
    (region.left, region.top),
    (region.right, region.top),
    (region.right, region.bottom),
    (region.left, region.bottom),
  ];
  var left = inverse.transformX(corners.first.$1, corners.first.$2);
  var right = left;
  var bottom = inverse.transformY(corners.first.$1, corners.first.$2);
  var top = bottom;
  for (final c in corners.skip(1)) {
    final x = inverse.transformX(c.$1, c.$2);
    final y = inverse.transformY(c.$1, c.$2);
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < bottom) bottom = y;
    if (y > top) top = y;
  }
  return PdfRect(left, bottom, right, top);
}

void main() {
  testWidgets('bands partition the transcript along the X pan axis',
      (tester) async {
    final index = PdfRegionReplayIndex.build(_wideTranscript(),
        maxCommands: 1 << 20);
    expect(index.supported, isTrue);

    // 10 strips over the 0..1000 X extent. The histogram counts each unit once
    // by its centre band, so it sums to the unit total and exposes the uneven
    // spread the CAD probe measured.
    final histogram = index.unitBandHistogram(10);
    expect(histogram.length, 10);
    expect(histogram.reduce((a, b) => a + b), index.units.length);

    final bands = PdfBandedTranscript.build(_wideTranscript(), bandCount: 10)!;
    expect(bands.bandCount, 10);
    expect(bands.residentBandCount, 10);
    // The wide stroke is retained by every strip it spans, so summed strip
    // lengths exceed the distinct unit count - but the byte estimate dedupes.
    final summedUnits =
        bands.bands.fold<int>(0, (n, b) => n + b.unitCount);
    expect(summedUnits, greaterThan(index.units.length));
  });

  testWidgets('resident-strip replay matches whole-transcript region replay',
      (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final commands = _wideTranscript();
      final scene =
          await PdfRetainedScene.fromCommands(page, commands, includeImages: false);
      addTearDown(scene.dispose);
      final bands = PdfBandedTranscript.build(commands, bandCount: 10)!;

      // A viewport over the left third of the page.
      final size = const PdfPageRenderPlan().pageSize(page);
      final region = Rect.fromLTWH(0, 0, size.width * 0.35, size.height);

      PdfRetainedScene.spatialRegionReplay = true;
      final expected = await scene.rasterizeRegion(region, pixelRatio: 2);
      final actual = await _rasterBand(page, bands, region, 2);
      expect(actual.width, expected.width);
      expect(actual.height, expected.height);
      expect((await _bytes(actual)).buffer.asUint8List(),
          (await _bytes(expected)).buffer.asUint8List(),
          reason: 'banded replay must match whole-transcript region replay');
      expected.dispose();
      actual.dispose();
    });
  });

  testWidgets('retained bytes scale with resident strips, not the whole page',
      (tester) async {
    final bands = PdfBandedTranscript.build(_wideTranscript(), bandCount: 10)!;
    final full = bands.estimatedFullBytes;
    expect(full, greaterThan(0));

    // Evict everything outside the left-third viewport (page X 0..~200 of
    // 0..1000). Only the strips overlapping it stay resident.
    final kept = bands.evictOutside(const PdfRect(0, 0, 200, 1000));
    expect(kept, greaterThan(0));
    expect(bands.residentBandCount, lessThan(bands.bandCount));
    expect(bands.estimatedResidentBytes, lessThan(full),
        reason: 'evicting offscreen strips must lower retained bytes');

    // A viewport that pans into an evicted strip is reported as incomplete.
    final missing = bands.missingBandsForRegion(const PdfRect(600, 0, 900, 1000));
    expect(missing, isNotEmpty);
  });

  testWidgets('an evicted strip re-materializes to an identical replay',
      (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final commands = _wideTranscript();
      final scene =
          await PdfRetainedScene.fromCommands(page, commands, includeImages: false);
      addTearDown(scene.dispose);
      final size = const PdfPageRenderPlan().pageSize(page);

      // A viewport over the right third, where strips will have been evicted.
      final region =
          Rect.fromLTWH(size.width * 0.6, 0, size.width * 0.4, size.height);

      PdfRetainedScene.spatialRegionReplay = true;
      final expected = await scene.rasterizeRegion(region, pixelRatio: 2);

      final bands = PdfBandedTranscript.build(commands, bandCount: 10)!;
      // Evict the strips this viewport needs.
      final pageRegion =
          _pageSpaceRegion(page, const PdfPageRenderPlan(), region);
      for (final band in bands.bands) {
        bands.evict(band.index);
      }
      expect(bands.residentBandCount, 0);
      expect(bands.missingBandsForRegion(pageRegion), isNotEmpty);

      // Re-materialize from a freshly recorded (identical) transcript.
      final restored = bands.restore(_wideTranscript());
      expect(restored, isNotEmpty);
      expect(bands.missingBandsForRegion(pageRegion), isEmpty);

      final actual = await _rasterBand(page, bands, region, 2);
      expect((await _bytes(actual)).buffer.asUint8List(),
          (await _bytes(expected)).buffer.asUint8List(),
          reason: 're-materialized strips must replay identically');
      expected.dispose();
      actual.dispose();
    });
  });

  testWidgets('restoring a subset does not double-count a spanning paint',
      (tester) async {
    final bands = PdfBandedTranscript.build(_wideTranscript(), bandCount: 5)!;
    final full = bands.estimatedFullBytes;

    // Evict the middle strips only, so the wide stroke stays resident in the
    // outer strips while its restored copies land as fresh instances.
    bands.evict(2);
    bands.evict(3);
    expect(bands.estimatedResidentBytes, lessThan(full));

    bands.restore(_wideTranscript());
    expect(bands.residentBandCount, 5);
    expect(bands.estimatedResidentBytes, full,
        reason: 'a strip-spanning paint is one command across resident and '
            'restored strips - dedup is by painter order, not instance');
  });

  testWidgets('evictAll frees every strip; estimated bytes fall to zero',
      (tester) async {
    final bands = PdfBandedTranscript.build(_wideTranscript(), bandCount: 8)!;
    expect(bands.residentBandCount, 8);
    expect(bands.estimatedResidentBytes, greaterThan(0));
    bands.evictAll();
    expect(bands.residentBandCount, 0);
    expect(bands.estimatedResidentBytes, 0);
    // Every strip the page covers is now missing.
    expect(bands.missingBandsForRegion(PdfRect(bands.xMin, 0, bands.xMax, 1000)),
        isNotEmpty);
  });

  testWidgets('scene.reband re-materializes evicted strips via one re-record',
      (tester) async {
    await tester.runAsync(() async {
      // A recorded scene (commands == record(page, plan)), so reband's
      // re-record reproduces the identical transcript.
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.record(page);
      addTearDown(scene.dispose);

      final bands = scene.bandTranscript(bandCount: 6);
      expect(bands, isNotNull,
          reason: 'the classic page must be spatially indexable');
      expect(bands!.residentBandCount, 6);

      // No-op while every strip is resident.
      expect(await scene.reband(), isEmpty);

      bands.evictAll();
      expect(bands.residentBandCount, 0);

      final restored = await scene.reband();
      expect(restored, isNotEmpty);
      expect(bands.residentBandCount, 6,
          reason: 'reband restores every evicted strip');
    });
  });

  testWidgets('scene exposes the histogram, drop, and banding primitives',
      (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final scene = await PdfRetainedScene.fromCommands(
          page, _wideTranscript(),
          includeImages: false);
      addTearDown(scene.dispose);

      final histogram = scene.debugUnitBandHistogram(10);
      expect(histogram.length, 10);
      expect(histogram.reduce((a, b) => a + b), greaterThan(0));

      final bands = scene.bandTranscript(bandCount: 10);
      expect(bands, isNotNull);
      expect(identical(scene.bands, bands), isTrue);
      expect(scene.debugHasRegionReplayIndex, isTrue);

      scene.dropRegionIndex();
      expect(scene.debugHasRegionReplayIndex, isFalse);
      expect(scene.bands, isNull);

      // A memory-pressure sweep sheds spatial metadata on live scenes.
      scene.bandTranscript(bandCount: 4);
      final touched = PdfRetainedScene.handleMemoryPressure();
      expect(touched, greaterThanOrEqualTo(1));
      expect(scene.bands, isNull);
      expect(scene.debugHasRegionReplayIndex, isFalse);
    });
  });
}
