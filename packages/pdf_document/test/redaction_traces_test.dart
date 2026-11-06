import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

/// What a burn leaves behind shouldn't trace what it removed: empty
/// graphics-state groups, empty text objects and the positioning stops of
/// removed lines go, and a word that loses any letter loses them all - while
/// the text that stays doesn't move.

const _helvetica = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
    '/Encoding /WinAnsiEncoding >>';

Uint8List _page(
  String content, {
  String resources = '/Font << /F1 5 0 R >>',
  List<String> extra = const [_helvetica],
}) =>
    _objects([
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
          '/Resources << $resources >> >>',
      _stream('', content),
      ...extra,
    ]);

String _stream(String dict, String data) =>
    '<< $dict /Length ${data.length} >>\nstream\n$data\nendstream';

Uint8List _objects(List<String> bodies) {
  final buffer = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < bodies.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${bodies[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer
    ..write('xref\n0 ${bodies.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final o in offsets) {
    buffer.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

/// Burns [rects] on page 0 of [pdf].
Uint8List _burn(Uint8List pdf, List<PdfRect> rects) =>
    (PdfEditor(PdfDocument.open(pdf))..addRedaction(0, rects)).burnRedactions();

String _content(Uint8List pdf, [int page = 0]) =>
    latin1.decode(PdfDocument.open(pdf).page(page).contentBytes());

/// [keep] draws where it did before the burn.
void _unmoved(Uint8List before, Uint8List after, List<String> keep) {
  final was = _textBounds(PdfDocument.open(before));
  final now = _textBounds(PdfDocument.open(after));
  for (final k in keep) {
    expect(now[k], isNotNull, reason: '$k was lost');
    expect(now[k]!.left, closeTo(was[k]!.left, 0.05), reason: '$k moved');
    expect(now[k]!.bottom, closeTo(was[k]!.bottom, 0.05), reason: '$k moved');
  }
}

Map<String, PdfRect> _textBounds(PdfDocument doc) => {
      for (final e in PdfPageElements.of(doc, 0).elements)
        if (e.text != null && e.bounds != null) e.text!: e.bounds!,
    };

void main() {
  const content =
      'q 0.92 0.94 1 rg 0.25 0.35 0.85 RG 1 w 100 600 50 20 re B Q\n'
      'BT /F1 12 Tf 72 700 Td (KEEPA) Tj 0 -60 Td (GONEB) Tj '
      '0 -60 Td (GONEC) Tj 0 -60 Td (KEEPD) Tj ET\n'
      'BT /F1 12 Tf 300 300 Td (GONEE) Tj ET\n';

  test('removed shapes and lines leave no state or stops behind', () {
    final before = PdfDocument.open(_page(content));
    final editor = PdfEditor(before)
      ..addRedaction(0, [
        const PdfRect(60, 570, 400, 650),
        const PdfRect(290, 290, 400, 320),
      ]);
    final after = PdfDocument.open(editor.burnRedactions());
    final text = latin1.decode(after.page(0).contentBytes());

    for (final gone in ['GONEB', 'GONEC', 'GONEE']) {
      expect(text, isNot(contains(gone)));
    }
    // the removed shape's colour and line state
    expect(text, isNot(contains('0.92')));
    expect(text, isNot(contains('0.85 RG')));
    // the stops of the removed lines, and the empty text object's position
    expect(text, isNot(contains('640')));
    expect(text, isNot(contains('580')));
    expect(text, isNot(contains('300 300')));
    // nor the width of the removed lines, as a kern nothing uses
    expect(text, isNot(contains('TJ')));

    // what stays doesn't move
    final was = _textBounds(before), now = _textBounds(after);
    for (final keep in ['KEEPA', 'KEEPD']) {
      expect(now[keep], isNotNull, reason: '$keep was lost');
      expect(now[keep]!.left, closeTo(was[keep]!.left, 0.01));
      expect(now[keep]!.bottom, closeTo(was[keep]!.bottom, 0.01));
    }
  });

  test('a word that loses a letter loses them all, under a wider fill', () {
    final doc = PdfDocument.open(
        _page('BT /F1 12 Tf 72 700 Td (the drives work) Tj ET\n'));
    // "the " is 20pt wide: the box covers only the d of drives
    final editor = PdfEditor(doc)
      ..addRedaction(0, [const PdfRect(92.5, 695, 97, 715)]);
    final after = PdfDocument.open(editor.burnRedactions());
    final text = latin1.decode(after.page(0).contentBytes());
    expect(text, isNot(contains('rives')));
    expect(text, contains('(the '));
    expect(text, contains(' work)'));
    // the box itself, and a fill over the letters taken beyond it
    expect(RegExp(r'\bre\b').allMatches(text).length, greaterThanOrEqualTo(2));
    final fills = RegExp(r'([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+) re')
        .allMatches(text)
        .map((m) => double.parse(m.group(1)!) + double.parse(m.group(3)!));
    // some fill reaches past the end of "drives" (x ~ 124)
    expect(fills.any((right) => right > 120), isTrue);
  });

  test('letter-by-letter removal is still available', () {
    final doc = PdfDocument.open(
        _page('BT /F1 12 Tf 72 700 Td (the drives work) Tj ET\n'));
    final editor = PdfEditor(doc)
      ..addRedaction(0, [const PdfRect(92.5, 695, 97, 715)]);
    final after = PdfDocument.open(editor.burnRedactions(wholeWords: false));
    expect(latin1.decode(after.page(0).contentBytes()), contains('rives'));
  });

  group('round 5', () {
    test('an emptied text object keeps the colour and state it set', () {
      final pdf = _page(
          'BT /F1 12 Tf 1 0 0 rg /G1 gs 72 700 Td (SECRET) Tj ET\n'
          'BT 72 600 Td (KEEP) Tj ET\n',
          resources:
              '/Font << /F1 5 0 R >> /ExtGState << /G1 << /ca 0.2 >> >>');
      final text = _content(_burn(pdf, [const PdfRect(60, 690, 200, 720)]));
      expect(text, isNot(contains('SECRET')));
      // KEEP is still red and translucent
      expect(text, contains('1 0 0 rg'));
      expect(text, contains('/G1 gs'));
    });

    test('the leading a Q restores is the one a T* folds with', () {
      final pdf = _page('q BT 20 TL /F1 12 Tf 72 700 Td (KEEPA) Tj ET Q\n'
          'BT /F1 12 Tf 72 500 Td T* (KEEPB) Tj ET\n'
          'BT /F1 12 Tf 300 300 Td (GONE) Tj ET\n');
      final out = _burn(pdf, [const PdfRect(290, 290, 400, 320)]);
      _unmoved(pdf, out, ['KEEPA', 'KEEPB']);
    });

    test('no gap after the last kept letter records the removed width', () {
      final pdf = _page('BT /F1 12 Tf 72 700 Td (Name: SECRETVALUE) Tj ET\n');
      final text = _content(_burn(pdf, [const PdfRect(110, 690, 300, 720)]));
      expect(text, contains('(Name:'));
      expect(RegExp(r'\)\s*-?\d').hasMatch(text), isFalse,
          reason: 'a kern follows the kept text:\n$text');
    });

    test('tagged lines leave no stops or kerns of a removed line', () {
      final pdf = _page('BT /F1 12 Tf /P <</MCID 0>> BDC 72 700 Td (KEEPA) Tj '
          'EMC /P <</MCID 1>> BDC 0 -37 Td (SECRET) Tj EMC '
          '/P <</MCID 2>> BDC 0 -41 Td (KEEPB) Tj EMC ET\n');
      final out = _burn(pdf, [const PdfRect(60, 655, 200, 675)]);
      final text = _content(out);
      expect(text, isNot(contains('-37')));
      expect(text, isNot(contains('TJ')));
      expect(text, isNot(contains('MCID 1')));
      _unmoved(pdf, out, ['KEEPA', 'KEEPB']);
    });

    test('a stop in front of a font change folds too', () {
      final pdf = _page('BT /F1 12 Tf 72 700 Td (KEEPA) Tj 0 -37 Td /F1 11 Tf '
          '(SECRET) Tj 0 -41 Td /F1 12 Tf (KEEPB) Tj ET\n');
      final out = _burn(pdf, [const PdfRect(60, 655, 200, 675)]);
      expect(_content(out), isNot(contains('-37')));
      _unmoved(pdf, out, ['KEEPA', 'KEEPB']);
    });

    test('spacing, scaling, rise and quotes survive a fold', () {
      final pdf = _page('BT /F1 12 Tf 14 TL 72 700 Td (KEEPA) Tj 2 Tc 0 -20 Td '
          "(GONE) Tj 120 Tz 3 Ts 0 -20 Td T* (KEEPB) Tj (KEEPC) ' "
          '1 2 (KEEPD) " ET\n');
      final out = _burn(pdf, [const PdfRect(60, 675, 200, 690)]);
      _unmoved(pdf, out, ['KEEPA', 'KEEPB', 'KEEPC', 'KEEPD']);
    });

    test('kept text drawn at a tiny scale does not move', () {
      final pdf = _page('q 0.0000004 0 0 0.0000004 0 0 cm BT /F1 30000000 Tf '
          '180000000 1750000000 Td (KEEP) Tj ET Q\n'
          'BT /F1 12 Tf 300 300 Td (GONE) Tj ET\n');
      final out = _burn(pdf, [const PdfRect(290, 290, 400, 320)]);
      _unmoved(pdf, out, ['KEEP']);
    });

    test('a removed shape in marked content leaves no colour', () {
      final pdf =
          _page('q /Artifact BMC 0.913 0.27 0.11 rg 100 600 50 20 re f EMC Q\n'
              'BT /F1 12 Tf 72 700 Td (KEEP) Tj ET\n');
      final text = _content(_burn(pdf, [const PdfRect(90, 590, 200, 630)]));
      expect(text, isNot(contains('0.913')));
      expect(text, isNot(contains('Artifact')));
    });

    test('a group whose text is removed leaves no colour', () {
      final pdf =
          _page('q 0.913 0.27 0.11 rg BT /F1 12 Tf 72 600 Td (SECRET) Tj ET Q\n'
              'BT /F1 12 Tf 72 700 Td (KEEP) Tj ET\n');
      final text = _content(_burn(pdf, [const PdfRect(60, 590, 200, 630)]));
      expect(text, isNot(contains('0.913')));
    });

    test('a word grown beyond the box gets one fill, not one per letter', () {
      final pdf = _page('BT /F1 12 Tf 72 700 Td (the drives work) Tj ET\n');
      final text = _content(_burn(pdf, [const PdfRect(92.5, 695, 97, 715)]));
      // the box, and one fill over "drives"
      expect(RegExp(r'\bre\b').allMatches(text), hasLength(2), reason: text);
    });

    test('glyphs without Unicode still make up words', () {
      final pdf = _page(
          'BT /F2 20 Tf 100 700 Td <002a002b002c002d002e002f> Tj ET',
          resources: '/Font << /F2 5 0 R >>',
          extra: [
            '<< /Type /Font /Subtype /Type0 /BaseFont /X '
                '/Encoding /Identity-H /DescendantFonts [6 0 R] >>',
            '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /X '
                '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) '
                '/Supplement 0 >> /DW 500 >>',
          ]);
      final text = _content(_burn(pdf, [const PdfRect(101, 695, 109, 720)]));
      expect(text.toLowerCase(), isNot(contains('002b')));
    });

    test('words taken from a kept appearance are filled on its own page', () {
      final pdf = _objects([
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
            '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> '
            '/Annots [8 0 R] >>',
        _stream('', 'BT /F1 12 Tf 72 300 Td (KEEP0) Tj ET'),
        _helvetica,
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
            '/Contents 7 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
        _stream('', 'BT /F1 12 Tf 400 100 Td (GONE1) Tj ET'),
        '<< /Type /Annot /Subtype /Square /Rect [100 100 200 120] /F 4 '
            '/AP << /N 9 0 R >> >>',
        _stream(
            '/Type /XObject /Subtype /Form /BBox [0 0 100 20] '
                '/Resources << /Font << /F1 5 0 R >> >>',
            'BT /F1 12 Tf 0 5 Td (ABCDEFGHIJKLMNOPQRSTUV) Tj ET'),
      ]);
      final editor = PdfEditor(PdfDocument.open(pdf))
        ..addRedaction(0, [const PdfRect(230, 95, 240, 125)])
        ..addRedaction(1, [const PdfRect(390, 90, 460, 120)]);
      final out = editor.burnRedactions();
      final re = RegExp(r'\bre\b');
      expect(re.allMatches(_content(out, 0)).length, 2);
      expect(re.allMatches(_content(out, 1)).length, 1);
    });

    test('a top-level leading folds into a later T*', () {
      final pdf = _page('20 TL BT /F1 12 Tf 72 700 Td (KEEPA) Tj T* (GONE) Tj '
          'T* (KEEPB) Tj ET\n');
      final out = _burn(pdf, [const PdfRect(60, 675, 200, 690)]);
      expect(_content(out), isNot(contains('GONE')));
      _unmoved(pdf, out, ['KEEPA', 'KEEPB']);
    });

    test('an emptied text object keeps the leading its TD and TL set', () {
      for (final setter in ['0 -15 TD', '15 TL']) {
        final pdf = _page('BT /F1 12 Tf 300 300 Td $setter (GONE) Tj ET\n'
            'BT /F1 12 Tf 72 700 Td (KEEPA) Tj T* (KEEPB) Tj ET\n');
        final out = _burn(pdf, [const PdfRect(290, 270, 400, 320)]);
        final text = _content(out);
        expect(text, isNot(contains('GONE')));
        expect(text, isNot(contains('300')), reason: setter);
        _unmoved(pdf, out, ['KEEPA', 'KEEPB']);
      }
    });

    test('a folded TD still sets the leading', () {
      final pdf = _page('BT /F1 12 Tf 72 700.5 Td (KEEPA) Tj 0 -20 TD '
          '(GONE) Tj T* (KEEPB) Tj T* (KEEPC) Tj ET\n');
      final out = _burn(pdf, [const PdfRect(60, 675, 200, 690)]);
      expect(_content(out), isNot(contains('GONE')));
      _unmoved(pdf, out, ['KEEPA', 'KEEPB', 'KEEPC']);
    });

    test('marked content an emptied object opens stays balanced', () {
      final pdf = _page('BT /F1 12 Tf /Span <</MCID 0>> BDC 300 300 Td (GONE) '
          'Tj ET EMC BT /F1 12 Tf 72 700 Td (KEEP) Tj ET\n');
      final text = _content(_burn(pdf, [const PdfRect(290, 290, 400, 320)]));
      expect(text, isNot(contains('GONE')));
      final ops =
          ContentStreamParser.parse(Uint8List.fromList(latin1.encode(text)))
              .map((o) => o.operator)
              .toList();
      expect(ops.where((o) => o == 'BDC').length,
          ops.where((o) => o == 'EMC').length);
    });

    test('a kept TJ loses only its trailing kern', () {
      final pdf = _page('BT /F1 12 Tf 72 700 Td '
          '[(KEEPA) -1000 (KEEPB) -1000 (SECRETX)] TJ ET\n');
      final text = _content(_burn(pdf, [const PdfRect(186, 690, 300, 720)]));
      // the kern between kept strings stays: KEEPB is where it was
      expect(text, contains('[(KEEPA) -1000 (KEEPB)] TJ'));
    });

    test('unterminated groups and text objects are left as they are', () {
      final pdf = _page('BT /F1 12 Tf 300 300 Td (GONE) Tj ET\n'
          'q 0.5 g BT /F1 12 Tf 72 700 Td (KEEP) Tj');
      final text = _content(_burn(pdf, [const PdfRect(290, 290, 400, 320)]));
      expect(text, isNot(contains('GONE')));
      expect(text, contains('(KEEP) Tj'));
    });
  });
}
