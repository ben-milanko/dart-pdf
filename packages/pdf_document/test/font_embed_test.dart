import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  final fontBytes = File('test/fonts/DejaVuSans.ttf').readAsBytesSync();

  PdfDocument roundTrip(void Function(PdfEditor) edit) {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    edit(editor);
    return PdfDocument.open(editor.save());
  }

  String appearanceText(PdfDocument doc, PdfAnnotation annot) =>
      latin1.decode(doc.cos.decodeStreamData(annot.normalAppearance!));

  group('PdfEmbeddedFont.parse', () {
    test('reads names, metrics, and maps runes to glyphs', () {
      final font = PdfEmbeddedFont.parse(fontBytes);
      expect(font.familyName, contains('DejaVu'));
      expect(font.postScriptName, isNotEmpty);
      expect(font.ascent, greaterThan(0));
      // Real glyphs for common Latin letters.
      final gidA = font.glyphForRune('A'.codeUnitAt(0));
      expect(gidA, greaterThan(0));
      expect(font.advanceForGlyph(gidA), greaterThan(0));
      // Missing glyph (a private-use codepoint) maps to .notdef.
      expect(font.glyphForRune(0xE000), 0);
    });

    test('measures proportionally — W is wider than i', () {
      final font = PdfEmbeddedFont.parse(fontBytes);
      expect(font.measure('W', 100), greaterThan(font.measure('i', 100)));
      expect(font.measure('', 100), 0);
    });

    test('rejects non-font and WOFF data', () {
      expect(() => PdfEmbeddedFont.parse(Uint8List(4)), throwsArgumentError);
      final woff = Uint8List.fromList([0x77, 0x4F, 0x46, 0x46, 0, 0, 0, 0, 0, 0, 0, 0]);
      expect(() => PdfEmbeddedFont.parse(woff), throwsArgumentError);
    });
  });

  group('addFreeText with an embedded font', () {
    test('writes a Type0/CIDFontType2 Identity-H font with FontFile2', () {
      final doc = roundTrip((e) => e.addFreeText(
            0,
            const PdfRect(72, 600, 320, 680),
            'Hello',
            fontSize: 14,
            font: PdfEmbeddedFont.parse(fontBytes),
          ));
      final ft = doc.page(0).annotations.single;
      expect(ft.subtype, 'FreeText');

      // /DA references the generated embedded-font resource name.
      final da = doc.cos.resolve(ft.dict['DA']) as CosString;
      expect(da.text, contains('/F0 14 Tf'));

      // The appearance shows glyphs as a hex string, not a literal string.
      final content = appearanceText(doc, ft);
      expect(content, contains('/F0 14 Tf'));
      expect(content, contains('> Tj'));

      final resources = doc.cos
          .resolve(ft.normalAppearance!.dictionary['Resources']) as CosDictionary;
      final fonts = doc.cos.resolve(resources['Font']) as CosDictionary;
      final type0 = doc.cos.resolve(fonts['F0']) as CosDictionary;
      expect((doc.cos.resolve(type0['Subtype']) as CosName).value, 'Type0');
      expect((doc.cos.resolve(type0['Encoding']) as CosName).value, 'Identity-H');

      final descendants = doc.cos.resolve(type0['DescendantFonts']) as CosArray;
      final cidFont = doc.cos.resolve(descendants.items.single) as CosDictionary;
      expect((doc.cos.resolve(cidFont['Subtype']) as CosName).value,
          'CIDFontType2');
      expect((doc.cos.resolve(cidFont['CIDToGIDMap']) as CosName).value,
          'Identity');

      final descriptor =
          doc.cos.resolve(cidFont['FontDescriptor']) as CosDictionary;
      final fontFile = doc.cos.resolve(descriptor['FontFile2']) as CosStream;
      // The embedded program decompresses back to a TrueType file.
      final program = doc.cos.decodeStreamData(fontFile);
      expect(program.length,
          (doc.cos.resolve(fontFile.dictionary['Length1']) as CosInteger).value);
      expect(program.sublist(0, 4), fontBytes.sublist(0, 4)); // sfnt header
    });

    test('ToUnicode maps the shown glyphs back to their text', () {
      final font = PdfEmbeddedFont.parse(fontBytes);
      final doc = roundTrip((e) => e.addFreeText(
            0, const PdfRect(72, 600, 320, 680), 'Hi', font: font));
      final ft = doc.page(0).annotations.single;
      final resources = doc.cos
          .resolve(ft.normalAppearance!.dictionary['Resources']) as CosDictionary;
      final fonts = doc.cos.resolve(resources['Font']) as CosDictionary;
      final type0 = doc.cos.resolve(fonts['F0']) as CosDictionary;
      final toUnicode = doc.cos.resolve(type0['ToUnicode']) as CosStream;
      final cmap = latin1.decode(doc.cos.decodeStreamData(toUnicode));

      // The CMap lists the glyph id of 'H' mapped to U+0048.
      final gidH =
          font.glyphForRune('H'.codeUnitAt(0)).toRadixString(16).padLeft(4, '0');
      expect(cmap, contains('beginbfchar'));
      expect(cmap.toLowerCase(), contains('<$gidH> <0048>'));
    });

    test('non-Latin text round-trips through Identity-H', () {
      // U+00E9 (é) and U+03A9 (Ω) — beyond WinAnsi's reach for some, and
      // exactly what embedding buys over the base-14 path.
      final font = PdfEmbeddedFont.parse(fontBytes);
      final doc = roundTrip((e) => e.addFreeText(
            0, const PdfRect(72, 600, 320, 680), 'café Ω', font: font));
      final content = appearanceText(doc, doc.page(0).annotations.single);
      expect(content, contains('> Tj'));
      // The accented and Greek glyphs resolve to real (non-zero) ids.
      expect(font.glyphForRune(0x00E9), greaterThan(0));
      expect(font.glyphForRune(0x03A9), greaterThan(0));
    });
  });
}
