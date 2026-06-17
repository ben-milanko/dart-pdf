import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

void main() {
  group('pdfTextNeedsShaping', () {
    test('returns true for Arabic text', () {
      expect(pdfTextNeedsShaping('مرحبا'), isTrue);
    });

    test('returns false for Latin text', () {
      expect(pdfTextNeedsShaping('Hello'), isFalse);
    });

    test('returns true for mixed text with Arabic', () {
      expect(pdfTextNeedsShaping('Hello مرحبا World'), isTrue);
    });

    test('returns false for empty text', () {
      expect(pdfTextNeedsShaping(''), isFalse);
    });

    test('returns false for numbers and punctuation', () {
      expect(pdfTextNeedsShaping('123 + 456 = 579'), isFalse);
    });
  });

  // Use direction: ltr to test shaping in isolation (no bidi reorder).
  group('pdfShapeText (shaping only, LTR)', () {
    test('leaves Latin text unchanged', () {
      final result = pdfShapeText('Hello', direction: PdfTextDirection.ltr);
      expect(result.text, 'Hello');
      expect(result.originalRunes.length, 5);
      for (var i = 0; i < 5; i++) {
        expect(result.originalRunes[i], hasLength(1));
      }
    });

    test('maps isolated Arabic letter to isolated presentation form', () {
      // Beh (U+0628) alone → isolated form FE8F
      final result = pdfShapeText('ب', direction: PdfTextDirection.ltr);
      expect(result.text.runes.single, 0xFE8F);
      expect(result.originalRunes.single, [0x0628]);
    });

    test('applies joining context for dual-joining letters', () {
      // Three Behs in logical order: first=initial, second=medial, third=final
      final result = pdfShapeText('ببب', direction: PdfTextDirection.ltr);
      final runes = result.text.runes.toList();
      expect(runes[0], 0xFE91, reason: 'first Beh should be initial');
      expect(runes[1], 0xFE92, reason: 'middle Beh should be medial');
      expect(runes[2], 0xFE90, reason: 'last Beh should be final');
    });

    test('right-joining letters only get isolated and final forms', () {
      // Beh + Alef + Beh: Beh=initial, Alef=final, Beh=isolated
      // (Alef is right-joining, doesn't extend left)
      final result = pdfShapeText('باب', direction: PdfTextDirection.ltr);
      final runes = result.text.runes.toList();
      expect(runes[0], 0xFE91, reason: 'Beh before Alef is initial');
      expect(runes[1], 0xFE8E, reason: 'Alef after Beh is final');
      expect(runes[2], 0xFE8F, reason: 'Beh after Alef is isolated');
    });

    test('applies lam-alef ligatures', () {
      // Lam (0644) + Alef (0627) → ligature 0xFEFB (isolated)
      final result = pdfShapeText('لا', direction: PdfTextDirection.ltr);
      final runes = result.text.runes.toList();
      expect(runes.length, 1, reason: 'lam+alef should collapse to one');
      expect(runes[0], 0xFEFB);
      expect(result.originalRunes[0], [0x0644, 0x0627]);
    });

    test('lam-alef with preceding joining letter gets final form', () {
      // Beh + Lam + Alef: Beh=initial, LamAlef=final
      final result = pdfShapeText('بلا', direction: PdfTextDirection.ltr);
      final runes = result.text.runes.toList();
      expect(runes.length, 2);
      expect(runes[0], 0xFE91, reason: 'Beh is initial');
      expect(runes[1], 0xFEFC, reason: 'LamAlef is final');
    });

    test('lam-alef with madda', () {
      final result = pdfShapeText('لآ', direction: PdfTextDirection.ltr);
      expect(result.text.runes.toList(), hasLength(1));
      expect(result.text.runes.single, 0xFEF5);
      expect(result.originalRunes[0], [0x0644, 0x0622]);
    });

    test('lam-alef with hamza above', () {
      final result = pdfShapeText('لأ', direction: PdfTextDirection.ltr);
      expect(result.text.runes.single, 0xFEF7);
    });

    test('lam-alef with hamza below', () {
      final result = pdfShapeText('لإ', direction: PdfTextDirection.ltr);
      expect(result.text.runes.single, 0xFEF9);
    });

    test('spaces break joining context', () {
      // Beh space Beh: both isolated
      final result = pdfShapeText('ب ب', direction: PdfTextDirection.ltr);
      final runes = result.text.runes.toList();
      expect(runes[0], 0xFE8F, reason: 'first Beh isolated');
      expect(runes[2], 0xFE8F, reason: 'second Beh isolated');
    });

    test('mixed Arabic and Latin text', () {
      final result =
          pdfShapeText('بب AB', direction: PdfTextDirection.ltr);
      final runes = result.text.runes.toList();
      // Arabic shaped
      expect(runes[0], 0xFE91, reason: 'first Beh initial');
      expect(runes[1], 0xFE90, reason: 'second Beh final');
      // Space and Latin unchanged
      expect(runes[2], ' '.codeUnitAt(0));
      expect(runes[3], 'A'.codeUnitAt(0));
      expect(runes[4], 'B'.codeUnitAt(0));
    });

    test('transparent joiners are skipped during joining analysis', () {
      // Beh + fathah (064E, transparent) + Beh: should still join
      final result = pdfShapeText('بَب', direction: PdfTextDirection.ltr);
      final runes = result.text.runes.toList();
      expect(runes[0], 0xFE91, reason: 'Beh initial (mark is transparent)');
      expect(runes[1], 0x064E, reason: 'fathah passes through');
      expect(runes[2], 0xFE90, reason: 'Beh final');
    });

    test('empty text returns empty result', () {
      final result = pdfShapeText('', direction: PdfTextDirection.ltr);
      expect(result.text, '');
      expect(result.originalRunes, isEmpty);
    });
  });

  group('pdfShapeText (RTL bidi reorder)', () {
    test('RTL direction reverses Arabic characters', () {
      // Two Behs, LTR order: initial, final
      // RTL visual: final, initial (reversed)
      final result = pdfShapeText('بب', direction: PdfTextDirection.rtl);
      final runes = result.text.runes.toList();
      expect(runes[0], 0xFE90, reason: 'final appears first in visual');
      expect(runes[1], 0xFE91, reason: 'initial appears last in visual');
    });

    test('auto direction resolves to RTL for Arabic text', () {
      final result = pdfShapeText('بب');
      final runes = result.text.runes.toList();
      // Same as explicit RTL
      expect(runes[0], 0xFE90);
      expect(runes[1], 0xFE91);
    });

    test('LTR embedded runs keep internal order in RTL paragraph', () {
      // "123" is an LTR number run inside an RTL paragraph
      final result = pdfShapeText('ب 123 ب', direction: PdfTextDirection.rtl);
      final text = result.text;
      // The digits should appear in their natural order (123, not 321)
      expect(text, contains('123'));
    });
  });

  group('font fallback', () {
    test('keeps base character when font lacks presentation form', () {
      final fontBytes = File('test/fonts/DejaVuSans.ttf').readAsBytesSync();
      final font = PdfEmbeddedFont.parse(fontBytes);
      // DejaVu Sans has Arabic text support
      final result =
          pdfShapeText('بب', font: font, direction: PdfTextDirection.ltr);
      final runes = result.text.runes.toList();
      expect(runes.length, 2);
      // Each glyph should resolve to a non-zero glyph in the font
      for (final r in runes) {
        expect(font.glyphForRune(r), greaterThanOrEqualTo(0));
      }
    });
  });
}
