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
}
