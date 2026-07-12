// The dense-page strip zoom router (PdfPageView.stripZoomReplay):
//
//  - flag ON + page above retainedZoomReplayMaxCommands -> the scene IS
//    retained and zoom re-rasters re-bin through StripPdfDevice
//    (observable via the device's batching telemetry);
//  - flag OFF -> exactly the #208 behavior: over-ceiling pages retain no
//    scene and zoom via the classic cached-picture re-raster (no strip
//    device activity at all);
//  - image sanity: the strip replay of a retained scene stays visually
//    equivalent to the canvas replay (non-blank, bounded mean diff - the
//    devices differ only in AA coverage on edges, same tolerance family as
//    the Ghent parity gate), for the full page and the region variant.
//
// The image-sanity test must run FIRST: after the widget zoom tests, later
// tester.runAsync platform work in this same file (decodeImageFromPixels
// inside the strip atlas upload) never completes - test files run in their
// own isolates, so the order only matters within this file.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// A one-page classic-xref PDF with solid vector content (fills + a
/// stroke), so the strip device has geometry to bin (text through a
/// non-embedded Type1 font would delegate to the canvas fallback).
Uint8List buildVectorPdf() {
  const content = '1 0 0 rg 72 600 200 100 re f '
      '0 0 1 rg 300 300 150 220 re f '
      '0 0.6 0 RG 6 w 72 100 m 500 250 l S';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

Future<Uint8List> _rgba(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();

double _meanAbsDiff(Uint8List a, Uint8List b) {
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / a.length;
}

/// Pumps until the page's RawImage raster reaches [width] px (the async
/// strip replay takes a few event-loop turns for the atlas decode).
/// Shared with strip_plan_device_test.
Future<ui.Image> settleRaster(WidgetTester tester, int width) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
    final images = find.byType(RawImage);
    if (images.evaluate().isNotEmpty) {
      final image = tester.widget<RawImage>(images).image;
      if (image != null && image.width == width) return image;
    }
  }
  fail('raster never reached $width px wide');
}

void main() {
  test('stripZoomReplay defaults ON, guarded by the Impeller gate', () {
    expect(PdfPageView.stripZoomReplay, isTrue,
        reason: 'worker binning + the backend gate made this the default');
    expect(PdfPageView.debugStripZoomReplayBackendOverride, isNull,
        reason: 'production asks the engine (isShaderFilterSupported)');
  });

  testWidgets('strip replay stays visually equivalent to the canvas replay',
      (tester) async {
    await tester.runAsync(() async {
      final doc = PdfDocument.open(buildVectorPdf());
      final page = doc.page(0);
      final scene = await PdfRetainedScene.record(page);
      for (final ratio in [1.0, 2.4]) {
        final canvasImage = await scene.rasterize(pixelRatio: ratio);
        final stripImage = await scene.rasterizeStrips(pixelRatio: ratio);
        expect(stripImage.width, canvasImage.width, reason: 'ratio $ratio');
        expect(stripImage.height, canvasImage.height, reason: 'ratio $ratio');
        final a = await _rgba(canvasImage);
        final b = await _rgba(stripImage);
        // non-blank: the fills must actually land
        expect(b.any((v) => v < 128), isTrue,
            reason: 'strip raster is blank at ratio $ratio');
        // same tolerance family as the Ghent parity gate: the devices agree
        // except for AA coverage on shape edges
        expect(_meanAbsDiff(a, b), lessThanOrEqualTo(2.0),
            reason: 'strip raster diverges at ratio $ratio');
        canvasImage.dispose();
        stripImage.dispose();
      }

      // region variant: same crop through both devices, over the blue rect
      // (PDF y 300..520 = raster y 272..492 on the 792pt page)
      const region = Rect.fromLTWH(290, 300, 200, 150);
      final canvasRegion =
          await scene.rasterizeRegion(region, pixelRatio: 2);
      final stripRegion =
          await scene.rasterizeRegionStrips(region, pixelRatio: 2);
      expect(stripRegion.width, canvasRegion.width);
      expect(stripRegion.height, canvasRegion.height);
      final a = await _rgba(canvasRegion);
      final b = await _rgba(stripRegion);
      expect(b.any((v) => v < 128), isTrue, reason: 'region raster is blank');
      expect(_meanAbsDiff(a, b), lessThanOrEqualTo(2.0));
      canvasRegion.dispose();
      stripRegion.dispose();
      scene.dispose();
    });
  });
  testWidgets(
      'stripZoomReplay routes over-ceiling zooms through the strip device',
      (tester) async {
    PdfPageView.retainedZoomReplayMaxCommands = 0; // every page is "dense"
    PdfPageView.stripZoomReplay = true;
    // flutter test runs on software Skia where the Impeller gate
    // (ui.ImageFilter.isShaderFilterSupported) is false; force it on so the
    // router logic itself is exercised.
    PdfPageView.debugStripZoomReplayBackendOverride = true;
    addTearDown(() {
      PdfPageView.retainedZoomReplayMaxCommands = 20000;
      PdfPageView.stripZoomReplay = true; // the default
      PdfPageView.debugStripZoomReplayBackendOverride = null;
    });
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildVectorPdf());
    final page = doc.page(0);
    Widget at(double scale) => Center(
        child:
            SizedBox(width: 612, child: PdfPageView(page: page, scale: scale)));

    StripPdfDevice.resetStats();
    await tester.pumpWidget(at(1));
    final base = await settleRaster(tester, 612);
    expect(base.width, 612);

    // the zoom settle must re-bin through the strip device
    StripPdfDevice.resetStats();
    await tester.pumpWidget(at(3));
    final zoomed = await settleRaster(tester, 612 * 3);
    expect(zoomed.width, 612 * 3);
    expect(StripPdfDevice.totalStripQuads, greaterThan(0),
        reason: 'the zoom re-raster must have binned strip quads');
  });

  testWidgets(
      'flag off: over-ceiling pages keep the cached-picture path, '
      'no strip activity', (tester) async {
    PdfPageView.retainedZoomReplayMaxCommands = 0;
    PdfPageView.stripZoomReplay = false;
    PdfPageView.debugStripZoomReplayBackendOverride = true;
    addTearDown(() {
      PdfPageView.retainedZoomReplayMaxCommands = 20000;
      PdfPageView.stripZoomReplay = true; // the default
      PdfPageView.debugStripZoomReplayBackendOverride = null;
    });
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildVectorPdf());
    final page = doc.page(0);
    Widget at(double scale) => Center(
        child:
            SizedBox(width: 612, child: PdfPageView(page: page, scale: scale)));

    StripPdfDevice.resetStats();
    await tester.pumpWidget(at(1));
    final base = await settleRaster(tester, 612);
    expect(base.width, 612);

    await tester.pumpWidget(at(3));
    final zoomed = await settleRaster(tester, 612 * 3);
    expect(zoomed.width, 612 * 3);
    expect(StripPdfDevice.totalFlushes, 0,
        reason: 'flag off must never touch the strip device');
  });

  testWidgets(
      'backend gate off: the flag is inert on non-Impeller backends',
      (tester) async {
    PdfPageView.retainedZoomReplayMaxCommands = 0;
    PdfPageView.stripZoomReplay = true;
    PdfPageView.debugStripZoomReplayBackendOverride = false; // "software"
    addTearDown(() {
      PdfPageView.retainedZoomReplayMaxCommands = 20000;
      PdfPageView.stripZoomReplay = true; // the default
      PdfPageView.debugStripZoomReplayBackendOverride = null;
    });
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildVectorPdf());
    final page = doc.page(0);
    Widget at(double scale) => Center(
        child:
            SizedBox(width: 612, child: PdfPageView(page: page, scale: scale)));

    StripPdfDevice.resetStats();
    await tester.pumpWidget(at(1));
    await settleRaster(tester, 612);
    await tester.pumpWidget(at(3));
    final zoomed = await settleRaster(tester, 612 * 3);
    expect(zoomed.width, 612 * 3);
    expect(StripPdfDevice.totalFlushes, 0,
        reason: 'the gate must keep strips off software backends');
  });
}
