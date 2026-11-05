import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

/// What a burn leaves behind shouldn't trace what it removed: empty
/// graphics-state groups, empty text objects and the positioning stops of
/// removed lines go, and a word that loses any letter loses them all - while
/// the text that stays doesn't move.

Uint8List _page(String content) {
  final bodies = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/Encoding /WinAnsiEncoding >>',
  ];
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
}
