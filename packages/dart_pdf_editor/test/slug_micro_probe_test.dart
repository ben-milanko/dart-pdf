// Minimal synthetic glyphs (square/circle/triangle) through the real slug
// shader path, asserted against the Dart glyphCoverageAA reference.
// Impeller runs must set SLUG_IMPELLER=1 (record-resolution snapshot
// resampling widens the tolerance - see slug_test.dart).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:dart_pdf_editor/strips.dart';

Future<Uint8List> renderGlyph(PdfPath outline, PdfMatrix emToPage,
    int w, int h) async {
  StripPdfDevice.slugGlyphs = true;
  try {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    final device = StripPdfDevice(canvas,
        pageToDevice: PdfMatrix.identity,
        deviceWidth: w,
        deviceHeight: h,
        pixelRatio: 1);
    device.drawText(PdfTextRun(
      text: 'x',
      transform: emToPage,
      color: PdfColor.black,
      width: 1,
      glyphs: [PdfGlyphPlacement(offset: 0, outline: outline)],
    ));
    await device.finish();
    final pic = rec.endRecording();
    final img = await pic.toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    pic.dispose();
    device.dispose();
    return data!.buffer.asUint8List();
  } finally {
    StripPdfDevice.slugGlyphs = false;
  }
}

final bool _impeller = Platform.environment['SLUG_IMPELLER'] == '1';

Future<void> check(String name, PdfPath outline) async {
  const w = 32, h = 32;
  const m = PdfMatrix(24, 0, 0, -24, 4, 28);
  final got = await renderGlyph(outline, m, w, h);
  final quads = outlineToQuads(outline);
  final bands = buildBands(quads, bandCount: 8);
  final inv = m.inverted()!;
  var worst = 0;
  var sum = 0.0;
  var worstAt = '';
  for (var py = 0; py < h; py++) {
    for (var px = 0; px < w; px++) {
      final ex = inv.transformX(px + 0.5, py + 0.5);
      final ey = inv.transformY(px + 0.5, py + 0.5);
      final want = (255 * (1 - glyphCoverageAA(quads, bands, ex, ey, 24, 24)))
          .round();
      final d = (got[(py * w + px) * 4] - want).abs();
      sum += d;
      if (d > worst) {
        worst = d;
        worstAt = '($px,$py) got=${got[(py * w + px) * 4]} want=$want '
            'em=(${ex.toStringAsFixed(3)},${ey.toStringAsFixed(3)})';
      }
    }
  }
  // ignore: avoid_print
  print('MICRO $name: mean ${(sum / (w * h)).toStringAsFixed(2)} max $worst '
      '$worstAt');
  expect(sum / (w * h), lessThanOrEqualTo(_impeller ? 8.0 : 0.5),
      reason: '$name mean');
  expect(worst, lessThanOrEqualTo(_impeller ? 224 : 8), reason: '$name max');
}

void main() {
  testWidgets('square + circle + triangle micro glyphs', (tester) async {
    await tester.runAsync(() async {
      await check(
          'square',
          PdfPath([
            PdfMoveTo(0.1, 0.1),
            PdfLineTo(0.8, 0.1),
            PdfLineTo(0.8, 0.7),
            PdfLineTo(0.1, 0.7),
            const PdfClosePath(),
          ]));
      await check(
          'circle',
          PdfPath([
            PdfMoveTo(0.45, 0.8),
            PdfCubicTo(0.05, 0.8, 0.05, 0.1, 0.45, 0.1),
            PdfCubicTo(0.85, 0.1, 0.85, 0.8, 0.45, 0.8),
            const PdfClosePath(),
          ]));
      await check(
          'triangle',
          PdfPath([
            PdfMoveTo(0.1, 0.1),
            PdfLineTo(0.85, 0.15),
            PdfLineTo(0.4, 0.75),
            const PdfClosePath(),
          ]));
    });
  });
}
