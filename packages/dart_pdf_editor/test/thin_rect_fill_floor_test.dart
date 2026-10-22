// Thin filled rectangles - rules and table borders drawn as `re f`, which is
// how Word exports table borders (0.5 pt fills) - get the same
// one-device-pixel floor as a stroke.
//
// Unfloored, Skia paints a 0.5 pt fill at 0.6 px/pt as 0.3 px of coverage,
// split over two pixel rows wherever it lands between them, so zoomed out
// whole box edges faded to nothing while the strokes next to them held.
//
// The measurements are coverage peaks and sums down one pixel column across
// the rule: the sum is its device thickness whatever the antialiasing spreads
// it over, and the peak is whether it reads as ink. A one-pixel line straddling
// two pixel rows peaks around 0.6; unfloored, this rule peaked at 0.10-0.30.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

const pageHeight = 792.0;

/// Assembles [bodies] (1-indexed, in order) into a one-page PDF with a correct
/// xref table - offsets are computed, never hand-written.
Uint8List _assemble(List<Uint8List> bodies) {
  final out = BytesBuilder()..add(ascii('%PDF-1.7\n'));
  final offsets = <int>[];
  for (var i = 0; i < bodies.length; i++) {
    offsets.add(out.length);
    out
      ..add(ascii('${i + 1} 0 obj\n'))
      ..add(bodies[i])
      ..add(ascii('\nendobj\n'));
  }
  final xrefOffset = out.length;
  final trailer = StringBuffer()
    ..write('xref\n0 ${bodies.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    trailer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  trailer
    ..write('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  out.add(ascii(trailer.toString()));
  return out.takeBytes();
}

Uint8List _page(String content) => _assemble([
      ascii('<< /Type /Catalog /Pages 2 0 R >>'),
      ascii('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      ascii('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Contents 4 0 R >>'),
      ascii('<< /Length ${content.length} >>\nstream\n$content\nendstream'),
    ]);

/// Black ink (0-1, against the white paper) down the pixel column at page
/// x=[x], over page y in [yBottom]..[yTop]: (peak, sum).
Future<(double, double)> _columnInk(
    String content, double x, double yBottom, double yTop, double scale) async {
  final picture = await PdfPageRenderer.renderPicture(
      PdfDocument.open(_page(content)).page(0));
  final image = await PdfPageRenderer.rasterizeRegion(
    picture,
    Rect.fromLTRB(x - 2, pageHeight - yTop, x + 2, pageHeight - yBottom),
    scale,
  );
  picture.dispose();
  final data = (await image.toByteData())!;
  final column = image.width ~/ 2;
  var peak = 0.0, total = 0.0;
  for (var row = 0; row < image.height; row++) {
    final ink =
        (255 - data.getUint8((row * image.width + column) * 4 + 1)) / 255;
    total += ink;
    if (ink > peak) peak = ink;
  }
  image.dispose();
  return (peak, total);
}

void main() {
  // A horizontal 0.5 pt rule from x=100 to 300 at y=400..400.5.
  const rule = '0 g 100 400 200 0.5 re f';

  test('a sub-pixel rule fill paints a solid device pixel zoomed out',
      () async {
    for (final scale in [0.6, 1 / 3]) {
      // wherever the rule lands against the pixel grid
      for (final y in [400.0, 400.4, 400.8]) {
        final (peak, total) =
            await _columnInk('0 g 100 $y 200 0.5 re f', 200, 390, 410, scale);
        expect(peak, greaterThan(0.5),
            reason: 'at $scale px/pt the rule must read as ink, not haze');
        expect(total, closeTo(1, 0.35));
      }
    }
  });

  test('a vertical rule is floored too', () async {
    // the column runs down the 0.5 pt wide rule, so every row is the rule
    final (_, total) =
        await _columnInk('0 g 200.25 300 0.5 200 re f', 200.5, 380, 420, 0.6);
    // 40 pt tall at 0.6 px/pt is 24 rows; floored, each row's column holds
    // well over the 0.3 of ink the bare fill leaves
    expect(total / 24, greaterThan(0.5));
  });

  test('several thin rectangles in one fill are each floored', () async {
    const borders = '0 g 100 400 200 0.5 re 100 500 200 0.5 re f';
    final (low, _) = await _columnInk(borders, 200, 390, 410, 0.6);
    final (high, _) = await _columnInk(borders, 200, 490, 510, 0.6);
    expect(low, greaterThan(0.5));
    expect(high, greaterThan(0.5));
  });

  test('zoomed in the rule keeps its page-space thickness', () async {
    final (_, total) = await _columnInk(rule, 200, 396, 404, 4);
    expect(total, closeTo(2, 0.4), reason: '0.5 pt at 4 px/pt is 2 px');
  });

  test('a thick fill is left exact', () async {
    // 3 pt tall at 0.2 px/pt is 0.6 px of coverage, and must stay that
    final (_, total) =
        await _columnInk('0 g 100 400 200 3 re f', 200, 380, 420, 0.2);
    expect(total, closeTo(0.6, 0.15));
  });

  test('a thin hole in a thick even-odd frame is not painted over', () async {
    // a 20 pt box with a 0.5 pt slot through it: the slot is a hole
    final (_, total) = await _columnInk(
        '0 g 100 390 200 20 re 100 400 200 0.5 re f*', 200, 385, 415, 1);
    expect(total, closeTo(19.5, 0.6));
  });

  test('a translucent thin fill is left exact', () async {
    // a hairline over it would double the alpha wherever the fill covers;
    // 0.5 alpha over 0.5 pt at 4 px/pt sums to 1 px of ink, not more
    const translucent = '/GS1 gs 0 g 100 400 200 0.5 re f';
    final bytes = _assemble([
      ascii('<< /Type /Catalog /Pages 2 0 R >>'),
      ascii('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      ascii('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Contents 4 0 R /Resources << /ExtGState << /GS1 << /ca 0.5 >> '
          '>> >> >>'),
      ascii('<< /Length ${translucent.length} >>\nstream\n$translucent\n'
          'endstream'),
    ]);
    final picture =
        await PdfPageRenderer.renderPicture(PdfDocument.open(bytes).page(0));
    final image = await PdfPageRenderer.rasterizeRegion(picture,
        const Rect.fromLTRB(198, pageHeight - 404, 202, pageHeight - 396), 4);
    picture.dispose();
    final data = (await image.toByteData())!;
    final column = image.width ~/ 2;
    var total = 0.0;
    for (var row = 0; row < image.height; row++) {
      total +=
          (255 - data.getUint8((row * image.width + column) * 4 + 1)) / 255;
    }
    image.dispose();
    expect(total, closeTo(1, 0.25));
  });

  testWidgets('the strip rasterizer floors a thin fill the same way',
      (tester) async {
    await tester.runAsync(() async {
      const size = 32;
      PdfPath rect(double l, double b, double r, double t) => PdfPath([
            PdfMoveTo(l, b),
            PdfLineTo(r, b),
            PdfLineTo(r, t),
            PdfLineTo(l, t),
            const PdfClosePath(),
          ]);
      final recorder = ui.PictureRecorder();
      final device = StripPdfDevice(ui.Canvas(recorder),
          pageToDevice: const PdfMatrix(0.5, 0, 0, 0.5, 0, 0),
          deviceWidth: size,
          deviceHeight: size,
          pixelRatio: 0.5);
      // left: a true one-pixel rule (2 units at 0.5 px/unit), the reference;
      // right: 0.5 units, a quarter pixel of coverage unfloored
      device
        ..fillPath(
            rect(4, 30.2, 28, 32.2), PdfColor.black, PdfFillRule.nonzero, 1)
        ..fillPath(
            rect(36, 30.2, 60, 30.7), PdfColor.black, PdfFillRule.nonzero, 1);
      await device.finish();
      final picture = recorder.endRecording();
      final image = await picture.toImage(size, size);
      final data = (await image.toByteData())!;
      double column(int x) {
        var total = 0.0;
        for (var row = 0; row < size; row++) {
          total += data.getUint8((row * size + x) * 4 + 3) / 255;
        }
        return total;
      }

      final reference = column(8), thin = column(24);
      image.dispose();
      picture.dispose();
      device.dispose();
      expect(thin, closeTo(reference, reference * 0.15));
    });
  });
}
