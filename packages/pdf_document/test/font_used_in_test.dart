import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

final _fontBytes = File('test/fonts/DejaVuSans.ttf').readAsBytesSync();

PdfDocument _edited(void Function(PdfEditor) edit) {
  final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
  edit(editor);
  return PdfDocument.open(editor.save());
}

/// The first font dict in [annotation]'s normal-appearance /Resources.
CosDictionary _appearanceFontDict(PdfDocument doc, PdfAnnotation annotation) {
  final cos = doc.cos;
  final res =
      cos.resolve(annotation.normalAppearance!.dictionary['Resources'])
          as CosDictionary;
  final fonts = cos.resolve(res['Font']) as CosDictionary;
  return cos.resolve(fonts.entries.values.first) as CosDictionary;
}

void main() {
  group('PdfEmbeddedFont.usedIn', () {
    test('finds an embedded font in a free-text annotation appearance', () {
      final doc = _edited((e) => e.addFreeText(
            0,
            const PdfRect(72, 600, 300, 660),
            'Hello',
            font: PdfEmbeddedFont.parse(_fontBytes),
          ));
      final fonts = PdfEmbeddedFont.usedIn(doc);
      expect(fonts, hasLength(1));
      expect(fonts.single.familyName, contains('DejaVu'));
      // The reparsed program can map and measure real text.
      expect(fonts.single.glyphForRune('A'.codeUnitAt(0)), greaterThan(0));
    });

    test('a base-14-only document yields no embedded fonts', () {
      final doc = _edited((e) => e.addFreeText(
            0,
            const PdfRect(72, 600, 300, 660),
            'Plain',
            font: PdfStandardFont.helvetica,
          ));
      expect(PdfEmbeddedFont.usedIn(doc), isEmpty);
    });

    test('deduplicates the same face used on several pages', () {
      final font = PdfEmbeddedFont.parse(_fontBytes);
      final doc = _edited((e) {
        e.addFreeText(0, const PdfRect(72, 600, 300, 660), 'One', font: font);
        e.addFreeText(0, const PdfRect(72, 500, 300, 560), 'Two', font: font);
      });
      expect(PdfEmbeddedFont.usedIn(doc), hasLength(1));
    });

    test('an empty document yields no embedded fonts', () {
      expect(PdfEmbeddedFont.usedIn(PdfDocument.open(buildMultiPagePdf(1))),
          isEmpty);
    });
  });

  group('PdfEmbeddedFont.fromEmbeddedProgram', () {
    test('reparses a font already embedded in the document', () {
      final doc = _edited((e) => e.addFreeText(
            0,
            const PdfRect(72, 600, 300, 660),
            'Hi',
            font: PdfEmbeddedFont.parse(_fontBytes),
          ));
      final annotation = doc.page(0).annotations.single;
      final font = PdfEmbeddedFont.fromEmbeddedProgram(
          doc.cos, _appearanceFontDict(doc, annotation));
      expect(font, isNotNull);
      expect(font!.familyName, contains('DejaVu'));
    });

    test('canRender / glyphHasOutline gate a legible preview', () {
      final font = PdfEmbeddedFont.parse(_fontBytes);
      // A real letter has contours, so the font can preview its own name.
      expect(font.glyphHasOutline(font.glyphForRune('A'.codeUnitAt(0))), isTrue);
      expect(font.canRender('DejaVu Sans'), isTrue);
      // A character the font lacks entirely (unmapped) can't be rendered - the
      // same gate that, for a subset font, rejects a name whose glyphs were
      // stripped (verified against real subset PDFs). U+10FFFF is unassigned,
      // so no cmap maps it.
      expect(font.glyphForRune(0x10FFFF), 0);
      expect(font.canRender('\u{10FFFF}'), isFalse);
      // Out-of-range gids are given the benefit of the doubt, never suppressed.
      expect(font.glyphHasOutline(1 << 20), isTrue);
    });

    test('displayName leaves an untagged name untouched', () {
      // Guards against the subset-tag stripper mangling a normal family name;
      // DejaVu carries no `ABCDEF+` tag.
      final font = PdfEmbeddedFont.parse(_fontBytes);
      expect(font.familyName, contains('DejaVu'));
      expect(font.displayName, font.familyName);
    });

    test('returns null for a dict with no embedded program', () {
      final doc = _edited((e) => e.addFreeText(
            0,
            const PdfRect(72, 600, 300, 660),
            'Plain',
            font: PdfStandardFont.helvetica,
          ));
      final annotation = doc.page(0).annotations.single;
      expect(
          PdfEmbeddedFont.fromEmbeddedProgram(
              doc.cos, _appearanceFontDict(doc, annotation)),
          isNull);
    });
  });
}
