// The inter-page gap must stay in proportion to the pages across the zoom
// range. A constant pixel gap grows relative to the pages as you zoom out
// (pages lay out smaller below fit while the gap stayed fixed), which reads
// as the spacing "changing" when zooming in and out. The gap is scaled by
// the layout zoom so the ratio holds.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  testWidgets('the page gap stays proportional to the pages across zoom',
      (tester) async {
    final c = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          document: PdfDocument.open(buildMultiPagePdf(6)),
          controller: c,
        ),
      ),
    ));
    await tester.pump();
    final fit = c.zoom;

    // gap between the first two pages / the first page's height, at a given
    // fraction of the fit-width zoom (below fit, so several pages are visible)
    Future<double> gapRatioAt(double frac) async {
      c.setZoom(fit * frac);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      final rects = find
          .byType(PdfPageView)
          .evaluate()
          .map((e) => e.renderObject! as RenderBox)
          .map((rb) => rb.localToGlobal(Offset.zero) & rb.size)
          .toList()
        ..sort((a, b) => a.top.compareTo(b.top));
      expect(rects.length, greaterThanOrEqualTo(2));
      return (rects[1].top - rects[0].bottom) / rects[0].height;
    }

    final wide = await gapRatioAt(0.4);
    final tight = await gapRatioAt(0.2);
    // the gap tracks the page size, so the ratio is stable (it used to
    // nearly double between these two zooms with a constant-pixel gap)
    expect(tight, moreOrLessEquals(wide, epsilon: 0.002),
        reason: 'the gap must not change relative to the pages when zooming');
  });
}
