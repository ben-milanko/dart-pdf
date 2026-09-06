// Before/after comparisons use this run's renderer, so lossless equality
// holds on every platform without depending on host-specific font baselines.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

const _samples = [
  'ghent/1-CMYK/GWG050_Font_Substitution_x3.pdf',
  'ghent/1-CMYK/GWG090_Font-Support_x3.pdf',
  'ghent/1-CMYK/GWG150_OptionalContent-OCCD_X4.pdf',
  'ghent/1-CMYK/GWG160_Transp_Basic_BM_DeviceCMYK_Non-knockout_X4.pdf',
  'ghent/1-CMYK/GWG170_JPEG2000_compression_DeviceCMYK_X4.pdf',
  'ghent/3-ICC-CMS/GWG180_16Bit_Images_ICCbasedRGB_x4.pdf',
  'pdfjs/complex_ttf_font.pdf',
  'pdfjs/arial_unicode_ab_cidfont.pdf',
  'pdfjs/pattern_text_embedded_font.pdf',
  'pdfjs/simpletype3font.pdf',
  'pdfjs/ccitt_EndOfBlock_false.pdf',
  'pdfjs/jbig2_symbol_offset.pdf',
  'pdfjs/cmykjpeg.pdf',
  'pdfjs/tiling_patterns_variations.pdf',
  'pdfjs/smask_alpha_bc.pdf',
  'pdfjs/smaskdim.pdf',
];

void main() {
  var beforeTotal = 0;
  var afterTotal = 0;
  for (final name in _samples) {
    testWidgets('lossless optimisation preserves $name', (tester) async {
      await tester.runAsync(() async {
        await loadSystemFonts();
        final bytes = File('../../test_corpora/$name').readAsBytesSync();
        final before = PdfDocument.open(bytes);
        final result = PdfCompressor.optimize(before);
        final after = PdfDocument.open(result.bytes);
        expect(result.bytesAfter, lessThanOrEqualTo(result.bytesBefore));
        expect(after.pageCount, before.pageCount);
        beforeTotal += result.bytesBefore;
        afterTotal += result.bytesAfter;
        for (var i = 0; i < before.pageCount; i++) {
          final original = await _raster(before.page(i));
          final optimized = await _raster(after.page(i));
          expect(optimized, original,
              reason: '$name page ${i + 1}: lossless means identical pixels');
        }
      });
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
  tearDownAll(() {
    // Kept in the test log as an observed sample result, not a size promise.
    // ignore: avoid_print
    print('Lossless corpus sample: $beforeTotal → $afterTotal bytes');
  });
}

Future<Uint8List> _raster(PdfPage page) async {
  final image = await PdfPageRenderer.renderImage(page);
  try {
    final data =
        (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
