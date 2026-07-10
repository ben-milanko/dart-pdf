// Calibration probe (not part of the suite): how far does Skia's path AA
// deviate from exact-area coverage on a diagonal edge, and how far does the
// strip pipeline? Bounds the achievable strip-vs-canvas parity.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:dart_pdf_editor/strips.dart';

void main() {
  testWidgets('skia vs analytic vs strips on a diagonal edge', (tester) async {
    await tester.runAsync(() async {
      const w = 24, h = 24;
      // right triangle (4,4) (20,4) (4,20)
      final tri = PdfPath([
        PdfMoveTo(4, 4),
        PdfLineTo(20, 4),
        PdfLineTo(4, 20),
        const PdfClosePath(),
      ]);

      Future<Uint8List> raster(void Function(ui.Canvas) draw) async {
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 24, 24),
            ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        draw(canvas);
        final pic = rec.endRecording();
        final img = await pic.toImage(w, h);
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        pic.dispose();
        return data!.buffer.asUint8List();
      }

      final skia = await raster((canvas) {
        final path = ui.Path()
          ..moveTo(4, 4)
          ..lineTo(20, 4)
          ..lineTo(4, 20)
          ..close();
        canvas.drawPath(path, ui.Paint()..color = const ui.Color(0xFF000000));
      });

      final stripsBytes = await (() async {
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 24, 24),
            ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        final device = StripPdfDevice(canvas,
            pageToDevice: PdfMatrix.identity,
            deviceWidth: w,
            deviceHeight: h,
            pixelRatio: 1);
        device.fillPath(tri, PdfColor.black, PdfFillRule.nonzero, 1);
        await device.finish();
        final pic = rec.endRecording();
        final img = await pic.toImage(w, h);
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        pic.dispose();
        device.dispose();
        return data!.buffer.asUint8List();
      })();

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

      // walk the diagonal; print (analytic, skia, strips) coverage
      for (var y = 6; y <= 17; y += 1) {
        final x = 24 - y - 1; // pixel crossed by u+v=24
        final want = (255 * (1 - cov(x, y))).round();
        final s = skia[(y * w + x) * 4];
        final st = stripsBytes[(y * w + x) * 4];
        // ignore: avoid_print
        print('CAL: ($x,$y) analytic=$want skia=$s strips=$st '
            'dSkia=${s - want} dStrips=${st - want}');
        expect((st - want).abs(), lessThanOrEqualTo(2),
            reason: 'strip coverage vs analytic at ($x,$y)');
      }
    });
  });
}
