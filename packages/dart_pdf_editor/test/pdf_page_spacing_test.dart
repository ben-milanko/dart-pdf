// The inter-page gap must stay in proportion to the pages across the zoom
// range. A constant pixel gap grows relative to the pages as you zoom out
// (pages lay out smaller below fit while the gap stayed fixed), which reads
// as the spacing "changing" when zooming in and out. Two sources of a
// zoom-dependent gap are covered: the page spacing itself, and - with a
// pasteboard margin - a constant page inset that left the raster short of
// its (layout-zoom-scaled) tile.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  Future<double> Function(double) gapProbe(WidgetTester tester,
      PdfViewerController c, double fit) {
    return (double frac) async {
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
    };
  }

  for (final margin in const [0.0, 96.0]) {
    testWidgets('the page gap stays proportional across zoom (pasteboard '
        '$margin)', (tester) async {
      final c = PdfViewerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            initialFit: PdfViewerFit.width,
            document: PdfDocument.open(buildMultiPagePdf(6)),
            controller: c,
            pasteboardMargin: margin,
          ),
        ),
      ));
      await tester.pump();
      final gapRatioAt = gapProbe(tester, c, c.zoom);

      final wide = await gapRatioAt(0.4);
      final tight = await gapRatioAt(0.2);
      // the gap tracks the page size, so the ratio is stable. With a
      // pasteboard margin the ratio used to blow up when zooming out (the
      // raster fell short of its shrinking tile by a constant inset).
      expect(tight, moreOrLessEquals(wide, epsilon: 0.003),
          reason: 'the gap must not change relative to the pages when zooming');
    });
  }
}
