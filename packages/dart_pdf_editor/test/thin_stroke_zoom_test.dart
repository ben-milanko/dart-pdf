// A stroke thinner than one device pixel is floored at a solid pixel, but
// only *while* it is thinner than a pixel: one recorded page picture is
// replayed at every zoom, and a 0.72 pt line must still grow to ~3 px at 4x.
//
// It used to be recorded as Skia's zero-width hairline, which stays one pixel
// at every replay scale - so on CAD drawings the parallel 0.72 pt conduit runs
// that read as a solid red band zoomed out fell apart into faint threads
// zoomed in (LIL-L4209).
//
// The measurements are coverage peaks and sums down one pixel column across
// a horizontal line: the sum is its device thickness however antialiasing
// spreads it, and the peak is whether it reads as ink.
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
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
          '/Contents 4 0 R /Resources << /ExtGState << /GS1 << /CA 0.5 >> '
          '>> >> >>'),
      ascii('<< /Length ${content.length} >>\nstream\n$content\nendstream'),
    ]);

/// Black ink (0-1, against the white paper) down the pixel column at page
/// x=200, over page y in [yBottom]..[yTop], with the page recorded once and
/// replayed at each of [scales]: (peak, sum) per scale.
Future<List<(double, double)>> _columnInk(
    String content, double yBottom, double yTop, List<double> scales) async {
  final picture = await PdfPageRenderer.renderPicture(
      PdfDocument.open(_page(content)).page(0));
  final results = <(double, double)>[];
  for (final scale in scales) {
    final image = await PdfPageRenderer.rasterizeRegion(
        picture,
        Rect.fromLTRB(198, pageHeight - yTop, 202, pageHeight - yBottom),
        scale);
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
    results.add((peak, total));
  }
  picture.dispose();
  return results;
}

void main() {
  test('a sub-point stroke grows with the zoom from one recorded picture',
      () async {
    final [(_, at1), (_, at4)] =
        await _columnInk('0 G 0.72 w 100 400 m 300 400 l S', 396, 404, [1, 4]);
    expect(at4, closeTo(2.88, 0.4), reason: '0.72 pt at 4 px/pt is ~2.9 px');
    // floored at one device pixel; centred on a row boundary, the stroke and
    // its hairline each straddle two rows and composite to a little more
    expect(at1, inInclusiveRange(0.85, 1.5),
        reason: 'floored at one device pixel');
  });

  test('zoomed out the stroke is still a solid device pixel', () async {
    for (final y in [400.0, 400.4, 400.8]) {
      final [(peak, total)] =
          await _columnInk('0 G 0.72 w 100 $y m 300 $y l S', 390, 410, [1 / 3]);
      expect(peak, greaterThan(0.5),
          reason: 'at 1/3 px/pt the line must read as ink, not haze');
      expect(total, closeTo(1, 0.35));
    }
  });

  test('a zero-width stroke stays one device pixel at every zoom', () async {
    final results =
        await _columnInk('0 G 0 w 100 400 m 300 400 l S', 396, 404, [1, 4]);
    for (final (peak, total) in results) {
      expect(peak, greaterThan(0.5));
      expect(total, closeTo(1, 0.35));
    }
  });

  test('parallel sub-point strokes fuse into a band zoomed in', () async {
    // 7 x 0.72 pt runs 0.6 pt apart: the conduit bundles on LIL-L4209
    final runs = [
      for (var i = 0; i < 7; i++)
        '100 ${400 + i * 0.6} m 300 ${400 + i * 0.6} l',
    ].join(' ');
    final [(_, total)] = await _columnInk('0 G 0.72 w $runs S', 396, 408, [4]);
    // 6 * 0.6 + 0.72 = 4.32 pt of solid band, 17.3 px at 4x
    expect(total, closeTo(17.3, 1));
  });

  test('a dashed sub-point stroke grows too', () async {
    // a dash long enough to cover the measured column on its own
    final [(_, total)] = await _columnInk(
        '0 G 0.72 w [400 10] 0 d 100 400 m 300 400 l S', 396, 404, [4]);
    expect(total, closeTo(2.88, 0.4));
  });

  test('a translucent thin stroke keeps the plain hairline', () async {
    // an overlay would double the alpha wherever the stroke covers, so this
    // stays the one-pixel line it always was: 0.5 alpha over one pixel
    final [(_, total)] = await _columnInk(
        '/GS1 gs 0 G 0.72 w 100 400 m 300 400 l S', 396, 404, [4]);
    expect(total, closeTo(0.5, 0.2));
  });
}
