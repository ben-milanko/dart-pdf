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

  test('charFor memoises simple-font codes to the same string instance', () {
    final font = CosDictionary({
      'Subtype': const CosName('Type1'),
      'BaseFont': const CosName('Helvetica'),
    });
    final info = PdfFontInfo.load(cos, font);
    // A body page shows the same code thousands of times; the second lookup
    // must return the cached instance, not recompute (and re-allocate) it.
    final a = info.charFor(0x41); // 'A'
    final b = info.charFor(0x41);
    expect(a, 'A');
    expect(identical(a, b), isTrue,
        reason: 'repeat lookups return the memoised string');
    // The empty string (unmapped control code) is a valid cached value, so it
    // must stay stable too - not recompute on every call.
    expect(info.charFor(0x00), info.charFor(0x00));
    // Memoising must not change the decoded value of any other code.
    expect(info.charFor(0xD0), String.fromCharCode(0x2014));
  });

  test('Identity-V Type0 font is vertical with default DW2 metrics', () {
    final font = CosDictionary({
      'Subtype': const CosName('Type0'),
      'BaseFont': const CosName('Test'),
      'Encoding': const CosName('Identity-V'),
      'DescendantFonts': CosArray([
        CosDictionary({
          'Subtype': const CosName('CIDFontType2'),
          'DW': const CosInteger(1000),
        }),
      ]),
    });
    final info = PdfFontInfo.load(cos, font);
    expect(info.isVertical, isTrue);
    // DW2 default [880 -1000]: w1y = -1 em downward.
    expect(info.verticalAdvanceOf(7), closeTo(-1.0, 1e-9));
    final v = info.verticalOriginOf(7);
    expect(v.x, closeTo(0.5, 1e-9)); // half the horizontal width (DW 1000)
    expect(v.y, closeTo(0.88, 1e-9)); // DW2[0]
  });

  test('Identity-H Type0 font is horizontal', () {
    final font = CosDictionary({
      'Subtype': const CosName('Type0'),
      'Encoding': const CosName('Identity-H'),
      'DescendantFonts': CosArray([
        CosDictionary({'Subtype': const CosName('CIDFontType2')}),
      ]),
    });
    expect(PdfFontInfo.load(cos, font).isVertical, isFalse);
  });

  test('vertical font honours per-CID /W2 over DW2', () {
    final font = CosDictionary({
      'Subtype': const CosName('Type0'),
      'Encoding': const CosName('Identity-V'),
      'DescendantFonts': CosArray([
        CosDictionary({
          'Subtype': const CosName('CIDFontType2'),
          'DW': const CosInteger(1000),
          // CID 5: w1y -900, vx 450, vy 800
          'W2': CosArray([
            const CosInteger(5),
            CosArray([
              const CosInteger(-900),
              const CosInteger(450),
              const CosInteger(800),
            ]),
          ]),
        }),
      ]),
    });
    final info = PdfFontInfo.load(cos, font);
    expect(info.verticalAdvanceOf(5), closeTo(-0.9, 1e-9));
    final v = info.verticalOriginOf(5);
    expect(v.x, closeTo(0.45, 1e-9));
    expect(v.y, closeTo(0.8, 1e-9));
    // CID without W2 falls back to DW2 defaults.
    expect(info.verticalAdvanceOf(6), closeTo(-1.0, 1e-9));
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
      // Code 37 is the space glyph here - legitimately empty; skip empties.
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

  group('Symbol built-in encoding', () {
    CosDictionary symbolFont({CosObject? encoding}) => CosDictionary({
          'Subtype': const CosName('Type1'),
          'BaseFont': const CosName('Symbol'),
          if (encoding != null) 'Encoding': encoding,
        });

    test('maps the Greek run, not Latin look-alikes', () {
      final info = PdfFontInfo.load(cos, symbolFont());
      // Lower case alpha..omega and the capitals share the Greek block, so a
      // reader searching for a typed Greek letter matches the extracted text.
      expect(info.charFor(0x61), 'α'); // alpha, was 'a'
      expect(info.charFor(0x62), 'β'); // beta
      expect(info.charFor(0x70), 'π'); // pi
      expect(info.charFor(0x41), 'Α'); // Alpha
      expect(info.charFor(0x44), 'Δ'); // Delta, not U+2206 increment
      expect(info.charFor(0x57), 'Ω'); // Omega, not U+2126 ohm sign
      expect(info.charFor(0x6D), 'μ'); // mu, not U+00B5 micro sign
    });

    test('maps math operators above 0x7F', () {
      final info = PdfFontInfo.load(cos, symbolFont());
      expect(info.charFor(0xA5), '∞'); // infinity, was '¥'
      expect(info.charFor(0xD6), '√'); // radical, was 'Ö'
      expect(info.charFor(0xF2), '∫'); // integral, was 'ò'
      expect(info.charFor(0x22), '∀'); // universal
      expect(info.charFor(0x24), '∃'); // existential
      expect(info.charFor(0x40), '≅'); // congruent
    });

    test('prefers real characters over Adobe private-use code points', () {
      final info = PdfFontInfo.load(cos, symbolFont());
      // AGL puts these in the corporate-use subarea, where no substituted
      // font carries a glyph - the same tofu trap as the dingbat ornaments.
      expect(info.charFor(0xE2), '®'); // registersans
      expect(info.charFor(0xE3), '©'); // copyrightsans
      expect(info.charFor(0xE4), '™'); // trademarksans
      expect(info.charFor(0xE6), '⎛'); // parenlefttp
      expect(info.charFor(0xEF), '⎪'); // braceex
      expect(info.charFor(0xF4), '⎮'); // integralex
    });

    test('ASCII codes that Symbol shares with Latin are unchanged', () {
      final info = PdfFontInfo.load(cos, symbolFont());
      expect(info.charFor(0x20), ' ');
      expect(info.charFor(0x31), '1');
      expect(info.charFor(0x3D), '=');
      expect(info.charFor(0x25), '%');
    });

    test('a base encoding does not override the built-in one', () {
      // Producers routinely tag a Symbol font /WinAnsiEncoding while meaning
      // the Greek glyphs; honouring WinAnsi there would render Latin letters.
      final info = PdfFontInfo.load(
          cos, symbolFont(encoding: const CosName('WinAnsiEncoding')));
      expect(info.charFor(0x61), 'α');
    });

    test('/Differences outranks the built-in encoding', () {
      final info = PdfFontInfo.load(
        cos,
        symbolFont(
          encoding: CosDictionary({
            'Differences': CosArray([
              const CosInteger(0x61),
              const CosName('bullet'),
            ]),
          }),
        ),
      );
      expect(info.charFor(0x61), '•'); // the document's explicit name wins
      expect(info.charFor(0x62), 'β'); // untouched codes stay Greek
    });

    test('only the Symbol base font gets the table', () {
      final helvetica = CosDictionary({
        'Subtype': const CosName('Type1'),
        'BaseFont': const CosName('Helvetica'),
      });
      expect(PdfFontInfo.load(cos, helvetica).charFor(0x61), 'a');
    });

    test('a subset prefix still resolves to Symbol', () {
      final font = CosDictionary({
        'Subtype': const CosName('Type1'),
        'BaseFont': const CosName('ABCDEF+Symbol'),
      });
      expect(PdfFontInfo.load(cos, font).charFor(0x61), 'α');
    });
  });

  test('Symbol glyph names resolve for any font, not just Symbol', () {
    // A /Differences array naming Greek or math glyphs is unambiguous, and
    // nothing confines those names to the Symbol base font.
    final font = CosDictionary({
      'Subtype': const CosName('TrueType'),
      'BaseFont': const CosName('Helvetica'),
      'Encoding': CosDictionary({
        'Differences': CosArray([
          const CosInteger(97),
          const CosName('alpha'),
          const CosName('summation'),
          const CosName('infinity'),
          const CosName('arrowright'),
        ]),
      }),
    });
    final info = PdfFontInfo.load(cos, font);
    expect(info.charFor(97), 'α');
    expect(info.charFor(98), '∑');
    expect(info.charFor(99), '∞');
    expect(info.charFor(100), '→');
  });
}
