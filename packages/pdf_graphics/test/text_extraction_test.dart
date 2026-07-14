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

  test('whole-word search needs non-word boundaries', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final text = PdfTextExtractor.extract(doc, 0); // 'Hello, world!'
    // bounded by start/',' and by space/'!' - both whole words
    expect(text.findAll('Hello', wholeWord: true), hasLength(1));
    expect(text.findAll('world', wholeWord: true), hasLength(1));
    // a substring of a longer word is not a whole word
    expect(text.findAll('wor', wholeWord: true), isEmpty);
    expect(text.findAll('ell', wholeWord: true), isEmpty);
    // without the flag the substring still matches
    expect(text.findAll('wor'), hasLength(1));
  });

  test('regex search matches a pattern; an invalid one yields nothing', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final text = PdfTextExtractor.extract(doc, 0); // 'Hello, world!'
    final match = text.findAll(r'w\w+d', regex: true).single;
    expect(text.text.substring(match.start, match.end), 'world');
    // case sensitivity flows through to regex
    expect(text.findAll(r'WORLD', regex: true), hasLength(1));
    expect(text.findAll(r'WORLD', regex: true, caseSensitive: true), isEmpty);
    // whole-word combines with regex
    expect(text.findAll(r'wor', regex: true, wholeWord: true), isEmpty);
    // an invalid pattern surfaces no matches rather than throwing
    expect(text.findAll('[', regex: true), isEmpty);
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
    // covering only the tail of the run misses its center - whole runs
    // are in or out, no partial text
    expect(text.textIn(const PdfRect(200, 700, 300, 760)), '');
  });

  test('Arabic visual-order glyphs extract in logical order with marks', () {
    const logical = 'رَسُول اللَّه';
    // Embedded PDF fonts normally paint glyphs in visual left-to-right stream
    // order. Combining marks precede their logical base in that order.
    const visual = 'هَّللا لوُسَر';
    final page = PdfTextExtractor.extract(
        PdfDocument.open(_buildArabicTextPdf(visual, embedded: true)), 0);

    expect(page.text, logical);
    expect(page.findAll(logical, caseSensitive: true), hasLength(1));
    expect(page.findAll('اللَّه', caseSensitive: true), hasLength(1));
    expect(page.textIn(const PdfRect(60, 690, 360, 750)), logical);
    expect(
      PdfTextExtractor.reflowPage(
              PdfDocument.open(_buildArabicTextPdf(visual, embedded: true)), 0)
          .text,
      logical,
    );

    // Logical reading order starts on the physical right of the line.
    final firstWord = page.findAll('رَسُول', caseSensitive: true).single;
    final secondWord = page.findAll('اللَّه', caseSensitive: true).single;
    expect(
        firstWord.rects.first.left, greaterThan(secondWord.rects.first.left));
  });

  test('Arabic logical-order substitute text is not double-reversed', () {
    const logical = 'مرحبا 123';
    final page = PdfTextExtractor.extract(
        PdfDocument.open(_buildArabicTextPdf(logical, embedded: false)), 0);

    expect(page.text, logical);
    expect(page.findAll(logical, caseSensitive: true), hasLength(1));
  });

  test('Arabic extraction keeps mixed-script runs and numbers logical', () {
    const logical = 'مرحبا ١٢٣ PDF عالم';
    const visual = 'ملاع PDF ١٢٣ ابحرم';
    final page = PdfTextExtractor.extract(
      PdfDocument.open(
          _buildArabicTextPdf(visual, embedded: true, splitAt: 11)),
      0,
    );

    expect(page.text, logical);
    expect(page.findAll('١٢٣ PDF', caseSensitive: true), hasLength(1));
  });

  test('Arabic span does not reverse an LTR paragraph', () {
    const logical = 'Hello عالم from Dart';
    const visual = 'Hello ملاع from Dart';
    final page = PdfTextExtractor.extract(
        PdfDocument.open(_buildArabicTextPdf(visual, embedded: true)), 0);

    expect(page.text, logical);
    expect(page.findAll(logical, caseSensitive: true), hasLength(1));
  });

  test('Arabic extraction preserves multi-character glyph mappings', () {
    final page = PdfTextExtractor.extract(
      PdfDocument.open(_buildArabicGlyphPdf(
        const ['الله', ' ', 'ل', 'و', 'س', 'ر'],
        embedded: true,
      )),
      0,
    );

    expect(page.text, 'رسول الله');
    expect(page.findAll('الله', caseSensitive: true), hasLength(1));
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

  test('reflow splits a bullet list into separate list items', () {
    final doc = PdfDocument.open(_buildTextPdf([
      _textAt(72, 720, 'Shopping list'),
      _textAt(72, 700, '- apples'),
      _textAt(72, 686, '- pears'),
      _textAt(72, 672, '1. flour'),
    ]));

    final page = PdfTextExtractor.reflowPage(doc, 0);

    expect(page.blocks.map((block) => block.text), [
      'Shopping list',
      '- apples',
      '- pears',
      '1. flour',
    ]);
    expect(page.blocks.map((block) => block.isListItem),
        [false, true, true, true]);
  });

  test('reflow surfaces a placed image among the text in reading order', () {
    final doc = PdfDocument.open(_buildImagePdf());
    final page = PdfTextExtractor.reflowPage(doc, 0);

    // The image (drawn at y 500..620) sits between the two paragraphs.
    expect(page.items, hasLength(3));
    expect(page.items[0], isA<PdfReflowBlock>());
    expect((page.items[0] as PdfReflowBlock).text, 'Above the figure');
    expect(page.items[1], isA<PdfReflowImage>());
    expect((page.items[2] as PdfReflowBlock).text, 'Below the figure');

    final image = page.images.single;
    expect(image.bounds.left, closeTo(100, 1e-6));
    expect(image.bounds.right, closeTo(300, 1e-6));
    expect(image.aspectRatio, closeTo(200 / 120, 1e-6));
    // text-only view ignores images
    expect(page.text, 'Above the figure\n\nBelow the figure');
  });

  test('reflow drops a tiny decorative image', () {
    final doc = PdfDocument.open(_buildImagePdf(imageWidth: 8, imageHeight: 8));
    final page = PdfTextExtractor.reflowPage(doc, 0);
    expect(page.images, isEmpty);
    expect(page.blocks, hasLength(2));
  });

  test('reflow orders an image-only page top to bottom', () {
    final doc = PdfDocument.open(_imageDocWith(
      'q 200 0 0 120 100 600 cm /Im0 Do Q\n'
      'q 200 0 0 120 100 200 cm /Im0 Do Q',
    ));
    final page = PdfTextExtractor.reflowPage(doc, 0);

    expect(page.blocks, isEmpty);
    expect(page.text, '');
    // Same stream, but distinct placements: both survive de-duplication and
    // read highest-first.
    expect(page.images, hasLength(2));
    expect(page.images.first.bounds.bottom, closeTo(600, 1e-6));
    expect(page.images.last.bounds.bottom, closeTo(200, 1e-6));
  });

  test('reflow de-duplicates a repeated watermark image', () {
    final doc = PdfDocument.open(_imageDocWith([
      _textAt(100, 700, 'Body text'),
      'q 300 0 0 300 100 300 cm /Im0 Do Q',
      'q 300 0 0 300 100 300 cm /Im0 Do Q',
    ].join('\n')));
    final page = PdfTextExtractor.reflowPage(doc, 0);

    expect(page.images, hasLength(1));
    expect(page.blocks.map((block) => block.text), ['Body text']);
  });

  test('reflow places an image above all text first', () {
    final doc = PdfDocument.open(_imageDocWith([
      'q 200 0 0 80 100 690 cm /Im0 Do Q', // top of the page, above all text
      _textAt(100, 600, 'First paragraph'),
      _textAt(100, 400, 'Second paragraph'),
    ].join('\n')));
    final page = PdfTextExtractor.reflowPage(doc, 0);

    expect(page.items.first, isA<PdfReflowImage>());
    expect((page.items[1] as PdfReflowBlock).text, 'First paragraph');
    expect((page.items[2] as PdfReflowBlock).text, 'Second paragraph');
  });
}

/// A one-page PDF with two text paragraphs and a single image XObject drawn
/// between them via `cm`/`Do`. The image is placed at (100, 500) sized
/// [imageWidth]×[imageHeight] in page units. The pixel data is ASCII-hex so
/// the whole file stays 7-bit (reflow only records the draw request, but the
/// fixture stays decodable for parity).
Uint8List _buildImagePdf({double imageWidth = 200, double imageHeight = 120}) =>
    _imageDocWith([
      _textAt(100, 700, 'Above the figure'),
      'q $imageWidth 0 0 $imageHeight 100 500 cm /Im0 Do Q',
      _textAt(100, 400, 'Below the figure'),
    ].join('\n'));

/// A one-page PDF whose content is [content]; an `/Im0` 2×2 DeviceRGB image
/// XObject and an `/F1` Helvetica font are available as resources.
Uint8List _imageDocWith(String content) {
  // 2×2 DeviceRGB: red, green, blue, white.
  const hex = 'FF000000FF000000FFFFFFFF>';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> /XObject << /Im0 6 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /XObject /Subtype /Image /Width 2 /Height 2 '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode '
        '/Length ${hex.length} >>\nstream\n$hex\nendstream',
  ];
  return _assemblePdf(objects);
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
  return _assemblePdf(objects);
}

/// A one-line PDF whose character codes map to [text] through /ToUnicode.
///
/// The Type3 variant represents the common embedded-font case: its glyph list
/// is authoritative, so the content stream is visual order. The Type1 variant
/// has no font program and represents the package's Unicode substitution path,
/// whose decoded text is already logical order.
Uint8List _buildArabicTextPdf(String text,
        {required bool embedded, int? splitAt}) =>
    _buildArabicGlyphPdf(
      [for (final rune in text.runes) String.fromCharCode(rune)],
      embedded: embedded,
      splitAt: splitAt,
    );

Uint8List _buildArabicGlyphPdf(List<String> glyphTexts,
    {required bool embedded, int? splitAt}) {
  final codes = [for (var i = 0; i < glyphTexts.length; i++) i + 1];
  final shown = codes.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  final shownText = splitAt == null
      ? '<$shown> Tj'
      : '<${shown.substring(0, splitAt * 2)}> Tj '
          '<${shown.substring(splitAt * 2)}> Tj';
  final content = 'BT /F1 24 Tf 72 720 Td $shownText ET';
  final cmapEntries = <String>[];
  final widths = <String>[];
  final names = <String>[];
  for (var i = 0; i < glyphTexts.length; i++) {
    final code = codes[i];
    final glyphText = glyphTexts[i];
    final unicode = glyphText.codeUnits
        .map((unit) => unit.toRadixString(16).padLeft(4, '0'))
        .join();
    cmapEntries.add('<${code.toRadixString(16).padLeft(2, '0')}> '
        '<$unicode>');
    widths.add(switch (glyphText.runes.toList()) {
      [0x20] => '250',
      [>= 0x064B && <= 0x065F] => '0',
      _ => '500',
    });
    names.add('/g$code');
  }
  final cmap = [
    '/CIDInit /ProcSet findresource begin',
    '12 dict begin begincmap',
    '1 begincodespacerange <00> <FF> endcodespacerange',
    '${cmapEntries.length} beginbfchar',
    ...cmapEntries,
    'endbfchar endcmap CMapName currentdict /CMap defineresource pop',
    'end end',
  ].join('\n');
  final type3 = embedded
      ? ' /FontBBox [0 -200 1000 800] '
          '/FontMatrix [0.001 0 0 0.001 0 0] '
          '/CharProcs << ${[
          for (final name in names) '$name 7 0 R'
        ].join(' ')} >> '
          '/Resources << >>'
      : '';
  final font = '<< /Type /Font /Subtype /${embedded ? 'Type3' : 'Type1'} '
      '${embedded ? '' : '/BaseFont /Helvetica '}'
      '/FirstChar 1 /LastChar ${glyphTexts.length} '
      '/Widths [${widths.join(' ')}] '
      '/Encoding << /Type /Encoding /Differences [1 ${names.join(' ')}] >> '
      '/ToUnicode 6 0 R$type3 >>';
  const charProc = '500 0 d0 0 0 450 700 re f';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    font,
    '<< /Length ${cmap.length} >>\nstream\n$cmap\nendstream',
    '<< /Length ${charProc.length} >>\nstream\n$charProc\nendstream',
  ];
  return _assemblePdf(objects);
}

Uint8List _assemblePdf(List<String> objects) {
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
