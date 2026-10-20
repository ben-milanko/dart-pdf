// #912: stroked text (rendering modes 1/2/5/6) has to obey the same
// one-device-pixel stroke floor as every other stroke.
//
// #426 established the floor for path strokes - Skia paints a sub-pixel stroke
// as a one-pixel line with its alpha scaled down by the width, so a 0.06 pt CAD
// hairline came out at 6% opacity - but neither text path in `CanvasPdfDevice`
// applied it:
//
//   * embedded glyph outlines went to `canvas.drawPath` with the raw
//     page-space width, so thin positive widths painted at that same few
//     percent alpha (the interpreter does not route stroke modes on embedded
//     fonts here yet - it fills the outline in the stroking colour - so this
//     half is exercised against the device directly, the way a replayed
//     command buffer reaches it);
//   * substituted runs rewrote a `0 w` width to *one painter unit*
//     (`ts / renderSize` page units, i.e. a hundredth of the em), which is
//     sub-pixel at every ordinary text size - so "0 w + Tr 1" read as blank
//     paper instead of solid linework. pdf.js's own `zerowidthline.pdf`
//     ("Stroked text with zero line width.") renders solid black there and was
//     a ghost here.
//
// The measurements are coverage sums and peaks, not pixel hits: a row across
// one glyph stem, summing 0-1 of ink per pixel, totals the stroke's device
// width whatever the antialiasing does with it.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// 333% - the same "does the hairline stay one pixel?" scale as the #660 and
/// #426 stroke-width tests.
const zoom = 10 / 3;

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

Uint8List _stream(String dict, String content) =>
    ascii('<< $dict /Length ${content.length} >>\nstream\n$content\nendstream');

/// One em-square glyph outline stroked at [width] in text rendering mode 1,
/// drawn straight into a page-space picture the way a replayed render-command
/// buffer reaches the device.
///
/// The em square maps to a 24 pt square at x=100, y=700..724, so its left stem
/// is a vertical line with no curvature or hinting to argue about.
ui.Picture _strokedGlyphPicture(double width) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(0, pageHeight)
    ..scale(1, -1);
  CanvasPdfDevice(canvas).drawText(PdfTextRun(
    text: 'B',
    transform: const PdfMatrix(24, 0, 0, 24, 100, 700),
    color: PdfColor.black,
    width: 1,
    fill: false,
    strokeColor: PdfColor.black,
    strokeWidth: width,
    glyphs: const [
      PdfGlyphPlacement(
        offset: 0,
        outline: PdfPath([
          PdfMoveTo(0, 0),
          PdfLineTo(1, 0),
          PdfLineTo(1, 1),
          PdfLineTo(0, 1),
          PdfClosePath(),
        ]),
      ),
    ],
  ));
  return recorder.endRecording();
}

/// The same page for an *unembedded* standard-14 face, which the device draws
/// with a substituted system font through a `TextPainter` instead of glyph
/// outlines - the other half of the defect.
Uint8List _substitutedStrokedTextPdf(double width) {
  final content = 'BT /F1 40 Tf 1 Tr $width w 0 0 0 RG 100 700 Td (HHHH) Tj ET';
  return _assemble([
    ascii('<< /Type /Catalog /Pages 2 0 R >>'),
    ascii('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    ascii('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>'),
    _stream('', content),
    ascii('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'),
  ]);
}

Future<ui.Image> _rasterizeRegion(
    Uint8List bytes, Rect region, double scale) async {
  final picture =
      await PdfPageRenderer.renderPicture(PdfDocument.open(bytes).page(0));
  final image = await PdfPageRenderer.rasterizeRegion(picture, region, scale);
  picture.dispose();
  return image;
}

/// Coverage (0-1 per pixel, read as alpha over the transparent picture)
/// summed across the middle row of the rasterized glyph stem: its device-space
/// thickness, whatever the antialiasing spreads it over.
Future<double> _stemThickness(double width, double scale) async {
  final picture = _strokedGlyphPicture(width);
  // 8 pt wide around the stem at x=100, 4 pt tall about the middle of the
  // 24 pt square, so neither the square's right stem nor its corners intrude.
  final image = await PdfPageRenderer.rasterizeRegion(
    picture,
    Rect.fromCenter(
        center: const Offset(100, pageHeight - 712), width: 8, height: 4),
    scale,
  );
  picture.dispose();
  final data = (await image.toByteData())!;
  final row = image.height ~/ 2;
  var total = 0.0;
  for (var column = 0; column < image.width; column++) {
    total += data.getUint8((((row * image.width) + column) * 4) + 3) / 255;
  }
  image.dispose();
  return total;
}

/// (darkest pixel, total ink) over the whole run - what a reader sees as
/// "solid" versus "washed out", without depending on where a substituted face
/// puts its stems.
Future<(double, double)> _runInk(Uint8List bytes, double scale) async {
  final image = await _rasterizeRegion(
    bytes,
    const Rect.fromLTRB(96, pageHeight - 734, 260, pageHeight - 696),
    scale,
  );
  final data = (await image.toByteData())!;
  var peak = 0.0;
  var total = 0.0;
  for (var i = 0; i < image.width * image.height; i++) {
    final ink = (255 - data.getUint8(i * 4)) / 255;
    total += ink;
    if (ink > peak) peak = ink;
  }
  image.dispose();
  return (peak, total);
}

void main() {
  group('embedded glyph outlines', () {
    test('a sub-pixel stroke width paints a solid device pixel (#912)',
        () async {
      // Unfloored, 0.06 pt covers 0.06 px (6% alpha) at 1:1 and 0.2 px at
      // 333% - the washed-out reading of the page this fixes.
      expect(await _stemThickness(0.06, 1), closeTo(1, 0.35));
      expect(await _stemThickness(0.06, zoom), closeTo(1, 0.35));
    });

    test('an exact `0 w` stroke stays one device pixel at every scale',
        () async {
      expect(await _stemThickness(0, 1), closeTo(1, 0.35));
      expect(await _stemThickness(0, zoom), closeTo(1, 0.35),
          reason: '`0 w` is 8.4.3.2 thinnest-line, not a page-space width');
    });

    test('a width above the floor keeps its page-space measure', () async {
      expect(await _stemThickness(2, 1), closeTo(2, 0.35));
      expect(await _stemThickness(2, zoom), closeTo(2 * zoom, 0.7),
          reason: 'the floor must not flatten real linework to a hairline');
    });
  });

  group('substituted text', () {
    test('a `0 w` stroked run paints solid, not a few percent alpha (#912)',
        () async {
      final (peak, total) = await _runInk(_substitutedStrokedTextPdf(0), 1);

      // It used to be rewritten to one painter unit - 0.4 pt at 40 pt text,
      // so 40% alpha at best and, at the 12 pt body sizes a real document
      // uses, a few percent.
      expect(peak, greaterThan(0.9), reason: 'the outline must be solid ink');
      expect(total, greaterThan(20), reason: 'the run must be visible at all');
    });

    test('a sub-pixel stroke width paints solid too', () async {
      final (peak, _) = await _runInk(_substitutedStrokedTextPdf(0.06), 1);

      expect(peak, greaterThan(0.9));
    });

    test('a width above the floor still draws thicker than a hairline',
        () async {
      final (_, hairline) = await _runInk(_substitutedStrokedTextPdf(0), 1);
      final (peak, thick) = await _runInk(_substitutedStrokedTextPdf(4), 1);

      expect(peak, greaterThan(0.9));
      expect(thick, greaterThan(hairline * 2),
          reason: '4 pt outlines must not be floored to one pixel');
    });
  });
}
