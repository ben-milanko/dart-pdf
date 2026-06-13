import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  test('extracts the fixture page text', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final text = PdfTextExtractor.extract(doc, 0);
    expect(text.text, 'Hello, world!');
    expect(text.runs, hasLength(1));
  });

  test('run bounds sit at the drawn position', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final run = PdfTextExtractor.extract(doc, 0).runs.single;
    // drawn at 72,720 in 24pt with built-in Helvetica AFM advances
    expect(run.bounds.left, 72);
    expect(run.bounds.right,
        closeTo(72 + measureHelvetica('Hello, world!', 24), 1e-6));
    expect(run.bounds.bottom, closeTo(720 - 0.25 * 24, 1e-6));
    expect(run.bounds.top, closeTo(720 + 0.75 * 24, 1e-6));
  });

  test('findAll locates substrings with interpolated rects', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final text = PdfTextExtractor.extract(doc, 0);

    final matches = text.findAll('world');
    expect(matches, hasLength(1));
    final match = matches.single;
    expect(text.text.substring(match.start, match.end), 'world');
    final rect = match.rects.single;
    // 'world' starts at char 7 of 13; rects interpolate linearly across
    // the run's drawn width
    final width = measureHelvetica('Hello, world!', 24);
    expect(rect.left, closeTo(72 + width * (7 / 13), 1e-6));
    expect(rect.right, closeTo(72 + width * (12 / 13), 1e-6));
  });

  test('search is case-insensitive by default', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final text = PdfTextExtractor.extract(doc, 0);
    expect(text.findAll('HELLO'), hasLength(1));
    expect(text.findAll('HELLO', caseSensitive: true), isEmpty);
  });

  test('positionNear maps page points to character offsets', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final text = PdfTextExtractor.extract(doc, 0);
    // 'Hello, world!' at 72,720 in 24pt; offsets interpolate linearly
    // across the run width
    final perChar = measureHelvetica('Hello, world!', 24) / 13;
    expect(text.positionNear(72, 720), 0);
    expect(text.positionNear(72 + perChar * 7, 720), 7); // before 'w'
    expect(text.positionNear(228, 720), 13); // past the end
    // snaps vertically from outside the bounds
    expect(text.positionNear(72 + perChar * 7, 750), 7);
    // but respects a finite tolerance
    expect(text.positionNear(72, 400, tolerance: 20), -1);
    expect(text.positionNear(400, 400, tolerance: 20), -1);
  });

  test('rectsFor covers a character range', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final text = PdfTextExtractor.extract(doc, 0);
    final rect = text.rectsFor(7, 12).single;
    final perChar = measureHelvetica('Hello, world!', 24) / 13;
    expect(rect.left, closeTo(72 + perChar * 7, 1e-6));
    expect(rect.right, closeTo(72 + perChar * 12, 1e-6));
  });

  test('quadsFor matches the rect for horizontal text', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final text = PdfTextExtractor.extract(doc, 0);
    final quad = text.quadsFor(7, 12).single;
    final ll = quad.corners[0];
    final lr = quad.corners[1];
    // horizontal baseline: the two baseline corners share y, advance in x
    expect(lr.$2, closeTo(ll.$2, 1e-6));
    expect(lr.$1, greaterThan(ll.$1));
    // and the axis-aligned bounds equal the legacy rect
    expect(quad.bounds, text.rectsFor(7, 12).single);
  });

  test('quadsFor rotates with rotated text', () {
    // a 90° CCW text matrix: (x, y) -> (e - y, f + x), so the baseline
    // runs straight up the page instead of across it
    final doc = PdfDocument.open(_buildTextPdf([
      'BT /F1 12 Tf 0 1 -1 0 100 100 Tm (Rotated) Tj ET',
    ]));
    final text = PdfTextExtractor.extract(doc, 0);
    final quad = text.quadsFor(0, text.text.length).single;
    final ll = quad.corners[0];
    final lr = quad.corners[1];
    // the baseline (ll -> lr) is vertical: same x, the advance is in y
    expect(lr.$1, closeTo(ll.$1, 1e-6));
    expect(lr.$2 - ll.$2, greaterThan(10));
    // the rect still reports the enclosing axis-aligned box (covers the
    // whole rotated quad, both wider and taller than zero)
    final rect = text.rectsFor(0, text.text.length).single;
    expect(rect, quad.bounds);
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
  });

  test('multi-page documents extract per page', () {
    final doc = PdfDocument.open(buildMultiPagePdf(3));
    expect(PdfTextExtractor.extract(doc, 0).text, 'Page 1');
    expect(PdfTextExtractor.extract(doc, 2).text, 'Page 3');
  });

  test('textIn returns the runs whose center a rectangle covers', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final text = PdfTextExtractor.extract(doc, 0);
    // 'Hello, world!' spans x 72..204, y 714..738 (center ~138, 726)
    expect(text.textIn(const PdfRect(60, 700, 300, 760)), 'Hello, world!');
    expect(text.textIn(const PdfRect(0, 0, 50, 50)), '');
    // covering only the tail of the run misses its center — whole runs
    // are in or out, no partial text
    expect(text.textIn(const PdfRect(200, 700, 300, 760)), '');
  });

  test('reflow reads visual columns before stream order', () {
    final doc = PdfDocument.open(_buildTextPdf([
      _textAt(320, 720, 'Right top'),
      _textAt(72, 720, 'Left top'),
      _textAt(320, 704, 'Right bottom'),
      _textAt(72, 704, 'Left bottom'),
    ]));

    final page = PdfTextExtractor.reflowPage(doc, 0);

    expect(page.blocks.map((block) => block.text), [
      'Left top Left bottom',
      'Right top Right bottom',
    ]);
  });

  test('reflow splits paragraphs on vertical gaps', () {
    final doc = PdfDocument.open(_buildTextPdf([
      _textAt(72, 720, 'First line'),
      _textAt(72, 704, 'continues here'),
      _textAt(72, 660, 'Second paragraph'),
    ]));

    final page = PdfTextExtractor.reflowPage(doc, 0);

    expect(page.blocks.map((block) => block.text), [
      'First line continues here',
      'Second paragraph',
    ]);
  });

  test('reflow repairs line-end hyphenation', () {
    final doc = PdfDocument.open(_buildTextPdf([
      _textAt(72, 720, 'para-'),
      _textAt(72, 704, 'graph text'),
    ]));

    final page = PdfTextExtractor.reflowPage(doc, 0);

    expect(page.text, 'paragraph text');
  });
}

String _textAt(num x, num y, String text) =>
    'BT /F1 12 Tf $x $y Td (${_escapePdfText(text)}) Tj ET';

String _escapePdfText(String text) =>
    text.replaceAll('\\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');

Uint8List _buildTextPdf(List<String> operations) {
  final content = operations.join('\n');
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
