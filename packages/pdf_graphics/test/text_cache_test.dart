import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

PdfPageText _sample() => PdfPageText(
      pageIndex: 3,
      text: 'Hello wörld', // non-ASCII to exercise utf8
      runs: const [
        PdfExtractedRun(
          text: 'Hello',
          startIndex: 0,
          transform: PdfMatrix(12, 0, 0, 12, 72, 700),
          width: 2.5,
          bounds: PdfRect(72, 694, 132, 712),
          // Uneven, like a proportional font's real advances (#647).
          charOffsets: [0, 0.72, 1.28, 1.5, 1.72, 2.5],
        ),
        PdfExtractedRun(
          text: 'wörld',
          startIndex: 6,
          transform: PdfMatrix(12, 1, -1, 12, 140, 700),
          width: 2.6,
          bounds: PdfRect(140, 694, 200, 712),
          isRightToLeft: true,
        ),
      ],
    );

void _expectSame(PdfPageText a, PdfPageText b) {
  expect(b.pageIndex, a.pageIndex);
  expect(b.text, a.text);
  expect(b.runs.length, a.runs.length);
  for (var i = 0; i < a.runs.length; i++) {
    expect(b.runs[i].text, a.runs[i].text);
    expect(b.runs[i].startIndex, a.runs[i].startIndex);
    expect(b.runs[i].isRightToLeft, a.runs[i].isRightToLeft);
    expect(b.runs[i].width, a.runs[i].width);
    expect(b.runs[i].charOffsets, a.runs[i].charOffsets);
    final ta = a.runs[i].transform, tb = b.runs[i].transform;
    expect([tb.a, tb.b, tb.c, tb.d, tb.e, tb.f],
        [ta.a, ta.b, ta.c, ta.d, ta.e, ta.f]);
    final ba = a.runs[i].bounds, bb = b.runs[i].bounds;
    expect([bb.left, bb.bottom, bb.right, bb.top],
        [ba.left, ba.bottom, ba.right, ba.top]);
  }
}

void main() {
  group('PdfPageText codec', () {
    test('round-trips exactly', () {
      final page = _sample();
      final decoded = pdfDecodePageText(pdfEncodePageText(page));
      expect(decoded, isNotNull);
      _expectSame(page, decoded!);
    });

    test('rejects junk bytes as a miss', () {
      final blob = pdfEncodePageText(_sample());
      // truncated
      expect(pdfDecodePageText(blob.sublist(0, 3)), isNull);
      // wrong magic
      final corrupt = Uint8List.fromList(blob)..[0] ^= 0xff;
      expect(pdfDecodePageText(corrupt), isNull);
    });

    test('handles an empty page', () {
      final page = PdfPageText(pageIndex: 0, text: '', runs: const []);
      final decoded = pdfDecodePageText(pdfEncodePageText(page));
      _expectSame(page, decoded!);
    });

    test('a real extraction round-trips with its selection geometry', () {
      // The disk tier serves cached text on every reopen, so per-character
      // advances (#647) have to survive it - otherwise a cache hit silently
      // reverts highlights to the interpolated positions the issue reported.
      final original =
          PdfTextExtractor.extract(PdfDocument.open(buildClassicPdf()), 0);
      final decoded = pdfDecodePageText(pdfEncodePageText(original))!;
      _expectSame(original, decoded);
      expect(original.runs.single.charOffsets, isNotNull);

      final start = original.text.indexOf('world');
      expect(decoded.quadsFor(start, start + 5).single.corners,
          original.quadsFor(start, start + 5).single.corners);
      final mid = 72 + measureHelvetica('Hello, wor', 24);
      expect(decoded.positionNear(mid, 726), original.positionNear(mid, 726));
    });

    test('a table of the wrong length is dropped, not trusted', () {
      // Lenient on input: a stale or corrupt blob whose offsets no longer
      // match the run text falls back to interpolation instead of throwing
      // out of quadsFor.
      const page = PdfPageText(
        pageIndex: 0,
        text: 'abc',
        runs: [
          PdfExtractedRun(
            text: 'abc',
            startIndex: 0,
            transform: PdfMatrix(12, 0, 0, 12, 0, 0),
            width: 1.5,
            bounds: PdfRect(0, 0, 18, 12),
            charOffsets: [0, 0.5, 1.5], // one short: needs text.length + 1
          ),
        ],
      );
      final decoded = pdfDecodePageText(pdfEncodePageText(page))!;
      expect(decoded.runs.single.charOffsets, isNull);
      expect(decoded.quadsFor(0, 3), hasLength(1)); // and still usable
    });
  });

  group('PdfPageTextCache', () {
    test('computes on a miss, then serves from the store', () async {
      final cache = PdfPageTextCache(PdfDiskCache(PdfMemoryCacheStore()));
      var computes = 0;
      Future<PdfPageText> compute() async {
        computes++;
        return _sample();
      }

      final first = await cache.get('docA', 3, compute);
      _expectSame(_sample(), first);
      expect(computes, 1);

      // second call hits the disk cache - no recompute
      final second = await cache.get('docA', 3, compute);
      _expectSame(_sample(), second);
      expect(computes, 1);
    });

    test('keys by document and page', () async {
      final cache = PdfPageTextCache(PdfDiskCache(PdfMemoryCacheStore()));
      await cache.get('docA', 0, () async => _sample());
      var computed = false;
      await cache.get('docB', 0, () async {
        computed = true;
        return _sample();
      });
      expect(computed, isTrue, reason: 'different document must miss');
    });
  });
}
