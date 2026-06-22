import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

/// Builds a one-page PDF that draws [text] with an embedded composite
/// (/Type0, Identity-H, CIDFontType2) font built from [fontBytes].
Uint8List buildType0Pdf(String text, Uint8List fontBytes) {
  final font = PdfEmbeddedFont.parse(fontBytes);
  final hex = font.encodeHex(text); // records the glyphs for /W and /ToUnicode
  final builder = CosDocumentBuilder();

  final content = latin1.encode('BT /F0 24 Tf 72 700 Td <$hex> Tj ET');
  final contentRef = builder.add(CosStream(
      CosDictionary({'Length': CosInteger(content.length)}),
      Uint8List.fromList(content)));

  // buildResource registers the descendant font, descriptor, program and
  // ToUnicode through builder.add and returns { F0: <Type0 dict> }. Register
  // the Type0 dict itself indirectly, as real producers do.
  final type0Dict = font.buildResource(builder.add)['F0']!;
  final fontRef = builder.add(type0Dict);

  final pageDict = CosDictionary({
    'Type': const CosName('Page'),
    'MediaBox': CosArray(const [
      CosInteger(0),
      CosInteger(0),
      CosInteger(612),
      CosInteger(792),
    ]),
    'Contents': contentRef,
    'Resources': CosDictionary({
      'Font': CosDictionary({'F0': fontRef})
    }),
  });
  final pageRef = builder.add(pageDict);
  final pagesRef = builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray([pageRef]),
    'Count': const CosInteger(1),
  }));
  pageDict['Parent'] = pagesRef;
  final catalogRef = builder
      .add(CosDictionary({'Type': const CosName('Catalog'), 'Pages': pagesRef}));
  return builder.build(root: catalogRef);
}

/// The 2-byte show codes (glyph ids, Identity-H) of the first text run on
/// page [index].
List<int> showCodes(PdfDocument doc, [int index = 0]) {
  final codes = <int>[];
  for (final op in PdfPageElements.of(doc, index).operations) {
    void addString(Uint8List bytes) {
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        codes.add((bytes[i] << 8) | bytes[i + 1]);
      }
    }

    if (op.operator == 'Tj' &&
        op.operands.isNotEmpty &&
        op.operands[0] is CosString) {
      addString((op.operands[0] as CosString).bytes);
    } else if (op.operator == 'TJ' &&
        op.operands.isNotEmpty &&
        op.operands[0] is CosArray) {
      for (final item in (op.operands[0] as CosArray).items) {
        if (item is CosString) addString(item.bytes);
      }
    }
  }
  return codes;
}

/// The numeric kern adjustments inside the first TJ array on page [index].
List<double> showKerns(PdfDocument doc, [int index = 0]) {
  final kerns = <double>[];
  for (final op in PdfPageElements.of(doc, index).operations) {
    if (op.operator == 'TJ' &&
        op.operands.isNotEmpty &&
        op.operands[0] is CosArray) {
      for (final item in (op.operands[0] as CosArray).items) {
        if (item is CosInteger) kerns.add(item.value.toDouble());
        if (item is CosReal) kerns.add(item.value);
      }
    }
  }
  return kerns;
}

CosDictionary cidFontOf(PdfDocument doc) {
  final fonts = doc.cos.resolve(doc.page(0).resources['Font']) as CosDictionary;
  final type0 = doc.cos.resolve(fonts['F0']) as CosDictionary;
  final desc = doc.cos.resolve(type0['DescendantFonts']) as CosArray;
  return doc.cos.resolve(desc.items.first) as CosDictionary;
}

String toUnicodeOf(PdfDocument doc) {
  final fonts = doc.cos.resolve(doc.page(0).resources['Font']) as CosDictionary;
  final type0 = doc.cos.resolve(fonts['F0']) as CosDictionary;
  final stream = doc.cos.resolve(type0['ToUnicode']) as CosStream;
  return latin1.decode(doc.cos.decodeStreamData(stream), allowInvalid: true);
}

void main() {
  final fontBytes = File('test/fonts/DejaVuSans.ttf').readAsBytesSync();
  final liberationBytes =
      File('test/fonts/LiberationSans-Regular.ttf').readAsBytesSync();
  final font = PdfEmbeddedFont.parse(fontBytes);

  /// Expected Identity-H codes (= glyph ids) for [text] in DejaVuSans.
  List<int> gidsOf(String text) {
    final fresh = PdfEmbeddedFont.parse(fontBytes);
    final hex = fresh.encodeHex(text);
    return [
      for (var i = 0; i + 3 < hex.length + 1; i += 4)
        int.parse(hex.substring(i, i + 4), radix: 16)
    ];
  }

  PdfDocument edit(Uint8List bytes, void Function(PdfEditor) e) {
    final editor = PdfEditor(PdfDocument.open(bytes));
    e(editor);
    return PdfDocument.open(editor.save());
  }

  group('replaceText on a /Type0 composite font', () {
    test('rewrites a word using glyphs already in the font', () {
      final pdf = buildType0Pdf('Hello world', fontBytes);
      late int n;
      final doc = edit(pdf, (e) => n = e.replaceText(0, 'Hello', 'Goodbye'));

      expect(n, 1);
      // the run now draws "Goodbye world" as Identity-H glyph codes
      expect(showCodes(doc), gidsOf('Goodbye world'));
    });

    test('can type a character not originally drawn on the page', () {
      // 'ö' is not in "Hello world" but DejaVuSans (embedded whole) carries
      // its glyph, so it can be typed in.
      final pdf = buildType0Pdf('Hello world', fontBytes);
      final doc = edit(pdf, (e) => e.replaceText(0, 'world', 'wörld'));

      expect(showCodes(doc), gidsOf('Hello wörld'));

      // the new glyph's advance is recorded in /W and its Unicode in
      // /ToUnicode, so the line measures and copies correctly elsewhere.
      final oGid = font.glyphForRune('ö'.codeUnitAt(0));
      final widths = _parseW(doc, cidFontOf(doc));
      expect(widths[oGid], font.advanceForGlyph(oGid));
      final src = oGid.toRadixString(16).padLeft(4, '0');
      expect(toUnicodeOf(doc).toLowerCase(),
          contains('<$src> <00f6>')); // U+00F6 = ö
    });

    test('inserts a width compensation when the replacement changes width', () {
      final pdf = buildType0Pdf('Hi there', fontBytes);
      // "Hi" -> "Wide" is wider; text follows, so a kern keeps it put.
      final doc = edit(pdf, (e) => e.replaceText(0, 'Hi', 'Wide'));
      expect(showCodes(doc), gidsOf('Wide there'));
      expect(showKerns(doc), isNotEmpty,
          reason: 'a compensating TJ adjustment holds the following text');
    });

    test('shrinking a word still reads correctly', () {
      final pdf = buildType0Pdf('Hello world', fontBytes);
      final doc = edit(pdf, (e) => e.replaceText(0, 'Hello', 'Hi'));
      expect(showCodes(doc), gidsOf('Hi world'));
    });

    test('a non-matching find leaves the run untouched', () {
      final pdf = buildType0Pdf('Hello world', fontBytes);
      late int n;
      final doc = edit(pdf, (e) => n = e.replaceText(0, 'absent', 'x'));
      expect(n, 0);
      expect(showCodes(doc), gidsOf('Hello world'));
    });

    test('deleting text (empty replacement) removes the glyphs', () {
      final pdf = buildType0Pdf('Hello world', fontBytes);
      final doc = edit(pdf, (e) => e.replaceText(0, 'Hello ', ''));
      expect(showCodes(doc), gidsOf('world'));
    });

    test('content elements decode Type0 text via /ToUnicode', () {
      // the content-edit UI reads PdfContentElement.text as both the prompt
      // value and the replaceText `find` — for Type0 it must be the real
      // string, not the 2-byte codes Latin-1-decoded.
      final doc = PdfDocument.open(buildType0Pdf('Hello world', fontBytes));
      final texts = PdfPageElements.of(doc, 0)
          .elements
          .where((e) => e.kind == PdfElementKind.text)
          .map((e) => e.text)
          .join();
      expect(texts, 'Hello world');
    });

    test('the content-tool flow (find via element.text) round-trips', () {
      final pdf = buildType0Pdf('Hello world', fontBytes);
      final el = PdfPageElements.of(PdfDocument.open(pdf), 0)
          .elements
          .firstWhere((e) => e.kind == PdfElementKind.text);
      expect(el.text, 'Hello world'); // what the UI shows / passes as `find`
      final doc = edit(pdf, (e) => e.replaceText(0, el.text!, 'Goodbye world'));
      expect(showCodes(doc), gidsOf('Goodbye world'));
    });

    String pageText(PdfDocument doc) => PdfPageElements.of(doc, 0)
        .elements
        .where((e) => e.kind == PdfElementKind.text)
        .map((e) => e.text)
        .join();

    test('falls back to a bundled font for a glyph the document font lacks',
        () {
      // Liberation Sans (the document font) lacks some glyphs DejaVu carries.
      final lib = PdfEmbeddedFont.parse(liberationBytes);
      int? missing;
      for (final r in const [0x2605, 0x263A, 0x4E2D, 0x0416, 0x2660, 0x266B]) {
        if (lib.glyphForRune(r) == 0 && font.glyphForRune(r) != 0) {
          missing = r;
          break;
        }
      }
      expect(missing, isNotNull, reason: 'need a rune only the fallback has');
      final ch = String.fromCharCode(missing!);
      final pdf = buildType0Pdf('Hello world', liberationBytes);

      // without a fallback, the undrawable replacement leaves the run alone
      late int n0;
      final doc0 = edit(pdf, (e) => n0 = e.replaceText(0, 'world', '${ch}rld'));
      expect(n0, 0);
      expect(pageText(doc0), 'Hello world');

      // with a fallback, the replacement is drawn in the fallback font
      final fallback = PdfEmbeddedFont.parse(fontBytes);
      late int n;
      final doc = edit(
          pdf,
          (e) => n = e.replaceText(0, 'world', '${ch}rld',
              fallbackFonts: [fallback]));
      expect(n, 1);

      // a new /Font resource holds the embedded fallback (Type0/Identity-H)
      final fonts =
          doc.cos.resolve(doc.page(0).resources['Font']) as CosDictionary;
      expect(fonts.entries.keys, contains('Fbk0'));
      final fb = doc.cos.resolve(fonts['Fbk0']) as CosDictionary;
      expect((doc.cos.resolve(fb['Subtype']) as CosName).value, 'Type0');

      // the content switches to the fallback for the replacement and the
      // text round-trips through both fonts' /ToUnicode
      final tfFonts = [
        for (final op in PdfPageElements.of(doc, 0).operations)
          if (op.operator == 'Tf' && op.operands.first is CosName)
            (op.operands.first as CosName).value
      ];
      expect(tfFonts, containsAll(['F0', 'Fbk0']));
      expect(pageText(doc), 'Hello ${ch}rld');
    });
  });
}

Map<int, double> _parseW(PdfDocument doc, CosDictionary cidFont) {
  final map = <int, double>{};
  final w = doc.cos.resolve(cidFont['W']);
  if (w is! CosArray) return map;
  final items = w.items;
  var i = 0;
  double num(CosObject o) =>
      o is CosInteger ? o.value.toDouble() : (o is CosReal ? o.value : 0);
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
