// Probe (not part of the suite): does compositing of two overlapping
// strip-routed fills inside ONE flush batch match the canvas result?
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:dart_pdf_editor/strips.dart';

void main() {
  testWidgets('pink diagonal over grey box: strips vs canvas', (tester) async {
    await tester.runAsync(() async {
      const w = 32, h = 32;
      final grey = PdfPath([
        PdfMoveTo(4, 4),
        PdfLineTo(28, 4),
        PdfLineTo(28, 28),
        PdfLineTo(4, 28),
        const PdfClosePath(),
      ]);
      // diagonal-edged pink shape overlapping the grey box
      final pink = PdfPath([
        PdfMoveTo(8, 8),
        PdfLineTo(24, 8),
        PdfLineTo(8, 24),
        const PdfClosePath(),
      ]);
      const greyC = PdfColor(134 / 255, 128 / 255, 128 / 255);
      const pinkC = PdfColor(1, 170 / 255, 200 / 255);

      Future<Uint8List> viaStrips({bool splitFlush = false}) async {
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 32, 32),
            ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        final d = StripPdfDevice(canvas,
            pageToDevice: PdfMatrix.identity,
            deviceWidth: w,
            deviceHeight: h,
            pixelRatio: 1);
        d.fillPath(grey, greyC, PdfFillRule.nonzero, 1);
        if (splitFlush) {
          // force a flush boundary between the two fills
          d.save();
          d.clipPath(
              PdfPath([
                PdfMoveTo(0, 0),
                PdfLineTo(32, 0),
                PdfLineTo(32, 32),
                PdfLineTo(0, 32),
                const PdfClosePath(),
              ]),
              PdfFillRule.nonzero);
          d.restore();
        }
        d.fillPath(pink, pinkC, PdfFillRule.nonzero, 1);
        await d.finish();
        final pic = rec.endRecording();
        final img = await pic.toImage(w, h);
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        pic.dispose();
        d.dispose();
        return data!.buffer.asUint8List();
      }

      Future<Uint8List> viaCanvas() async {
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 32, 32),
            ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        ui.Path toUi(PdfPath p) {
          final out = ui.Path();
          for (final s in p.segments) {
            switch (s) {
              case PdfMoveTo(:final x, :final y):
                out.moveTo(x, y);
              case PdfLineTo(:final x, :final y):
                out.lineTo(x, y);
              case PdfCubicTo():
                out.cubicTo(s.x1, s.y1, s.x2, s.y2, s.x3, s.y3);
              case PdfClosePath():
                out.close();
            }
          }
          return out;
        }

        canvas.drawPath(
            toUi(grey), ui.Paint()..color = const ui.Color(0xFF868080));
        canvas.drawPath(
            toUi(pink), ui.Paint()..color = const ui.Color(0xFFFFAAC8));
        final pic = rec.endRecording();
        final img = await pic.toImage(w, h);
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        pic.dispose();
        return data!.buffer.asUint8List();
      }

      final a = await viaCanvas();
      final b = await viaStrips();
      final c = await viaStrips(splitFlush: true);

      // sample along the pink diagonal edge (x+y = 32 crossing pixels):
      // sequential srcOver of two overlapping strip fills must composite
      // like the canvas, in one flush batch or across a flush boundary
      for (final (x, y) in const [(15, 16), (16, 15), (12, 19), (19, 12), (10, 21)]) {
        final o = (y * w + x) * 4;
        // ignore: avoid_print
        print('OVERLAP: ($x,$y) canvas=(${a[o]},${a[o + 1]},${a[o + 2]}) '
            'strips1flush=(${b[o]},${b[o + 1]},${b[o + 2]}) '
            'strips2flush=(${c[o]},${c[o + 1]},${c[o + 2]})');
        for (var ch = 0; ch < 3; ch++) {
          expect((b[o + ch] - a[o + ch]).abs(), lessThanOrEqualTo(2),
              reason: 'one-flush overlap at ($x,$y) channel $ch');
          expect((c[o + ch] - a[o + ch]).abs(), lessThanOrEqualTo(2),
              reason: 'split-flush overlap at ($x,$y) channel $ch');
        }
      }
    });
  });
}
