import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// One-page Helvetica PDF around [content].
Uint8List buildPdf(String content) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

void main() {
  // a three-line body paragraph followed (after a gap) by a footer line.
  const content = 'BT /F1 14 Tf 16 TL 72 700 Td '
      '(The quick brown fox jumps) Tj '
      'T* (over the lazy sleeping dog) Tj '
      'T* (beside the river at dawn) Tj '
      '0 -32 Td (End of section footer) Tj ET';

  test('a reflowed paragraph interprets and reads correctly through the '
      'rendering pipeline', () {
    final doc = PdfDocument.open(buildPdf(content));

    // baseline: the footer sits below the body, no overlap
    final before = PdfTextExtractor.extract(doc, 0);
    final footerBefore =
        before.runs.firstWhere((r) => r.text.contains('footer'));

    final editor = PdfEditor(doc);
    final grew = editor.reflowText(0, 'fox',
        'fox and several additional descriptive words that force more lines');
    expect(grew, isTrue);
    final out = PdfDocument.open(editor.save());

    // the same interpreter the rasterizer uses must handle the rewritten
    // stream - extraction runs the full PdfInterpreter.
    final after = PdfTextExtractor.extract(out, 0);
    expect(after.runs, isNotEmpty);

    final bodyRuns =
        after.runs.where((r) => !r.text.contains('footer')).toList();
    final footerAfter =
        after.runs.firstWhere((r) => r.text.contains('footer'));

    // the paragraph grew past its original three lines …
    final bodyBaselines = <double>{
      for (final r in bodyRuns) (r.bounds.bottom * 100).round() / 100,
    };
    expect(bodyBaselines.length, greaterThan(3));

    // … the footer dropped to make room and still clears the last body line
    // (no overlap) …
    expect(footerAfter.bounds.top, lessThan(footerBefore.bounds.top));
    final lastBody = bodyRuns
        .reduce((a, b) => a.bounds.bottom < b.bounds.bottom ? a : b);
    expect(lastBody.bounds.bottom, greaterThanOrEqualTo(footerAfter.bounds.top));

    // … and reading order recovers the edited paragraph, then the footer.
    final reading = PdfTextReflower.reflow(after).text;
    expect(
        reading.replaceAll(RegExp(r'\s+'), ' '),
        contains('The quick brown fox and several additional descriptive '
            'words that force more lines jumps over the lazy sleeping dog '
            'beside the river at dawn'));
    expect(reading, contains('End of section footer'));
  });
}
