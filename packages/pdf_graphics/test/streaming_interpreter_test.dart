import 'dart:io';
import 'dart:math' as math;

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

void main() {
  const fixtures = [
    'operator-in-TJ-array.pdf',
    'rotation.pdf',
    'xobject-image.pdf',
    'gradientfill.pdf',
    'tiling-pattern-box.pdf',
    'pattern_text_embedded_font.pdf',
    'blendmode.pdf',
    'knockout_smask.pdf',
  ];

  test('streaming and materialized interpretation are byte-equivalent', () {
    for (final name in fixtures) {
      final document = PdfDocument.open(
        File('../../test_corpora/pdfjs/$name').readAsBytesSync(),
      );
      for (var pageIndex = 0;
          pageIndex < math.min(2, document.pageCount);
          pageIndex++) {
        final page = document.page(pageIndex);
        final content = page.contentBytes();

        final materialized = RecordingPdfDevice();
        PdfInterpreter(cos: document.cos, device: materialized)
            .drawPageOperations(page, ContentStreamParser.parse(content));
        final streamed = RecordingPdfDevice();
        PdfInterpreter(cos: document.cos, device: streamed)
            .drawPageContent(page, content);

        final materializedBytes = serializeCommands(
          materialized.commands,
          cos: document.cos,
          decodeImages: false,
          imagePlaceholders: true,
          compactStateScopes: true,
        );
        final streamedBytes = serializeCommands(
          streamed.commands,
          cos: document.cos,
          decodeImages: false,
          imagePlaceholders: true,
          compactStateScopes: true,
        );
        expect(materializedBytes, isNotNull, reason: '$name page $pageIndex');
        expect(streamedBytes, materializedBytes,
            reason: '$name page $pageIndex');
      }
    }
  });
}
