import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// A one-page 612×792 PDF drawing each `(x, y, text)` line at 18pt
/// Helvetica.
Uint8List _textPdf(List<(int, int, String)> lines) {
  final content = lines
      .map((l) => 'BT /F1 18 Tf ${l.$1} ${l.$2} Td (${l.$3}) Tj ET')
      .join('\n');
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

PdfPageText _text(List<(int, int, String)> lines) =>
    PdfTextExtractor.extract(PdfDocument.open(_textPdf(lines)), 0);

void main() {
  test('tokenizes page text into words with bounds', () {
    final tokens =
        tokenizePageText(_text([(72, 720, 'the quick brown fox')]));
    expect(tokens.map((t) => t.text), ['the', 'quick', 'brown', 'fox']);
    for (final token in tokens) {
      expect(token.bounds, isNotNull,
          reason: 'every token should carry page-space bounds');
    }
    // bounds advance left-to-right across the line
    expect(tokens[0].bounds!.left, lessThan(tokens[3].bounds!.left));
  });

  test('detects a replaced word, leaving the rest equal', () {
    final before = _text([(72, 720, 'the quick brown fox')]);
    final after = _text([(72, 720, 'the quick red fox')]);
    final diff = PdfTextDiff.between(before, after);

    expect(diff.hasChanges, isTrue);
    expect(diff.deletedTokens.map((t) => t.text), ['brown']);
    expect(diff.insertedTokens.map((t) => t.text), ['red']);

    // 'the', 'quick' and 'fox' are unchanged — never flagged.
    final changed = {
      ...diff.deletedTokens.map((t) => t.text),
      ...diff.insertedTokens.map((t) => t.text),
    };
    expect(changed, isNot(contains('the')));
    expect(changed, isNot(contains('quick')));
    expect(changed, isNot(contains('fox')));

    // The replace is one hunk carrying both sides.
    expect(diff.hunks, hasLength(1));
    expect(diff.hunks.single.before.map((t) => t.text), ['brown']);
    expect(diff.hunks.single.after.map((t) => t.text), ['red']);
    expect(diff.hunks.single.isInsertion, isFalse);
    expect(diff.hunks.single.isDeletion, isFalse);
  });

  test('detects a pure insertion', () {
    final before = _text([(72, 720, 'alpha gamma')]);
    final after = _text([(72, 720, 'alpha beta gamma')]);
    final diff = PdfTextDiff.between(before, after);

    expect(diff.deletedTokens, isEmpty);
    expect(diff.insertedTokens.map((t) => t.text), ['beta']);
    expect(diff.hunks.single.isInsertion, isTrue);
  });

  test('detects a pure deletion', () {
    final before = _text([(72, 720, 'alpha beta gamma')]);
    final after = _text([(72, 720, 'alpha gamma')]);
    final diff = PdfTextDiff.between(before, after);

    expect(diff.insertedTokens, isEmpty);
    expect(diff.deletedTokens.map((t) => t.text), ['beta']);
    expect(diff.hunks.single.isDeletion, isTrue);
  });

  test('identical pages report no changes', () {
    final diff = PdfTextDiff.between(
      _text([(72, 720, 'same text here')]),
      _text([(72, 720, 'same text here')]),
    );
    expect(diff.hasChanges, isFalse);
    expect(diff.hunks, isEmpty);
  });
}
