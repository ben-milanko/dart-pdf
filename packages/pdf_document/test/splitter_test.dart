import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

List<String> labels(Uint8List bytes) {
  final doc = PdfDocument.open(bytes);
  return [
    for (final page in doc.pages)
      RegExp(r'\((Page \d+)\)')
          .firstMatch(String.fromCharCodes(page.contentBytes()))!
          .group(1)!,
  ];
}

void main() {
  test('batch preserves range order, overlaps and independent outputs', () {
    final bytes = buildMultiPagePdf(5);
    final before = Uint8List.fromList(bytes);
    final parts = PdfSplitter.split(bytes, const [
      PdfPageRange(3, 4),
      PdfPageRange(0, 2),
      PdfPageRange(1, 1),
      PdfPageRange(3, 4),
    ]);
    expect(parts.map(labels), [
      ['Page 4', 'Page 5'],
      ['Page 1', 'Page 2', 'Page 3'],
      ['Page 2'],
      ['Page 4', 'Page 5'],
    ]);
    expect(identical(parts.first, parts.last), isFalse);
    final editor = PdfEditor(PdfDocument.open(parts.first))..removePage(0);
    expect(labels(editor.save()), ['Page 5']);
    expect(labels(parts.last), ['Page 4', 'Page 5']);
    expect(bytes, before);
  });

  test('single-range convenience includes both endpoints', () {
    expect(labels(PdfSplitter.splitRange(buildMultiPagePdf(4), 1, 2)),
        ['Page 2', 'Page 3']);
  });

  test('expression produces separate PDFs with one-based page numbers', () {
    final parts = PdfSplitter.splitExpression(
      buildMultiPagePdf(12),
      '1-3, 7, 10-12',
    );
    expect(parts.map(labels), [
      ['Page 1', 'Page 2', 'Page 3'],
      ['Page 7'],
      ['Page 10', 'Page 11', 'Page 12'],
    ]);
  });

  test('parser tolerates whitespace and preserves repeats and order', () {
    final ranges =
        PdfSplitter.parseRanges(' 3 - 4 , 1, 3-4, 2-2 ', pageCount: 4);
    expect(
        ranges.map((r) => (r.start, r.end)), [(2, 3), (0, 0), (2, 3), (1, 1)]);
  });

  for (final input in [
    '',
    ' ',
    ',',
    '1,',
    ',1',
    '1,,2',
    '0',
    '-1',
    '5',
    '1-5',
    '3-2',
    '1-',
    '-2',
    '1-2-3',
    '1.5',
    '1 2',
    'one',
    '1;2',
    '999999999999999999999999999999999999999999999'
  ]) {
    test('parser rejects "$input"', () {
      expect(() => PdfSplitter.parseRanges(input, pageCount: 4),
          throwsFormatException);
    });
  }

  test('invalid batches and single ranges are rejected without mutation', () {
    final doc = PdfDocument.open(buildMultiPagePdf(3));
    for (final ranges in <List<PdfPageRange>>[
      [],
      [const PdfPageRange(2, 1)],
      [const PdfPageRange(-1, 1)],
      [const PdfPageRange(0, 1), const PdfPageRange(1, 3)],
    ]) {
      expect(() => doc.extractPageRanges(ranges), throwsArgumentError);
    }
    expect(() => PdfSplitter.splitRange(buildMultiPagePdf(3), 0, 1000000000),
        throwsRangeError);
    expect(doc.pageCount, 3);
  });

  test('password is forwarded and each encrypted-source output is plain', () {
    final bytes = buildEncryptedPdf(revision: 4, userPassword: 'secret');
    expect(() => PdfSplitter.splitRange(bytes, 0, 0),
        throwsA(isA<CosPasswordException>()));
    for (final part in PdfSplitter.split(
        bytes, const [PdfPageRange(0, 0), PdfPageRange(0, 0)],
        password: 'secret')) {
      final doc = PdfDocument.open(part);
      expect(doc.cos.isEncrypted, isFalse);
      expect(String.fromCharCodes(doc.page(0).contentBytes()),
          contains('Hello, world!'));
    }
    expect(
        PdfDocument.open(
                PdfSplitter.splitExpression(bytes, '1', password: 'secret')
                    .single)
            .cos
            .isEncrypted,
        isFalse);
    expect(
        PdfDocument.open(
                PdfSplitter.splitRange(bytes, 0, 0, password: 'secret'))
            .cos
            .isEncrypted,
        isFalse);
  });
}
