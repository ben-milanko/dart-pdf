@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// Each bundled substitute face and the standard-14 font it stands in for.
///
/// This is the contract the whole substitution scheme rests on: a page that
/// names one of the standard 14 carries no font program, so its advances come
/// from these AFM tables, and the renderer places every character at the pen
/// offset they produce. A face whose glyphs are narrower than the table says
/// does not merely look different - it opens white space inside words.
const _substitutes = <String, PdfStandardFont>{
  'TeXGyreHeros-Regular.otf': PdfStandardFont.helvetica,
  'TeXGyreHeros-Bold.otf': PdfStandardFont.helveticaBold,
  'TeXGyreHeros-Italic.otf': PdfStandardFont.helveticaOblique,
  'TeXGyreHeros-BoldItalic.otf': PdfStandardFont.helveticaBoldOblique,
  'TeXGyreTermes-Regular.otf': PdfStandardFont.times,
  'TeXGyreTermes-Bold.otf': PdfStandardFont.timesBold,
  'TeXGyreTermes-Italic.otf': PdfStandardFont.timesItalic,
  'TeXGyreTermes-BoldItalic.otf': PdfStandardFont.timesBoldItalic,
  'TeXGyreCursor-Regular.otf': PdfStandardFont.courier,
  'TeXGyreCursor-Bold.otf': PdfStandardFont.courierBold,
  'TeXGyreCursor-Italic.otf': PdfStandardFont.courierOblique,
  'TeXGyreCursor-BoldItalic.otf': PdfStandardFont.courierBoldOblique,
};

/// Code 39 is the one code whose glyph the AFM tables disagree about, because
/// the two standard encodings disagree: StandardEncoding - the default for a
/// base-14 font that declares no /Encoding - puts `quoteright` there, and
/// WinAnsiEncoding puts the narrower `quotesingle`. The checked-in tables were
/// taken from sources that split on it (Times-Roman and Times-Italic carry
/// quoteright, Times-Bold and Times-BoldItalic quotesingle), and the width fill
/// in `PdfFontInfo` is by code, so it cannot serve both. Accept either glyph
/// here rather than pin a convention this change does not settle.
const _quoteCode = 0x27;
const _quoteRight = 0x2019;

/// Calibri's own advances, per style, for WinAnsi codes 32-126.
///
/// Calibri is not one of the standard 14, so there is no AFM table to check
/// Carlito against - but a page that names it unembedded carries a /Widths
/// array, and that array *is* the contract: those are the offsets the renderer
/// places each character at. These tables were read out of the /Widths of a
/// Windows document printed through a GDI driver, merged across its pages;
/// -1 marks a code no page in it showed, which this test skips rather than
/// guess at.
///
/// Carlito matching them to the unit is what makes it substitutable. Falling
/// through to Heros instead put Helvetica's much wider advances on Calibri's
/// pen offsets - `C` 722 against 529, `s` 556 against 399 - and crowded every
/// glyph into the next.
const _calibriWidths = <String, List<int>>{
  'Regular': [
    226, -1, -1, 498, -1, 715, 682, 221, 303, 303, -1, 498, 250, 306, 252, //
    386, 507, 507, 507, 507, 507, 507, 507, 507, 507, 507, 268, 268, -1, 498,
    -1, 463, 894, 579, 544, 533, 615, 488, 459, 631, 623, 252, 319, 520, 420,
    855, 646, 662, 517, 673, 543, 459, 487, 642, 567, 890, 519, 487, 468, -1,
    -1, -1, -1, 498, -1, 479, 525, 423, 525, 498, 305, 471, 525, 229, 239, 455,
    229, 799, 525, 527, 525, 525, 349, 391, 335, 525, 452, 715, 433, 453, 395,
    -1, 460, -1, -1,
  ],
  'Bold': [
    226, -1, -1, -1, -1, -1, 705, -1, 312, 312, -1, 498, 258, 306, 267, 430, //
    507, 507, 507, 507, 507, 507, 507, 507, 507, 507, 276, -1, -1, -1, -1, -1,
    -1, 606, 561, 529, 630, 488, 459, 637, 631, 267, 331, 547, 423, 874, 659,
    676, 532, 686, 563, 473, 495, 653, 591, 906, 551, 520, -1, -1, -1, -1, -1,
    -1, -1, 494, 537, 418, 537, 503, 316, 474, 537, 246, 255, 480, 246, 813,
    537, 538, 537, 537, 355, 399, 347, 537, 473, 745, 459, 474, 397, -1, 475,
    -1, -1,
  ],
  'Italic': [
    226, -1, -1, -1, -1, -1, 682, -1, 303, 303, -1, -1, 250, 306, 252, -1, //
    507, 507, 507, 507, 507, 507, 507, 507, 507, 507, 268, -1, -1, -1, -1, -1,
    -1, 579, 544, 522, 615, -1, 459, -1, 623, 252, -1, -1, 420, 855, -1, 654,
    517, -1, 543, 452, 487, -1, -1, 890, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    514, 514, 416, 514, 478, 305, 514, 514, 229, 239, 455, 229, 791, 514, 513,
    514, -1, 343, 389, 335, 514, 446, 715, 433, 447, -1, -1, -1, -1, -1,
  ],
  'BoldItalic': [
    226, -1, -1, -1, -1, -1, -1, -1, 312, 312, -1, -1, 258, 306, -1, -1, 507, //
    507, 507, 507, 507, 507, 507, -1, 507, 507, 276, -1, -1, -1, -1, -1, -1,
    606, -1, 519, 630, 488, 459, 637, -1, 267, -1, 547, 423, 874, 656, 668,
    532, -1, 563, 465, 495, 653, -1, 907, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    528, 528, 412, 528, 491, 316, 528, -1, 246, 255, 480, 246, 804, 527, 527,
    528, -1, 352, 394, 347, 527, 469, 745, -1, 470, -1, -1, -1, -1, -1,
  ],
};

void main() {
  group('bundled metric-compatible substitutes', () {
    _substitutes.forEach((file, standard) {
      test('$file carries ${standard.baseFont} advances', () {
        final bytes = File('assets/fonts/$file').readAsBytesSync();
        final font = OpenTypeCffFont.parse(bytes);
        expect(font, isNotNull, reason: '$file is an OpenType CFF face');
        int advanceFor(int codePoint) {
          final gid = font!.gidForUnicode(codePoint);
          expect(gid, isNot(0),
              reason:
                  '$file has no glyph for U+${codePoint.toRadixString(16)}');
          final advance = font.advanceForGlyph(gid);
          expect(advance, isNotNull,
              reason: '$file advance for U+${codePoint.toRadixString(16)}');
          return (advance! * 1000).round();
        }

        for (var code = 32; code <= 126; code++) {
          final expected = standard.widthOf(code);
          if (code == _quoteCode) {
            expect(expected, anyOf(advanceFor(code), advanceFor(_quoteRight)),
                reason: '$file must draw the quote at code 39 in the width'
                    ' ${standard.baseFont} reserves for it');
            continue;
          }
          expect(advanceFor(code), expected,
              reason: '$file advance for ${String.fromCharCode(code)}'
                  ' (code $code) must match ${standard.baseFont}');
        }
      });
    });

    _calibriWidths.forEach((style, widths) {
      test('Carlito-$style.ttf carries Calibri advances', () {
        final bytes = File('assets/fonts/Carlito-$style.ttf').readAsBytesSync();
        final font = TrueTypeFont.parse(bytes);
        expect(font, isNotNull,
            reason: 'Carlito-$style.ttf is a TrueType face');
        var checked = 0;
        for (var code = 32; code <= 126; code++) {
          final expected = widths[code - 32];
          if (expected < 0) continue;
          final gid = font!.gidForUnicode(code);
          expect(gid, isNot(0),
              reason: 'Carlito-$style.ttf has no glyph for code $code');
          final advance = font.advanceForGlyph(gid);
          expect(advance, isNotNull,
              reason: 'Carlito-$style.ttf advance for code $code');
          expect((advance! * 1000).round(), expected,
              reason: 'Carlito-$style.ttf advance for'
                  ' ${String.fromCharCode(code)} (code $code) must match'
                  ' Calibri-$style');
          checked++;
        }
        // Guards the table itself: an all -1 column would pass vacuously.
        expect(checked, greaterThan(50),
            reason:
                'Calibri-$style reference table must cover the ASCII range');
      });
    });

    test('Adventor ships the upright weights the engine obliques', () {
      for (final file in const [
        'TeXGyreAdventor-Regular.otf',
        'TeXGyreAdventor-Bold.otf',
      ]) {
        expect(File('assets/fonts/$file').existsSync(), isTrue, reason: file);
      }
    });
  });
}
