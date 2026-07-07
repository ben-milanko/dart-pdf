// The viewer's scroll metrics must be exact, not estimated: stock
// ListView reports a maxScrollExtent extrapolated from the average extent
// of the built children, which oscillates by tens of thousands of pixels
// on long mixed-size documents (AMT-SP-101: 93k↔162k between frames) and
// makes the scrollbar thumb leap around while scrolling.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  testWidgets('maxScrollExtent is exact and constant on mixed-size documents',
      (tester) async {
    const pageCount = 30;
    final document = PdfDocument.open(buildVariedHeightPdf(pageCount));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
        ),
      ),
    ));
    await tester.pump();

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    // the exact total: pages lay out fit-width (viewport 800 wide), so
    // each page is aspect * 800 tall, separated by pageSpacing (12) with
    // a trailing bottom pad of the same
    const width = 800.0;
    const spacing = 12.0;
    const heights = [792.0, 396.0, 1008.0]; // buildVariedHeightPdf's cycle
    var content = 0.0;
    for (var i = 0; i < pageCount; i++) {
      content += heights[i % 3] / 612.0 * width;
    }
    content += spacing * pageCount; // between pages + bottom padding
    final expected = content - position.viewportDimension;
    expect(position.maxScrollExtent, moreOrLessEquals(expected, epsilon: 1));

    // scrolling through windows dominated by short or tall pages must not
    // move the metrics - this is what the estimating sliver gets wrong
    final initialMax = position.maxScrollExtent;
    for (final fraction in [0.15, 0.4, 0.65, 0.9, 0.3, 0.05]) {
      position.jumpTo(initialMax * fraction);
      await tester.pump();
      await tester.pump();
      expect(position.maxScrollExtent, initialMax,
          reason: 'maxScrollExtent drifted at scroll fraction $fraction');
    }
    await tester.pump(const Duration(milliseconds: 400)); // settle timers
  });
}
