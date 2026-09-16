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
