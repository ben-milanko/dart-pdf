import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_document/src/type0_font.dart';
import 'package:test/test.dart';

import 'content_edit_type0_test.dart' show buildType0Pdf;

void main() {
  // A cos to resolve direct objects against; decode() only calls resolve
  // (identity for direct objects) and decodeStreamData.
  final cos = PdfDocument.open(buildType0Pdf('A', _dejaVu())).cos;

  CosStream toUnicode(String cmapBody) {
    final bytes = latin1.encode(cmapBody);
    return CosStream(
        CosDictionary({'Length': CosInteger(bytes.length)}),
        Uint8List.fromList(bytes));
  }

  group('Type0Font.decode on a synthetic font dictionary', () {
    test('reads code -> text from /ToUnicode and code -> width from /W', () {
      final cidFont = CosDictionary({
        'Subtype': const CosName('CIDFontType2'),
        // 65 -> 600 (as `c [w]`), 66..67 -> 700 (as `cFirst cLast w`)
        'W': CosArray([
          CosInteger(65),
          CosArray([CosInteger(600)]),
          CosInteger(66),
          CosInteger(67),
          CosInteger(700),
        ]),
        'DW': CosInteger(250),
      });
      final fontDict = CosDictionary({
        'Subtype': const CosName('Type0'),
        'Encoding': const CosName('Identity-H'),
        'DescendantFonts': CosArray([cidFont]),
        'ToUnicode': toUnicode(
          'beginbfchar\n'
          '<0041> <0041>\n' // 65 -> 'A'
          '<0042> <0042>\n' // 66 -> 'B'
          'endbfchar\n',
        ),
      });

      final font = Type0Font.decode(cos, fontDict);

      expect(font.codeToText[0x41], 'A');
      expect(font.codeToText[0x42], 'B');
      expect(font.widthOf(65), 600);
      expect(font.widthOf(66), 700);
      expect(font.widthOf(67), 700);
      expect(font.widthOf(99), 250, reason: 'falls back to /DW');
      expect(font.canEdit, isFalse, reason: 'decode-only, no program');
    });

    test('a bfrange with a base increments the trailing code unit', () {
      final fontDict = CosDictionary({
        'Subtype': const CosName('Type0'),
        'Encoding': const CosName('Identity-H'),
        'DescendantFonts': CosArray([
          CosDictionary({'Subtype': const CosName('CIDFontType2')})
        ]),
        'ToUnicode': toUnicode(
          'beginbfrange\n<0010> <0012> <0041>\nendbfrange\n',
        ),
      });

      final font = Type0Font.decode(cos, fontDict);
      expect(font.codeToText[0x10], 'A');
      expect(font.codeToText[0x11], 'B');
      expect(font.codeToText[0x12], 'C');
      expect(font.widthOf(0x10), 1000, reason: 'no /W or /DW -> 1000');
    });

    test('a missing /ToUnicode and /W yield empty maps, never null', () {
      final font = Type0Font.decode(
          cos, CosDictionary({'Subtype': const CosName('Type0')}));
      expect(font.codeToText, isEmpty);
      expect(font.widthOf(1), 1000);
    });
  });

  group('Type0Font.forEditing eligibility gate', () {
    CosDictionary type0(Map<String, CosObject> overrides) => CosDictionary({
          'Subtype': const CosName('Type0'),
          'Encoding': const CosName('Identity-H'),
          'ToUnicode': toUnicode('beginbfchar\n<0041> <0041>\nendbfchar\n'),
          'DescendantFonts': CosArray([
            CosDictionary({'Subtype': const CosName('CIDFontType2')})
          ]),
          ...overrides,
        });

    test('rejects a non-Identity-H encoding', () {
      expect(
          Type0Font.forEditing(
              cos, type0({'Encoding': const CosName('UniGB-UCS2-H')})),
          isNull);
    });

    test('rejects a CIDFontType0 (CFF) descendant', () {
      expect(
          Type0Font.forEditing(
              cos,
              type0({
                'DescendantFonts': CosArray([
                  CosDictionary({'Subtype': const CosName('CIDFontType0')})
                ])
              })),
          isNull);
    });

    test('rejects a stream /CIDToGIDMap (code != gid)', () {
      expect(
          Type0Font.forEditing(
              cos,
              type0({
                'DescendantFonts': CosArray([
                  CosDictionary({
                    'Subtype': const CosName('CIDFontType2'),
                    'CIDToGIDMap': CosStream(
                        CosDictionary({'Length': CosInteger(0)}),
                        Uint8List(0)),
                  })
                ])
              })),
          isNull);
    });

    test('rejects a missing embedded program (no descriptor)', () {
      // the descendant is CIDFontType2 and Identity-H, but there is no font
      // program to encode against, so it is not editable.
      expect(Type0Font.forEditing(cos, type0(const {})), isNull);
    });

    test('accepts a real Identity-H / CIDFontType2 embedded composite', () {
      final doc = PdfDocument.open(buildType0Pdf('Hello', _dejaVu()));
      final fontDict = _fontDictOf(doc);
      final font = Type0Font.forEditing(doc.cos, fontDict);
      expect(font, isNotNull);
      expect(font!.canEdit, isTrue);
    });
  });

  group('Type0Font glyph recording and /W + /ToUnicode merge', () {
    // The win: this is testable in isolation - record a glyph and commit the
    // font dict, with no full page rewrite and no re-parsing of saved bytes.
    test('recordGlyph + commitFontDict writes the new /W entry and mapping',
        () {
      final doc = PdfDocument.open(buildType0Pdf('Hello', _dejaVu()));
      final fontDict = _fontDictOf(doc);
      final cidFont = _cidFontOf(doc);
      final font = Type0Font.forEditing(doc.cos, fontDict)!;

      // 'W' (U+0057) is not in "Hello"; DejaVu carries its glyph.
      final gid = font.glyphForRune('W'.codeUnitAt(0));
      expect(gid, isNonZero);
      final width = font.recordGlyph(gid, 'W'.codeUnitAt(0));
      expect(width, font.advanceForGlyph(gid));
      expect(font.isDirty, isTrue);

      font.commitFontDict(CosIncrementalUpdater(doc.cos));

      // /W now carries the recorded glyph's real advance...
      final w = _parseW(doc, cidFont);
      expect(w[gid], font.advanceForGlyph(gid));
      // ...and /ToUnicode maps its code to U+0057.
      final src = gid.toRadixString(16).padLeft(4, '0');
      final toUni = latin1.decode(
          doc.cos.decodeStreamData(
              doc.cos.resolve(fontDict['ToUnicode']) as CosStream),
          allowInvalid: true);
      expect(toUni.toLowerCase(), contains('<$src> <0057>'));
    });

    test('recordGlyph is idempotent for a glyph already mapped correctly', () {
      final doc = PdfDocument.open(buildType0Pdf('Hi', _dejaVu()));
      final font = Type0Font.forEditing(doc.cos, _fontDictOf(doc))!;
      final gid = font.glyphForRune('H'.codeUnitAt(0));
      font.recordGlyph(gid, 'H'.codeUnitAt(0)); // already in "Hi"
      expect(font.isDirty, isFalse, reason: 'no new glyph introduced');
    });

    test('encodeIdentity returns null when the font lacks a glyph', () {
      final doc = PdfDocument.open(buildType0Pdf('Hi', _dejaVu()));
      final font = Type0Font.forEditing(doc.cos, _fontDictOf(doc))!;
      // U+4E2D (中) is absent from DejaVu Sans.
      expect(font.encodeIdentity('中'), isNull);
      // a drawable string encodes to 2-byte Identity-H codes.
      final encoded = font.encodeIdentity('Hi');
      expect(encoded, isNotNull);
      expect(encoded!.bytes.length, 4);
    });
  });
}

Uint8List _dejaVu() => File('test/fonts/DejaVuSans.ttf').readAsBytesSync();

CosDictionary _fontDictOf(PdfDocument doc) {
  final fonts = doc.cos.resolve(doc.page(0).resources['Font']) as CosDictionary;
  return doc.cos.resolve(fonts['F0']) as CosDictionary;
}

CosDictionary _cidFontOf(PdfDocument doc) {
  final type0 = _fontDictOf(doc);
  final desc = doc.cos.resolve(type0['DescendantFonts']) as CosArray;
  return doc.cos.resolve(desc.items.first) as CosDictionary;
}

Map<int, double> _parseW(PdfDocument doc, CosDictionary cidFont) {
  final map = <int, double>{};
  final w = doc.cos.resolve(cidFont['W']);
  if (w is! CosArray) return map;
  final items = w.items;
  double num(CosObject o) =>
      o is CosInteger ? o.value.toDouble() : (o is CosReal ? o.value : 0);
  var i = 0;
  while (i < items.length) {
    final first = doc.cos.resolve(items[i]);
    if (first is! CosInteger || i + 1 >= items.length) {
      i++;
      continue;
    }
    final next = doc.cos.resolve(items[i + 1]);
    if (next is CosArray) {
      var cid = first.value;
      for (final wv in next.items) {
        map[cid++] = num(doc.cos.resolve(wv));
      }
      i += 2;
    } else {
      i++;
    }
  }
  return map;
}
