// PdfDocument.openSource: opening documents from an asynchronous byte source
// with page-level semantics intact.

import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  test('opens a one-page document and reads its page tree', () async {
    final doc =
        await PdfDocument.openSource(PdfBytesByteSource(buildClassicPdf()));
    expect(doc.pageCount, 1);
    final page = doc.page(0);
    expect(page.mediaBox, const PdfRect(0, 0, 612, 792));
    expect(page.resources.containsKey('Font'), isTrue);
  });

  test('opens a multi-page document with the right page count', () async {
    final doc =
        await PdfDocument.openSource(PdfBytesByteSource(buildMultiPagePdf(7)));
    expect(doc.pageCount, 7);
  });

  test('sparse preview exposes only its covered pages', () async {
    final doc = await PdfDocument.openSource(
      PdfBytesByteSource(buildMultiPagePdf(80)),
      options: const PdfSourceLoadOptions(
        firstPaintPages: 1,
        completeFirstPaintPageTree: false,
        headWindow: 64,
        tailWindow: 200,
        xrefWindow: 4096,
      ),
    );

    expect(doc.pageCount, 1);
    expect(doc.page(0).mediaBox.width, greaterThan(0));
    expect(() => doc.page(1), throwsRangeError);
  });

  test('reads page content through the source', () async {
    final doc =
        await PdfDocument.openSource(PdfBytesByteSource(buildClassicPdf()));
    final content = String.fromCharCodes(doc.page(0).contentBytes());
    expect(content, contains('Hello, world!'));
  });

  test('falls back cleanly for an unknown-length source', () async {
    final doc = await PdfDocument.openSource(
        _UnknownLengthSource(buildMultiPagePdf(3)));
    expect(doc.pageCount, 3);
  });

  test('full-download fallback does not keep the preview page-count hint',
      () async {
    final doc = await PdfDocument.openSource(
      _UnknownLengthSource(buildMultiPagePdf(3)),
      options: const PdfSourceLoadOptions(
        firstPaintPages: 1,
        completeFirstPaintPageTree: false,
      ),
    );

    expect(doc.pageCount, 3,
        reason: 'the fallback downloaded the complete page tree');
    expect(doc.page(2).mediaBox.width, greaterThan(0));
  });
}

/// A source that reports no length, forcing the sequential-download fallback.
class _UnknownLengthSource implements PdfByteSource {
  _UnknownLengthSource(this._bytes);
  final Uint8List _bytes;

  @override
  Future<int?> get length async => null;

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async {
    final s = start < 0 ? 0 : (start > _bytes.length ? _bytes.length : start);
    final e = endExclusive < s
        ? s
        : (endExclusive > _bytes.length ? _bytes.length : endExclusive);
    return Uint8List.sublistView(_bytes, s, e);
  }

  @override
  Future<void> close() async {}
}
