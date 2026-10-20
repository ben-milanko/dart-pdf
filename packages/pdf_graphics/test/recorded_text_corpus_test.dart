import 'dart:io';
import 'dart:math' as math;

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

void main() {
  // A bounded sample of the checked-in corpora targets differences between a
  // recording device and extraction: embedded/substitute/vertical fonts,
  // recursive Type3 cells, optional content, OCR and text-bearing soft masks.
  const files = [
    'pdfjs/arial_unicode_ab_cidfont.pdf',
    'pdfjs/bug1011159.pdf',
    'pdfjs/bug898853.pdf',
    'pdfjs/bug946506.pdf',
    'pdfjs/cid_cff.pdf',
    'pdfjs/complex_ttf_font.pdf',
    'pdfjs/ContentStreamCycleType3insideType3.pdf',
    'pdfjs/ContentStreamNoCycleType3insideType3.pdf',
    'pdfjs/helloworld-bad.pdf',
    'pdfjs/issue4684.pdf',
    'pdfjs/operator-in-TJ-array.pdf',
    'pdfjs/vertical.pdf',
    'ghent/1-CMYK/GWG050_Font_Substitution_x3.pdf',
    'ghent/1-CMYK/GWG090_Font-Support_x3.pdf',
    'ghent/1-CMYK/GWG091_FontSupport-OpenType_X4.pdf',
    'ghent/1-CMYK/GWG150_OptionalContent-OCCD_X4.pdf',
    'ghent/1-CMYK/GWG161_Transp_Basic_BM_DeviceCMYK_Knockout_X4.pdf',
    'ghent/1-CMYK/GWG1610_Softmasks_Text_part1_X4.pdf',
    'ghent/1-CMYK/GWG1611_Softmasks_Text_part2_X4.pdf',
    'ghent/1-CMYK/GWG168_Softmasks_Vector_part1_X4.pdf',
  ];

  for (final name in files) {
    final file = File('../../test_corpora/$name');
    test('recorded text matches fresh extraction: $name', () {
      final document = PdfDocument.open(file.readAsBytesSync());
      final pages =
          name == 'pdfjs/vertical.pdf' ? math.min(3, document.pageCount) : 1;
      var textLength = 0;
      for (var page = 0; page < pages; page++) {
        final recorder = RecordingPdfDevice();
        PdfInterpreter(
          cos: document.cos,
          device: recorder,
          collectCharOffsets: true,
        ).drawPage(document.page(page));
        final snapshot = PdfRecordedText.capture(recorder.commands);
        recorder.commands.clear();
        final reused = PdfTextExtractor.fromRecordedText(snapshot, page);
        final fresh = PdfTextExtractor.extract(document, page);
        expect(serializePageText(reused), serializePageText(fresh),
            reason:
                'page $page: text, bidi, MCIDs and exact selection geometry');
        textLength += reused.text.length;
      }
      // Some vertical.pdf pages use currently unsupported CMaps and extract
      // no text. Compare that existing behavior too, while requiring actual
      // text in every document so no file's parity passes wholly vacuously.
      expect(textLength, greaterThan(0));
    }, skip: file.existsSync() ? false : 'checked-in corpus unavailable');
  }
}
