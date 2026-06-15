import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
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
        ),
        PdfExtractedRun(
          text: 'wörld',
          startIndex: 6,
          transform: PdfMatrix(12, 1, -1, 12, 140, 700),
          width: 2.6,
          bounds: PdfRect(140, 694, 200, 712),
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
    expect(b.runs[i].width, a.runs[i].width);
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

      // second call hits the disk cache — no recompute
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
