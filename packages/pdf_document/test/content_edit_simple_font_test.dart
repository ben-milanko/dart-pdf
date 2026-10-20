import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

/// A one-page PDF whose /F1 is a *subsetted* simple font that renumbered its
/// codes, the shape behind the "date field shows `-=>-/>?-?@`" report.
///
/// The /Differences below are chosen so the bytes drawing `05/08/2026` read
/// as exactly the string from that screenshot when taken as Latin-1:
///
///   '0' -> 45 (0x2D '-')   '5' -> 61 (0x3D '=')   '/' -> 62 (0x3E '>')
///   '8' -> 47 (0x2F '/')   '2' -> 63 (0x3F '?')   '6' -> 64 (0x40 '@')
///
/// [toUnicode] optionally adds a /ToUnicode CMap saying the same thing a
/// different way, which is how most real producers state it.
Uint8List buildRemappedFontPdf(String content, {bool toUnicode = false}) {
  const cmap = '/CIDInit /ProcSet findresource begin\n'
      '12 dict begin begincmap\n'
      '1 begincodespacerange <00> <FF> endcodespacerange\n'
      '6 beginbfchar\n'
      '<2D> <0030>\n'
      '<3D> <0035>\n'
      '<3E> <002F>\n'
      '<2F> <0038>\n'
      '<3F> <0032>\n'
      '<40> <0036>\n'
      'endbfchar\n'
      'endcmap CMapName currentdict /CMap defineresource pop end end';

  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R /F2 7 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /TrueType /BaseFont /AAAAAA+Calibri '
        '/FirstChar 45 /LastChar 64 '
        '/Widths [${List.filled(20, 500).join(' ')}] '
        '/Encoding << /Type /Encoding /Differences '
        '[45 /zero 47 /eight 61 /five /slash /two /six] >>'
        '${toUnicode ? ' /ToUnicode 6 0 R' : ''} >>',
    '<< /Length ${cmap.length} >>\nstream\n$cmap\nendstream',
    // a plain base-14 face, for the "unencodable character" comparison
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
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

/// A one-page PDF whose /F1 is [fontDict] verbatim, drawing [content].
/// Lets each test state exactly the font shape it is about.
Uint8List buildFontPdf(String fontDict, String content) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    fontDict,
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
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

/// `05/08/2026` in the remapped font's own codes.
const dateCodes = r'-=>-/>?-?@';

String pageText(PdfDocument doc) => latin1.decode(doc.page(0).contentBytes());

void main() {
  group('simple fonts with a remapped encoding', () {
    test('element text reads through /Differences, not as raw bytes', () {
      final doc = PdfDocument.open(buildRemappedFontPdf(
        'BT /F1 12 Tf 72 700 Td ($dateCodes) Tj ET\n',
      ));
      final elements = PdfPageElements.of(doc, 0).elements;
      expect(elements, hasLength(1));
      expect(elements.single.text, '05/08/2026');
    });

    test('/ToUnicode says the same thing and is honoured too', () {
      final doc = PdfDocument.open(buildRemappedFontPdf(
        'BT /F1 12 Tf 72 700 Td ($dateCodes) Tj ET\n',
        toUnicode: true,
      ));
      expect(PdfPageElements.of(doc, 0).elements.single.text, '05/08/2026');
    });

    test('a replacement is written back in the font\'s own codes', () {
      final doc = PdfDocument.open(buildRemappedFontPdf(
        'BT /F1 12 Tf 72 700 Td ($dateCodes) Tj ET\n',
      ));
      final editor = PdfEditor(doc);
      // every character of the replacement is one the subset kept
      expect(editor.replaceText(0, '05/08/2026', '26/05/2026'), 1);

      final saved = PdfDocument.open(editor.save());
      expect(PdfPageElements.of(saved, 0).elements.single.text, '26/05/2026');
      // and physically: the codes, not the ASCII of the new text
      expect(pageText(saved), contains(r'(?@>-=>?-?@)'));
      expect(pageText(saved), isNot(contains('(26/05/2026)')));
    });

    test('a character the subset dropped leaves the run untouched', () {
      final doc = PdfDocument.open(buildRemappedFontPdf(
        'BT /F1 12 Tf 72 700 Td ($dateCodes) Tj ET\n',
      ));
      final editor = PdfEditor(doc);
      // '9' is not among the glyphs this subset kept: there is no code that
      // would draw it, so the edit must decline rather than draw something
      // else at the ASCII position of '9'.
      expect(editor.replaceText(0, '05/08/2026', '05/09/2026'), 0);
      expect(pageText(PdfDocument.open(editor.save())), contains('($dateCodes)'));
    });

    test('a plain base-14 run still round-trips as Latin-1', () {
      final doc = PdfDocument.open(buildRemappedFontPdf(
        'BT /F2 12 Tf 72 700 Td (Revision: B) Tj ET\n',
      ));
      expect(PdfPageElements.of(doc, 0).elements.single.text, 'Revision: B');
      final editor = PdfEditor(doc);
      expect(editor.replaceText(0, 'Revision: B', 'Revision: C'), 1);
      expect(pageText(PdfDocument.open(editor.save())),
          contains('(Revision: C)'));
    });

    test('widths come from the font, so bounds are not Helvetica-shaped', () {
      final doc = PdfDocument.open(buildRemappedFontPdf(
        'BT /F1 12 Tf 72 700 Td ($dateCodes) Tj ET\n',
      ));
      final element = PdfPageElements.of(doc, 0).elements.single;
      // 10 glyphs, all /Widths 500, at 12pt
      expect(element.bounds!.width, closeTo(10 * 0.5 * 12, 0.01));
    });
  });

  group("the ' and \" show operators", () {
    // These carry a line break, so replaceText rewrites their string in
    // place rather than through the run rewriter - a separate code path that
    // must encode through the font just the same.
    test("' rewrites its string in the font's own codes", () {
      final doc = PdfDocument.open(buildRemappedFontPdf(
        'BT /F1 12 Tf 14 TL 72 700 Td ($dateCodes) \' ET\n',
      ));
      expect(PdfPageElements.of(doc, 0).elements.single.text, '05/08/2026');

      final editor = PdfEditor(doc);
      expect(editor.replaceText(0, '05/08/2026', '26/05/2026'), 1);
      final saved = PdfDocument.open(editor.save());
      expect(pageText(saved), contains(r'(?@>-=>?-?@)'));
      expect(PdfPageElements.of(saved, 0).elements.single.text, '26/05/2026');
    });

    test('" rewrites its string and keeps its spacing operands', () {
      final doc = PdfDocument.open(buildRemappedFontPdf(
        'BT /F1 12 Tf 14 TL 72 700 Td 1 2 ($dateCodes) " ET\n',
      ));
      final editor = PdfEditor(doc);
      expect(editor.replaceText(0, '05/08/2026', '26/05/2026'), 1);
      final text = pageText(PdfDocument.open(editor.save()));
      expect(text, contains(r'1 2 (?@>-=>?-?@) "'));
    });

    test("a character the subset dropped leaves ' alone", () {
      final doc = PdfDocument.open(buildRemappedFontPdf(
        'BT /F1 12 Tf 14 TL 72 700 Td ($dateCodes) \' ET\n',
      ));
      final editor = PdfEditor(doc);
      // '9' is not a glyph this subset kept
      expect(editor.replaceText(0, '05/08/2026', '05/09/2026'), 0);
      expect(pageText(PdfDocument.open(editor.save())),
          contains('($dateCodes)'));
    });
  });

  group('targeted element edits', () {
    /// The same date drawn twice, as a header and a footer would be.
    String twice() => 'BT /F1 12 Tf 72 700 Td ($dateCodes) Tj ET\n'
        'BT /F1 12 Tf 72 100 Td ($dateCodes) Tj ET\n';

    test('replaceElementText rewrites only the selected occurrence', () {
      final doc = PdfDocument.open(buildRemappedFontPdf(twice()));
      final elements = PdfPageElements.of(doc, 0);
      expect(elements.elements, hasLength(2));

      final editor = PdfEditor(doc);
      expect(
        editor.replaceElementText(
            elements, elements.elements[1], '05/08/2026', '26/05/2026'),
        1,
      );

      final after = PdfPageElements.of(PdfDocument.open(editor.save()), 0);
      expect(after.elements[0].text, '05/08/2026');
      expect(after.elements[1].text, '26/05/2026');
    });

    test('page-wide replaceText still rewrites both', () {
      final doc = PdfDocument.open(buildRemappedFontPdf(twice()));
      final editor = PdfEditor(doc);
      expect(editor.replaceText(0, '05/08/2026', '26/05/2026'), 2);
    });
  });

  group('base encodings named rather than spelled out', () {
    // The dominant real-world shape: /Encoding is a *name*, so every code
    // resolves through that encoding's glyph-name table. Getting this wrong
    // is invisible - text still reads right, but replacements silently
    // refuse because nothing lands in the encodable set.
    String winAnsiFont() => '<< /Type /Font /Subtype /TrueType '
        '/BaseFont /BCDEFG+Calibri /Encoding /WinAnsiEncoding '
        '/FirstChar 32 /LastChar 255 '
        '/Widths [${List.filled(224, 500).join(' ')}] >>';

    test('/WinAnsiEncoding reads and writes as itself', () {
      final doc = PdfDocument.open(
          buildFontPdf(winAnsiFont(), 'BT /F1 12 Tf 72 700 Td (Caf\xe9) Tj ET\n'));
      expect(PdfPageElements.of(doc, 0).elements.single.text, 'Café');

      final editor = PdfEditor(doc);
      // 'e' with an acute is WinAnsi 0xE9 via /eacute - a high-byte code the
      // table must resolve in both directions.
      expect(editor.replaceText(0, 'Café', 'Thé'), 1);
      final saved = PdfDocument.open(editor.save());
      expect(PdfPageElements.of(saved, 0).elements.single.text, 'Thé');
      expect(pageText(saved), contains('(Th\xe9)'));
    });

    test('/MacRomanEncoding resolves through the standard names', () {
      final doc = PdfDocument.open(buildFontPdf(
        '<< /Type /Font /Subtype /TrueType /BaseFont /HIJKLM+Arial '
            '/Encoding /MacRomanEncoding >>',
        'BT /F1 12 Tf 72 700 Td (Plain ASCII) Tj ET\n',
      ));
      expect(PdfPageElements.of(doc, 0).elements.single.text, 'Plain ASCII');
      final editor = PdfEditor(doc);
      expect(editor.replaceText(0, 'Plain ASCII', 'Still ASCII'), 1);
      expect(pageText(PdfDocument.open(editor.save())), contains('(Still ASCII)'));
    });
  });

  group('fonts with a built-in encoding', () {
    test('ZapfDingbats codes read as their dingbats and round-trip', () {
      // code 0x61 is a3 in ZapfDingbatsEncoding: U+2701..-ish territory
      final doc = PdfDocument.open(buildFontPdf(
        '<< /Type /Font /Subtype /Type1 /BaseFont /ZapfDingbats >>',
        'BT /F1 12 Tf 72 700 Td (ab) Tj ET\n',
      ));
      final text = PdfPageElements.of(doc, 0).elements.single.text!;
      expect(text, hasLength(2));
      // not the Latin letters - the built-in encoding took precedence
      expect(text, isNot('ab'));

      // and the reverse table accepts what it just decoded
      final editor = PdfEditor(doc);
      expect(editor.replaceText(0, text, text.split('').reversed.join()), 1);
      expect(pageText(PdfDocument.open(editor.save())), contains('(ba)'));
    });

    test('Symbol codes read as Greek, not Latin', () {
      final doc = PdfDocument.open(buildFontPdf(
        '<< /Type /Font /Subtype /Type1 /BaseFont /Symbol >>',
        'BT /F1 12 Tf 72 700 Td (abg) Tj ET\n',
      ));
      // Symbol's built-in encoding maps a/b/g to alpha/beta/gamma
      expect(PdfPageElements.of(doc, 0).elements.single.text,
          'αβγ');
    });

    test('a subset-tagged Symbol is still Symbol', () {
      final doc = PdfDocument.open(buildFontPdf(
        '<< /Type /Font /Subtype /Type1 /BaseFont /ABCDEF+Symbol >>',
        'BT /F1 12 Tf 72 700 Td (a) Tj ET\n',
      ));
      expect(PdfPageElements.of(doc, 0).elements.single.text, 'α');
    });
  });

  group('malformed and missing metrics', () {
    test('a broken /ToUnicode leaves the encoding-derived table standing', () {
      // /ToUnicode points at a stream of junk: it must not throw, and the
      // font must still read through its /Differences.
      final content = 'BT /F1 12 Tf 72 700 Td (\x2d\x2f) Tj ET\n';
      const junk = 'this is not a CMap at all';
      final objects = <String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
            '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
        '<< /Length ${content.length} >>\nstream\n$content\nendstream',
        '<< /Type /Font /Subtype /TrueType /BaseFont /NOPQRS+Calibri '
            '/Encoding << /Type /Encoding /Differences [45 /zero 47 /eight] >> '
            '/ToUnicode 6 0 R >>',
        '<< /Length ${junk.length} >>\nstream\n$junk\nendstream',
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
      final doc =
          PdfDocument.open(Uint8List.fromList(latin1.encode(buffer.toString())));
      expect(PdfPageElements.of(doc, 0).elements.single.text, '08');
    });

    test('a /ToUnicode whose stream cannot even be decoded is survivable', () {
      // /FlateDecode over bytes that are not flate at all - the decode
      // itself blows up, not just the CMap parse. Real-world files do this,
      // and the font must still read through its /Differences.
      final content = 'BT /F1 12 Tf 72 700 Td (\x2d\x2f) Tj ET\n';
      const junk = 'definitely not deflate data';
      final objects = <String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
            '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
        '<< /Length ${content.length} >>\nstream\n$content\nendstream',
        '<< /Type /Font /Subtype /TrueType /BaseFont /NOPQRS+Calibri '
            '/Encoding << /Type /Encoding /Differences [45 /zero 47 /eight] >> '
            '/ToUnicode 6 0 R >>',
        '<< /Length ${junk.length} /Filter /FlateDecode >>\n'
            'stream\n$junk\nendstream',
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
      final doc =
          PdfDocument.open(Uint8List.fromList(latin1.encode(buffer.toString())));
      expect(PdfPageElements.of(doc, 0).elements.single.text, '08');
    });

    test('/MissingWidth covers codes outside /FirstChar../LastChar', () {
      // 'A' (0x41) is inside the range at width 600; 'z' (0x7A) is outside it
      // and must fall to the descriptor's (real-valued) /MissingWidth.
      final doc = PdfDocument.open(buildFontPdf(
        '<< /Type /Font /Subtype /TrueType /BaseFont /TUVWXY+Arial '
            '/Encoding /WinAnsiEncoding /FirstChar 65 /LastChar 66 '
            '/Widths [600 600] '
            '/FontDescriptor << /Type /FontDescriptor /FontName /TUVWXY+Arial '
            '/MissingWidth 250.5 >> >>',
        'BT /F1 10 Tf 72 700 Td (ABz) Tj ET\n',
      ));
      final element = PdfPageElements.of(doc, 0).elements.single;
      expect(element.text, 'ABz');
      // (600 + 600 + 250.5)/1000 * 10pt
      expect(element.bounds!.width, closeTo(14.505, 0.001));
    });

    test('an unknown face with no /Widths falls back to Helvetica metrics', () {
      final doc = PdfDocument.open(buildFontPdf(
        '<< /Type /Font /Subtype /TrueType /BaseFont /ZZZZZZ+SomethingElse >>',
        'BT /F1 12 Tf 72 700 Td (iii) Tj ET\n',
      ));
      final element = PdfPageElements.of(doc, 0).elements.single;
      // Helvetica's 'i' is 222/1000 em - a narrow glyph, so this would be
      // obviously wrong if the fallback were a fixed 500.
      expect(element.bounds!.width, closeTo(3 * 0.222 * 12, 0.01));
    });
  });
}
