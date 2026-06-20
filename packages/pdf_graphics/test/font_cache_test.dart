// The shared font cache must (a) load each font dictionary at most once and
// reuse it across interpreter instances — the two passes of one render and
// every re-render — and (b) hand back stable glyph-outline identities so the
// device's glyph-path cache hits across renders, all without changing what the
// interpreter emits.
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

class _NoOp implements PdfDevice {
  @override
  void noSuchMethod(Invocation invocation) {}
}

class _TextRecorder implements PdfDevice {
  final texts = <PdfTextRun>[];
  @override
  void drawText(PdfTextRun run) => texts.add(run);
  @override
  void noSuchMethod(Invocation invocation) {}
}

void _paint(PdfPage page, PdfDevice device) {
  PdfInterpreter(cos: page.document.cos, device: device)
    ..drawPageOperations(
        page, ContentStreamParser.parse(page.contentBytes()))
    ..drawAnnotations(page);
}

void main() {
  test('a font dict loads once and is reused across interpreter instances', () {
    PdfInterpreter.clearFontCache();
    expect(PdfInterpreter.debugFontCacheLength, 0);

    final page = PdfDocument.open(buildClassicPdf()).page(0);
    _paint(page, _NoOp());
    final afterFirst = PdfInterpreter.debugFontCacheLength;
    expect(afterFirst, greaterThan(0),
        reason: 'the page references at least one font');

    // A second, independent interpreter over the same page reuses the cache:
    // no new fonts load, so the count does not grow.
    _paint(page, _NoOp());
    expect(PdfInterpreter.debugFontCacheLength, afterFirst,
        reason: 're-rendering must hit the cache, not reload fonts');
  });

  test('the image-scan pass and the paint pass share one load', () {
    PdfInterpreter.clearFontCache();
    final page = PdfDocument.open(buildClassicPdf()).page(0);

    // Image-scan (collect) pass warms the cache...
    PdfInterpreter(cos: page.document.cos, device: _NoOp(), scanImagesOnly: true)
      ..drawPageOperations(
          page, ContentStreamParser.parse(page.contentBytes()))
      ..drawAnnotations(page);
    final afterScan = PdfInterpreter.debugFontCacheLength;
    expect(afterScan, greaterThan(0));

    // ...so the following paint pass reloads nothing.
    _paint(page, _NoOp());
    expect(PdfInterpreter.debugFontCacheLength, afterScan);
  });

  test('cached fonts return stable glyph-outline identities across renders', () {
    PdfInterpreter.clearFontCache();
    final page = PdfDocument.open(buildEmbeddedFontPdf()).page(0);

    final first = _TextRecorder();
    _paint(page, first);
    final second = _TextRecorder();
    _paint(page, second);

    // Same embedded font on both renders → the memoised outline PdfPath
    // instances are identical (not just equal), which is what the device's
    // identity-keyed glyph-path cache relies on.
    PdfPath? outlineOf(List<PdfTextRun> runs) {
      for (final run in runs) {
        for (final g in run.glyphs ?? const <PdfGlyphPlacement>[]) {
          if (g.outline != null) return g.outline;
        }
      }
      return null;
    }

    final a = outlineOf(first.texts);
    final b = outlineOf(second.texts);
    expect(a, isNotNull, reason: 'the embedded font has glyph outlines');
    expect(identical(a, b), isTrue,
        reason: 'the shared font yields the same outline instance each render');
  });

  test('clearFontCache empties the cache', () {
    final page = PdfDocument.open(buildClassicPdf()).page(0);
    _paint(page, _NoOp());
    expect(PdfInterpreter.debugFontCacheLength, greaterThan(0));
    PdfInterpreter.clearFontCache();
    expect(PdfInterpreter.debugFontCacheLength, 0);
  });

  test('mismatched fonts both stay cached', () {
    PdfInterpreter.clearFontCache();
    _paint(PdfDocument.open(buildClassicPdf()).page(0), _NoOp());
    final n = PdfInterpreter.debugFontCacheLength;
    _paint(PdfDocument.open(buildEmbeddedFontPdf()).page(0), _NoOp());
    expect(PdfInterpreter.debugFontCacheLength, greaterThan(n),
        reason: 'a different document\'s fonts add distinct entries');
  });
}
