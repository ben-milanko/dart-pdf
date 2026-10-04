// ocrAllPages is the page loop the native and web OCR jobs share: every page
// rasterized at OcrRunnerEngine.pixelRatioFor, progress per page, cancellation
// between pages. Proven with a fake engine (no model).
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/ocr_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// Writes one span per page and records the raster each page arrived at.
class _FakeEngine implements PdfOcrEngine {
  final pixelRatios = <double>[];

  @override
  Future<List<PdfOcrSpan>> recognize(PdfOcrPageImage page) async {
    pixelRatios.add(page.pixelRatio);
    return [
      PdfOcrSpan(
          text: 'page ${page.pageIndex}', bounds: PdfRect(10, 10, 80, 30)),
    ];
  }
}

void main() {
  test('runs every page at 216 dpi and reports each', () async {
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)));
    final engine = _FakeEngine();
    final pages = <(int, int)>[];
    final spans = await ocrAllPages(editor, engine,
        isCancelled: () => false, onPage: (i, n) => pages.add((i, n)));
    expect(spans, 3);
    expect(pages, [(0, 3), (1, 3), (2, 3)]);
    expect(engine.pixelRatios, [3, 3, 3]);
  });

  test('stops at the next page once cancelled', () async {
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)));
    final engine = _FakeEngine();
    var started = 0;
    final spans = await ocrAllPages(editor, engine,
        isCancelled: () => started >= 2, onPage: (_, __) => started++);
    expect(spans, 2);
    expect(engine.pixelRatios, hasLength(2));
  });
}
