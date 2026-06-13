import 'dart:typed_data';
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  late CosDocument cos;

  setUp(() => cos = CosDocument.open(buildClassicPdf()));

  test('simple font widths are thousandths of an em', () {
    final font = CosDictionary({
      'Subtype': const CosName('TrueType'),
      'FirstChar': const CosInteger(65),
      'Widths': CosArray([const CosInteger(722)]),
    });
    expect(PdfFontInfo.load(cos, font).widthOf(65), closeTo(0.722, 1e-9));
  });

  test('Type3 widths scale by the FontMatrix, not /1000', () {
    // browser-print PDFs use Type3 fonts with a 1/2048 glyph space
    final font = CosDictionary({
      'Subtype': const CosName('Type3'),
      'FontMatrix': CosArray([
        const CosReal(0.00048828125),
        const CosInteger(0),
        const CosInteger(0),
        const CosReal(-0.00048828125),
        const CosInteger(0),
        const CosInteger(0),
      ]),
      'FirstChar': const CosInteger(72),
      'Widths': CosArray([const CosReal(1578)]),
    });
    final info = PdfFontInfo.load(cos, font);
    expect(info.widthOf(72), closeTo(1578 / 2048, 1e-9));
  });

  test('Type3 with a missing FontMatrix falls back to /1000', () {
    final font = CosDictionary({
      'Subtype': const CosName('Type3'),
      'FirstChar': const CosInteger(65),
      'Widths': CosArray([const CosInteger(500)]),
    });
    expect(PdfFontInfo.load(cos, font).widthOf(65), closeTo(0.5, 1e-9));
  });

  test('Type3 missing glyphs do not advance before word spacing', () {
    final font = CosDictionary({
      'Subtype': const CosName('Type3'),
      'FirstChar': const CosInteger(97),
      'LastChar': const CosInteger(98),
      'Widths': CosArray([const CosInteger(1000), const CosInteger(1000)]),
    });
    final info = PdfFontInfo.load(cos, font);
    expect(info.widthOf(0x20), 0);
  });

  test('standard fonts decode high-byte StandardEncoding glyph names', () {
    final font = CosDictionary({
      'Subtype': const CosName('Type1'),
      'BaseFont': const CosName('Helvetica'),
    });
    final info = PdfFontInfo.load(cos, font);
    expect(info.charFor(0xD0), String.fromCharCode(0x2014));
  });

  test('WinAnsi standalone spacing diacritics decode to Unicode', () {
    final font = CosDictionary({
      'Subtype': const CosName('Type1'),
      'BaseFont': const CosName('Courier'),
      'Encoding': const CosName('WinAnsiEncoding'),
    });
    final info = PdfFontInfo.load(cos, font);
    // 0x88 'circumflex' and 0x98 'tilde' have no Latin-1 codepoint; without a
    // glyph-name -> Unicode entry they fell through to the C1 control range and
    // rendered as tofu in substituted fonts.
    expect(info.charFor(0x88), String.fromCharCode(0x02C6));
    expect(info.charFor(0x98), String.fromCharCode(0x02DC));
  });

  test('ZapfDingbats decodes built-in symbol codes to Unicode', () {
    final font = CosDictionary({
      'Subtype': const CosName('Type1'),
      'BaseFont': const CosName('ZapfDingbats'),
    });
    final info = PdfFontInfo.load(cos, font);
    expect(info.charFor(0x21), String.fromCharCode(0x2701));
  });

  test('malformed GBK simple Chinese fonts decode byte pairs', () {
    final font = CosDictionary({
      'Subtype': const CosName('TrueType'),
      'BaseFont': const CosName('ËÎÌå'),
      'Encoding': const CosName('WinAnsiEncoding'),
      'FirstChar': const CosInteger(0),
      'Widths': CosArray([
        for (var i = 0; i < 256; i++) const CosInteger(500),
      ]),
    });

    final info = PdfFontInfo.load(cos, font);
    final codes = info.codesOf(Uint8List.fromList([0xC4, 0xBF, 0x20]));

    expect(codes, [0xC4BF]);
    expect(info.charFor(codes[0]), '目');
    expect(info.widthOf(codes[0]), closeTo(1.0, 1e-9));
  });

  test('embedded subset TrueType selects glyphs via Encoding, not ToUnicode',
      () {
    // pdfkit_compressed embeds "Some text with an embedded font!" in a subset
    // TrueType whose (3,1) cmap is keyed on the encoded code points reached
    // through MacRomanEncoding glyph names (code 33 → "exclam" → U+0021 →
    // gid), while /ToUnicode remaps those codes to the semantic letters. Glyph
    // selection must follow the encoding (§9.6.6.4): before that fix every code
    // resolved to gid 0, so all 16 codes drew the same .notdef box.
    final doc = CosDocument.open(
        File('../../test_corpora/pdfjs/pdfkit_compressed.pdf')
            .readAsBytesSync());
    CosDictionary? fontDict;
    for (final number in doc.objectNumbers) {
      final obj = doc.resolve(CosReference(number, 0));
      if (obj is CosDictionary &&
          (obj['Subtype'] as CosName?)?.value == 'TrueType') {
        fontDict = obj;
        break;
      }
    }
    expect(fontDict, isNotNull, reason: 'embedded TrueType font not found');

    final info = PdfFontInfo.load(doc, fontDict!);
    final signatures = <String>{};
    var withOutline = 0;
    for (var code = 33; code <= 48; code++) {
      // Code 37 is the space glyph here — legitimately empty; skip empties.
      final outline = info.outlineFor(code);
      if (outline == null || outline.segments.isEmpty) continue;
      withOutline++;
      final kinds = outline.segments.map((s) => s.runtimeType.toString());
      signatures.add('${kinds.join(',')}#${outline.segments.length}');
    }
    // The 16-glyph subset draws "Some text with an embedded font!": most codes
    // carry a real outline and they are distinct. With the bug every code
    // resolved to gid 0, collapsing to a single .notdef signature.
    expect(withOutline, greaterThanOrEqualTo(12));
    expect(signatures.length, greaterThan(1));
  });
}
