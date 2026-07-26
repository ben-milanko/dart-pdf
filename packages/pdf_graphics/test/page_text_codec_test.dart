// The worker → UI-isolate wire codec for extracted page text (#396: off-thread
// text extraction). A PdfPageText serialized to bytes and read back must carry
// the same page text and per-run geometry, so search/hover on the main isolate
// behave identically whether the extraction ran locally or in a worker.
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void _expectRunEquals(PdfExtractedRun a, PdfExtractedRun b) {
  expect(b.text, a.text);
  expect(b.startIndex, a.startIndex);
  expect(b.mcid, a.mcid);
  expect(b.width, a.width);
  expect(b.isRightToLeft, a.isRightToLeft);
  expect([b.transform.a, b.transform.b, b.transform.c, b.transform.d,
    b.transform.e, b.transform.f],
      [a.transform.a, a.transform.b, a.transform.c, a.transform.d,
    a.transform.e, a.transform.f]);
  expect([b.bounds.left, b.bounds.bottom, b.bounds.right, b.bounds.top],
      [a.bounds.left, a.bounds.bottom, a.bounds.right, a.bounds.top]);
}

void main() {
  test('a synthetic page text round-trips field for field', () {
    const page = PdfPageText(
      pageIndex: 3,
      text: 'Héllo\nworld',
      runs: [
        PdfExtractedRun(
          text: 'Héllo',
          startIndex: 0,
          transform: PdfMatrix(12, 0, 0, 12, 72, 720),
          width: 3.2,
          bounds: PdfRect(72, 708, 132, 732),
          mcid: 4,
        ),
        PdfExtractedRun(
          text: 'world',
          startIndex: 6,
          transform: PdfMatrix(12, 0, 0, 12, 72, 700),
          width: 2.9,
          bounds: PdfRect(72, 688, 130, 712),
          isRightToLeft: true,
        ),
      ],
    );

    final restored = deserializePageText(serializePageText(page));
    expect(restored.pageIndex, 3);
    expect(restored.text, 'Héllo\nworld');
    expect(restored.runs, hasLength(2));
    _expectRunEquals(page.runs[0], restored.runs[0]);
    _expectRunEquals(page.runs[1], restored.runs[1]);
    expect(restored.runs[0].mcid, 4);
    expect(restored.runs[1].mcid, isNull);
  });

  test('a real extraction round-trips and still searches the same', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final original = PdfTextExtractor.extract(doc, 0);
    expect(original.text, isNotEmpty);
    expect(original.runs, isNotEmpty);

    final restored = deserializePageText(serializePageText(original));
    expect(restored.text, original.text);
    expect(restored.runs.length, original.runs.length);
    for (var i = 0; i < original.runs.length; i++) {
      _expectRunEquals(original.runs[i], restored.runs[i]);
    }

    // Geometry survives, so a search hit's quads land in the same place.
    final word = original.runs.first.text.trim().split(' ').first;
    if (word.isNotEmpty) {
      final a = original.findAll(word);
      final b = restored.findAll(word);
      expect(b.length, a.length);
      if (a.isNotEmpty) {
        expect(b.first.quads.first.corners, a.first.quads.first.corners);
      }
    }
  });

  test('an empty page text round-trips', () {
    const page = PdfPageText(pageIndex: 0, text: '', runs: []);
    final restored = deserializePageText(serializePageText(page));
    expect(restored.pageIndex, 0);
    expect(restored.text, isEmpty);
    expect(restored.runs, isEmpty);
  });
}
