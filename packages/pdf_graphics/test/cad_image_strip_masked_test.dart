// The opt-in faithful tile shape of the image-heavy CAD fixture
// (PdfTileSpec.masked, gen_cad_image_pdf.dart faithful2): what the profiled
// sheet really draws, which the perf scenarios depend on it to be.
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/cad_image_strip.dart';
import 'package:test/test.dart';

void main() {
  const w = 512, h = 400;
  final tiles = [
    const PdfTileSpec(
        codec: PdfTileCodec.imageMask, width: w, height: h, masked: true),
    const PdfTileSpec(
        codec: PdfTileCodec.flateRgb, width: w, height: h, masked: true),
    const PdfTileSpec(
        codec: PdfTileCodec.imageMask,
        width: w,
        height: h,
        masked: true,
        maskBlank: true),
    const PdfTileSpec(
        codec: PdfTileCodec.flateRgb,
        width: w,
        height: h,
        masked: true,
        maskBlank: true),
    const PdfTileSpec(
        codec: PdfTileCodec.indexed,
        width: w,
        height: h,
        masked: true,
        maskBlank: true),
    const PdfTileSpec(codec: PdfTileCodec.indexed, width: 3, height: 1),
    const PdfTileSpec(codec: PdfTileCodec.imageMask, width: w, height: h),
  ];
  final doc = PdfDocument.open(
      buildSyntheticCadImageStrip(tiles: tiles, ops: 50, tileWidthPt: 983));
  final cos = doc.cos;
  final recorder = RecordingPdfDevice();
  PdfInterpreter(cos: cos, device: recorder).drawPage(doc.page(0));
  final drawn = recorder.imageRequests.map((r) => r.stream).toList();

  bool inverted(CosStream s) {
    final decode = cos.resolve(s.dictionary['Decode']);
    return decode is CosArray && cos.resolve(decode[0]) == const CosInteger(1);
  }

  /// (painting pixels, bytes holding a painting bit) of a 1-bit plane.
  (double, double) ink(CosStream s) {
    final bits = cos.decodeStreamData(s);
    final flip = inverted(s) ? 0 : 0xff;
    var paint = 0, busy = 0;
    for (final byte in bits) {
      var v = byte ^ flip;
      if (v != 0) busy++;
      for (; v != 0; v >>= 1) {
        paint += v & 1;
      }
    }
    return (paint / (w * h), busy / bits.length);
  }

  test('draws every tile, masks paired as separate streams', () {
    expect(drawn, hasLength(tiles.length));
    for (final (i, s) in drawn.indexed) {
      final mask = cos.resolve(s.dictionary['Mask']);
      final colour = tiles[i].codec != PdfTileCodec.imageMask;
      expect(mask is CosStream, colour && tiles[i].masked, reason: 'tile $i');
    }
  });

  test('stencils are sparse linework under /Decode [1 0]', () {
    for (final (i, s) in drawn.indexed) {
      if (!tiles[i].masked) continue;
      final plane = tiles[i].codec == PdfTileCodec.imageMask
          ? s
          : cos.resolve(s.dictionary['Mask']) as CosStream;
      final d = plane.dictionary;
      expect(cos.resolve(d['ImageMask']), const CosBoolean(true));
      expect(cos.resolve(d['Width']), const CosInteger(w));
      expect(cos.resolve(d['Height']), const CosInteger(h));
      expect(inverted(plane), isTrue, reason: 'tile $i');
      final (paint, busy) = ink(plane);
      if (tiles[i].maskBlank) {
        expect(paint, 0, reason: 'tile $i');
      } else {
        // The profiled sheet: ~1% of pixels, ~1.3% of bytes.
        expect(paint, inInclusiveRange(0.003, 0.03), reason: 'tile $i');
        expect(busy, inInclusiveRange(0.003, 0.05), reason: 'tile $i');
      }
    }
  });

  test('the default hatch keeps its #419 shape', () {
    final hatch = drawn.last;
    expect(inverted(hatch), isFalse);
    expect(ink(hatch).$1, greaterThan(0.9)); // the negative of a drawing
  });

  test('masked colour tiles decode through their stencil', () {
    // A blank mask hides the whole tile; the sparse one shows ~1% of it.
    final sparse = decodePdfImagePixels(cos, drawn[1])!;
    final blank = decodePdfImagePixels(cos, drawn[3])!;
    var shown = 0;
    for (var i = 3; i < sparse.rgba.length; i += 4) {
      if (sparse.rgba[i] != 0) shown++;
      expect(blank.rgba[i], 0);
    }
    expect(shown / (w * h), inInclusiveRange(0.003, 0.03));
  });
}
