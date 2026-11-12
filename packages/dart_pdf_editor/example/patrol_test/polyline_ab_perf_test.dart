// #1270 A/B: does submitting straight polylines as line segments let Flutter
// 3.50's Impeller (UberSDF lines on desktop) rasterize CAD/plan linework
// faster than a tessellated stroked path, and at what pixel cost?
//
// Runs on the macOS Patrol lane (Metal). Every mode is measured in the same
// process, interleaved, so runner noise hits all of them alike. Results are
// logged as `[polyline-ab]` lines; CI copies them into the job summary.
// Nothing here gates on time - only the sanity checks can fail.
// The A/B switch is a debug seam; this harness is its intended caller.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:patrol/patrol.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

const _repetitions = 8;
const _pageRatio = 2.0;
const _zoomRatio = 8.0;

void main() {
  patrolTest('A/Bs straight-polyline submission on a plan sheet', ($) async {
    expect($.isWeb, isFalse);
    await $.pumpWidget(const MaterialApp(home: SizedBox()));
    await runPolylineAb();
    await $.pumpWidget(const SizedBox());
    await $.pump(const Duration(milliseconds: 50));
  });
}

void _log(String message) => debugPrint('[polyline-ab] $message');

double _p50(List<double> v) {
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

Future<Uint8List> _pixels(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();

/// Mean absolute channel difference, and the share of pixels that differ by
/// more than 32 in any channel (a visible change, not AA noise).
(double, double) _diff(Uint8List a, Uint8List b) {
  var total = 0;
  var visible = 0;
  for (var i = 0; i < a.length; i += 4) {
    var worst = 0;
    for (var c = 0; c < 3; c++) {
      final d = (a[i + c] - b[i + c]).abs();
      total += d;
      if (d > worst) worst = d;
    }
    if (worst > 32) visible++;
  }
  return (total / (a.length / 4 * 3), visible / (a.length / 4));
}

Future<void> runPolylineAb() async {
  final document = PdfDocument.open(buildSyntheticPlanPolylines());
  final page = document.page(0);
  final recorder = RecordingPdfDevice();
  PdfInterpreter(cos: document.cos, device: recorder).drawPage(page);
  final commands = recorder.commands;
  final size = const PdfPageRenderPlan().pageSize(page);
  // A 300x200 pt window in the middle of the sheet for the deep-zoom check,
  // where a dropped miter wedge would be widest.
  final zoomRegion = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2), width: 300, height: 200);

  final recordMs = {
    for (final m in PdfPolylineSubmission.values) m: <double>[]
  };
  final rasterMs = {
    for (final m in PdfPolylineSubmission.values) m: <double>[]
  };
  final pictureBytes = <PdfPolylineSubmission, int>{};
  final pagePixels = <PdfPolylineSubmission, Uint8List>{};
  final zoomPixels = <PdfPolylineSubmission, Uint8List>{};
  final modes = PdfPolylineSubmission.values;
  _log(
      'fixture strokes=3000 page=${size.width.round()}x${size.height.round()}pt '
      'ratio=$_pageRatio reps=$_repetitions (+1 warm-up) '
      'platform=${defaultTargetPlatform.name}');
  try {
    for (var rep = -1; rep < _repetitions; rep++) {
      // Rotate the order each repetition so no mode always runs first.
      for (var k = 0; k < modes.length; k++) {
        final mode = modes[(k + rep + 1) % modes.length];
        CanvasPdfDevice.debugStraightPolylines = mode;
        final record = Stopwatch()..start();
        final picture = await PdfPageRenderer.pictureFromCommands(
            page, commands,
            includeImages: false);
        record.stop();
        final raster = Stopwatch()..start();
        // A one-layer scene hands the engine the picture as recorded; the
        // future completes when the GPU has rasterized it.
        final image =
            await PdfPageRenderer.rasterizeViaLayer(picture, size, _pageRatio);
        raster.stop();
        if (rep >= 0) {
          recordMs[mode]!.add(record.elapsedMicroseconds / 1000);
          rasterMs[mode]!.add(raster.elapsedMicroseconds / 1000);
        } else {
          pictureBytes[mode] = picture.approximateBytesUsed;
          pagePixels[mode] = await _pixels(image);
          final zoom = await PdfPageRenderer.rasterizeRegion(
              picture, zoomRegion, _zoomRatio);
          zoomPixels[mode] = await _pixels(zoom);
          zoom.dispose();
        }
        image.dispose();
        picture.dispose();
      }
    }
  } finally {
    CanvasPdfDevice.debugStraightPolylines = PdfPolylineSubmission.path;
  }

  final baseRaster = _p50(rasterMs[PdfPolylineSubmission.path]!);
  for (final mode in modes) {
    final (pageMean, pageVisible) =
        _diff(pagePixels[PdfPolylineSubmission.path]!, pagePixels[mode]!);
    final (zoomMean, zoomVisible) =
        _diff(zoomPixels[PdfPolylineSubmission.path]!, zoomPixels[mode]!);
    final raster = _p50(rasterMs[mode]!);
    _log('mode=${mode.name} '
        'rasterMsP50=${raster.toStringAsFixed(1)} '
        'rasterVsPath=${(100 * (raster - baseRaster) / baseRaster).toStringAsFixed(1)}% '
        'recordMsP50=${_p50(recordMs[mode]!).toStringAsFixed(1)} '
        'pictureKB=${(pictureBytes[mode]! / 1024).round()} '
        'pageDiffMean=${pageMean.toStringAsFixed(3)} '
        'pageVisible=${(100 * pageVisible).toStringAsFixed(3)}% '
        'zoom${_zoomRatio.toInt()}xDiffMean=${zoomMean.toStringAsFixed(3)} '
        'zoomVisible=${(100 * zoomVisible).toStringAsFixed(3)}% '
        'rasterSamples=${rasterMs[mode]!.map((v) => v.toStringAsFixed(1)).join(',')}');
  }

  // Sanity only: every mode painted the sheet (not blank, not wildly off).
  for (final mode in modes) {
    final (mean, _) =
        _diff(pagePixels[PdfPolylineSubmission.path]!, pagePixels[mode]!);
    expect(mean, lessThan(8),
        reason: '${mode.name} should draw the same sheet');
  }
}
