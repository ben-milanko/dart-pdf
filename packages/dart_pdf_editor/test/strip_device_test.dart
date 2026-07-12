// Unit tests for StripPdfDevice: byte-level coverage checks on synthetic
// fills through the full shader path (strip generation -> atlas ->
// drawVertices+FragmentShader -> raster), plus flush/fallback ordering.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:dart_pdf_editor/strips.dart';

PdfPath rect(double l, double t, double r, double b) => PdfPath([
      PdfMoveTo(l, t),
      PdfLineTo(r, t),
      PdfLineTo(r, b),
      PdfLineTo(l, b),
      const PdfClosePath(),
    ]);

Future<Uint8List> renderStrips(
    void Function(StripPdfDevice d) draw, int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  // identity page->device: device space IS canvas space
  final device = StripPdfDevice(canvas,
      pageToDevice: PdfMatrix.identity,
      deviceWidth: w,
      deviceHeight: h,
      pixelRatio: 1,
      images: const {});
  draw(device);
  await device.finish();
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  device.dispose();
  return data!.buffer.asUint8List();
}

int px(Uint8List b, int w, int x, int y, int c) => b[(y * w + x) * 4 + c];

void main() {
  testWidgets('integer-aligned black rect is exact', (tester) async {
    await tester.runAsync(() async {
      final bytes = await renderStrips(
          (d) =>
              d.fillPath(rect(4, 4, 20, 12), PdfColor.black, PdfFillRule.nonzero, 1),
          24,
          16);
      expect(px(bytes, 24, 5, 5, 0), 0);
      expect(px(bytes, 24, 19, 11, 0), 0); // last interior pixel
      expect(px(bytes, 24, 3, 5, 0), 255); // left of rect
      expect(px(bytes, 24, 20, 5, 0), 255); // right of rect
      expect(px(bytes, 24, 5, 3, 0), 255); // above
      expect(px(bytes, 24, 5, 12, 0), 255); // below
    });
  });

  testWidgets('fractional edges get exact area coverage', (tester) async {
    await tester.runAsync(() async {
      // rect x in [4.25, 19.75], y in [5.5, 10.25]
      final bytes = await renderStrips(
          (d) => d.fillPath(rect(4.25, 5.5, 19.75, 10.25), PdfColor.black,
              PdfFillRule.nonzero, 1),
          24,
          16);
      int want(double cov) => (255 * (1 - cov)).round();
      // interior
      expect(px(bytes, 24, 10, 7, 0), 0);
      // left column x=4: covered 0.75 horizontally, fully vertically at y=7
      expect((px(bytes, 24, 4, 7, 0) - want(0.75)).abs(), lessThanOrEqualTo(2));
      // right column x=19: 0.75
      expect((px(bytes, 24, 19, 7, 0) - want(0.75)).abs(), lessThanOrEqualTo(2));
      // top row y=5: 0.5
      expect((px(bytes, 24, 10, 5, 0) - want(0.5)).abs(), lessThanOrEqualTo(2));
      // bottom row y=10: 0.25
      expect((px(bytes, 24, 10, 10, 0) - want(0.25)).abs(), lessThanOrEqualTo(2));
      // corner x=4,y=5: 0.75*0.5
      expect((px(bytes, 24, 4, 5, 0) - want(0.375)).abs(), lessThanOrEqualTo(2));
    });
  });

  testWidgets('diagonal edge coverage matches analytic area', (tester) async {
    await tester.runAsync(() async {
      // right triangle (4,4) (20,4) (4,20): hypotenuse x+y=24
      final path = PdfPath([
        PdfMoveTo(4, 4),
        PdfLineTo(20, 4),
        PdfLineTo(4, 20),
        const PdfClosePath(),
      ]);
      final bytes = await renderStrips(
          (d) => d.fillPath(path, PdfColor.black, PdfFillRule.nonzero, 1),
          24,
          24);
      // pixel (x,y) crossed by the diagonal: coverage = area of
      // {(u,v) in pixel: u+v <= 24}
      double cov(int x, int y) {
        var inside = 0;
        for (var sy = 0; sy < 64; sy++) {
          for (var sx = 0; sx < 64; sx++) {
            final u = x + (sx + 0.5) / 64, v = y + (sy + 0.5) / 64;
            if (u + v <= 24 && u >= 4 && v >= 4) inside++;
          }
        }
        return inside / 4096;
      }

      for (final (x, y) in const [(12, 11), (11, 12), (8, 15), (15, 8), (10, 13)]) {
        final wantV = (255 * (1 - cov(x, y))).round();
        expect((px(bytes, 24, x, y, 0) - wantV).abs(), lessThanOrEqualTo(3),
            reason: 'diagonal pixel $x,$y: got ${px(bytes, 24, x, y, 0)} '
                'want $wantV (cov ${cov(x, y)})');
      }
    });
  });

  testWidgets('translucent fill modulates like srcOver', (tester) async {
    await tester.runAsync(() async {
      final bytes = await renderStrips(
          (d) => d.fillPath(rect(4, 4, 20, 12), const PdfColor(1, 0, 0),
              PdfFillRule.nonzero, 0.5),
          24,
          16);
      // 50% red over white: (255, 127.5, 127.5)
      expect((px(bytes, 24, 10, 8, 0) - 255).abs(), lessThanOrEqualTo(2));
      expect((px(bytes, 24, 10, 8, 1) - 128).abs(), lessThanOrEqualTo(2));
      expect((px(bytes, 24, 10, 8, 2) - 128).abs(), lessThanOrEqualTo(2));
    });
  });

  testWidgets('painter order: strips flush under delegated paints and clips',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = await renderStrips((d) {
        // black rect via strips
        d.fillPath(rect(0, 0, 24, 16), PdfColor.black, PdfFillRule.nonzero, 1);
        // clip to the left half, then red rect via strips inside the clip
        d.save();
        d.clipPath(rect(0, 0, 12, 16), PdfFillRule.nonzero);
        d.fillPath(
            rect(0, 0, 24, 16), const PdfColor(1, 0, 0), PdfFillRule.nonzero, 1);
        d.restore();
        // green rect after restore, unclipped
        d.fillPath(
            rect(20, 0, 24, 16), const PdfColor(0, 1, 0), PdfFillRule.nonzero, 1);
      }, 24, 16);
      expect([px(bytes, 24, 6, 8, 0), px(bytes, 24, 6, 8, 1)], [255, 0],
          reason: 'red inside clip');
      expect([px(bytes, 24, 16, 8, 0), px(bytes, 24, 16, 8, 1)], [0, 0],
          reason: 'black outside clip (red clipped away)');
      expect([px(bytes, 24, 22, 8, 1)], [255], reason: 'green after restore');
    });
  });

  testWidgets('stats: one flush for a batch of plain fills', (tester) async {
    await tester.runAsync(() async {
      StripPdfDevice.resetStats();
      await renderStrips((d) {
        for (var i = 0; i < 10; i++) {
          d.fillPath(rect(i * 2.0, 0, i * 2.0 + 1.5, 8), PdfColor.black,
              PdfFillRule.nonzero, 1);
        }
      }, 24, 16);
      expect(StripPdfDevice.totalFlushes, 1);
      expect(StripPdfDevice.totalDelegatedPaints, 0);
    });
  });
}
