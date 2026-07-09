// Probe: cubic-curve fill parity, strips vs Skia drawPath, at glyph-like
// sizes - direct fillPath and the em-space cached fillOutline path.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:dart_pdf_editor/strips.dart';

void main() {
  testWidgets('cubic blob: skia vs strips (direct + em-cached)',
      (tester) async {
    await tester.runAsync(() async {
      const w = 32, h = 32;
      // glyph-ish bowl in em units (0..1), drawn at a 24-px em
      final em = PdfPath([
        PdfMoveTo(0.1, 0.1),
        PdfCubicTo(0.1, 0.9, 0.5, 1.0, 0.9, 0.55),
        PdfCubicTo(0.8, 0.2, 0.4, 0.05, 0.1, 0.1),
        const PdfClosePath(),
      ]);
      // translation on the glyph cache's 1/4-px quantization grid so the
      // em-cached path (which quantizes subpixel offsets) rasters at
      // exactly this transform
      const emToDev = PdfMatrix(24, 0, 0, 24, 4.25, 3.75);

      Future<Uint8List> raster(void Function(ui.Canvas) draw) async {
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 32, 32),
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
        final path = ui.Path()..moveTo(0.1, 0.1);
        path.cubicTo(0.1, 0.9, 0.5, 1.0, 0.9, 0.55);
        path.cubicTo(0.8, 0.2, 0.4, 0.05, 0.1, 0.1);
        path.close();
        canvas.save();
        canvas.translate(4.25, 3.75);
        canvas.scale(24, 24);
        canvas.drawPath(path, ui.Paint()..color = const ui.Color(0xFF000000));
        canvas.restore();
      });

      Future<Uint8List> viaDevice(void Function(StripPdfDevice) draw) async {
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 32, 32),
            ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        final d = StripPdfDevice(canvas,
            pageToDevice: PdfMatrix.identity,
            deviceWidth: w,
            deviceHeight: h,
            pixelRatio: 1);
        draw(d);
        await d.finish();
        final pic = rec.endRecording();
        final img = await pic.toImage(w, h);
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        pic.dispose();
        d.dispose();
        return data!.buffer.asUint8List();
      }

      // direct fillPath: flattened in device space at 0.25 px (device path
      // takes page-space geometry; pageToDevice is identity here, so map
      // the em outline through emToDev by hand)
      PdfPathSegment tx(PdfPathSegment s) => switch (s) {
            PdfMoveTo(:final x, :final y) => PdfMoveTo(
                emToDev.transformX(x, y), emToDev.transformY(x, y)),
            PdfLineTo(:final x, :final y) => PdfLineTo(
                emToDev.transformX(x, y), emToDev.transformY(x, y)),
            PdfCubicTo() => PdfCubicTo(
                emToDev.transformX(s.x1, s.y1),
                emToDev.transformY(s.x1, s.y1),
                emToDev.transformX(s.x2, s.y2),
                emToDev.transformY(s.x2, s.y2),
                emToDev.transformX(s.x3, s.y3),
                emToDev.transformY(s.x3, s.y3)),
            PdfClosePath() => s,
          };
      final devPath = PdfPath([for (final s in em.segments) tx(s)]);
      final direct = await viaDevice((d) =>
          d.fillPath(devPath, PdfColor.black, PdfFillRule.nonzero, 1));
      // em-cached glyph path
      final gen = StripGenerator()..begin(w, h);
      final cachedBytes = await (() async {
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 32, 32),
            ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        final d = StripPdfDevice(canvas,
            pageToDevice: PdfMatrix.identity,
            deviceWidth: w,
            deviceHeight: h,
            pixelRatio: 1);
        d.drawText(PdfTextRun(
          text: 'x',
          transform: emToDev,
          color: PdfColor.black,
          width: 1,
          glyphs: [PdfGlyphPlacement(offset: 0, outline: em)],
        ));
        await d.finish();
        final pic = rec.endRecording();
        final img = await pic.toImage(w, h);
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        pic.dispose();
        d.dispose();
        return data!.buffer.asUint8List();
      })();
      gen.begin(1, 1); // silence unused warning path

      var maxDirect = 0, maxCached = 0;
      int worstX = 0, worstY = 0;
      for (var i = 0; i < w * h; i++) {
        final dd = (skia[i * 4] - direct[i * 4]).abs();
        final dc = (skia[i * 4] - cachedBytes[i * 4]).abs();
        if (dd > maxDirect) maxDirect = dd;
        if (dc > maxCached) {
          maxCached = dc;
          worstX = i % w;
          worstY = i ~/ w;
        }
      }
      // ignore: avoid_print
      print('CURVE: max|skia-direct|=$maxDirect max|skia-emcached|=$maxCached '
          'worst cached at ($worstX,$worstY): skia=${skia[(worstY * w + worstX) * 4]} '
          'cached=${cachedBytes[(worstY * w + worstX) * 4]}');

      // analytic ground truth at the worst pixel: dense flatten + winding
      final fine = flattenPath(devPath, PdfMatrix.identity, tolerance: 1e-4);
      final ring = fine[0].points;
      double coverage(int px, int py) {
        var inside = 0;
        const ss = 64;
        for (var sy = 0; sy < ss; sy++) {
          for (var sx = 0; sx < ss; sx++) {
            final x = px + (sx + 0.5) / ss, y = py + (sy + 0.5) / ss;
            var wind = 0;
            final n = ring.length ~/ 2;
            for (var i = 0, j = n - 1; i < n; j = i++) {
              final y0 = ring[2 * j + 1], y1 = ring[2 * i + 1];
              if ((y0 > y) == (y1 > y)) continue;
              final x0 = ring[2 * j], x1 = ring[2 * i];
              final xc = x0 + (y - y0) * (x1 - x0) / (y1 - y0);
              if (xc > x) wind += y1 > y0 ? 1 : -1;
            }
            if (wind != 0) inside++;
          }
        }
        return inside / (ss * ss);
      }

      for (final (px, py) in [(worstX, worstY), (13, 6), (10, 25)]) {
        final want = (255 * (1 - coverage(px, py))).round();
        // ignore: avoid_print
        print('CURVE-GT: ($px,$py) analytic=$want '
            'skia=${skia[(py * w + px) * 4]} direct=${direct[(py * w + px) * 4]} '
            'cached=${cachedBytes[(py * w + px) * 4]}');
        // The strip raster must track the true curve area; Skia's own
        // deviation here (~58 counts at the worst pixel when measured) is
        // exactly why the parity gate classifies curve edges - do NOT
        // assert on Skia.
        expect((direct[(py * w + px) * 4] - want).abs(), lessThanOrEqualTo(4),
            reason: 'direct strip coverage vs analytic at ($px,$py)');
        expect((cachedBytes[(py * w + px) * 4] - want).abs(),
            lessThanOrEqualTo(4),
            reason: 'em-cached strip coverage vs analytic at ($px,$py)');
      }
    });
  });
}
