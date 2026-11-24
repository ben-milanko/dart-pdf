import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

// The space after the last page (page spacing + PdfViewer.trailingPadding) is
// list padding, and above fit the list rides a zoom transform - so the tail
// used to magnify with the pages. A pack whose one wide sheet sets fit for
// every page sits several times past fit at an ordinary zoom, and ended in a
// blank stretch most of a screen tall. The tail must stay its nominal size.
void main() {
  // A3 landscape sheets set fit width; the last page is a narrower portrait
  // sheet, the shape of a drawing pack.
  PdfDocument drawingPack() {
    final editor = PdfEditor(
        PdfDocument.open(buildMultiPagePdf(6, width: 1191, height: 842)));
    editor.appendPagesFrom(
        PdfDocument.open(buildMultiPagePdf(1, width: 842, height: 1191)));
    return PdfDocument.open(editor.save());
  }

  const view = Size(1040, 760);
  const spacing = 12.0;
  const trailing = 144.0;

  Future<double> gapAfterLastPageAt(
      WidgetTester tester, double fitMultiple) async {
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = PdfViewerController();
    final document = drawingPack();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
          pageSpacing: spacing,
          trailingPadding: trailing,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    controller.setZoom(controller.zoom * fitMultiple);
    await tester.pumpAndSettle();
    // wheel to the very end: past the list's extent the zoom window pans
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(view.center(Offset.zero)));
    for (var i = 0; i < 150; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 400)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    final last = document.pageCount - 1;
    final page = document.page(last);
    final rect = controller.globalRectOf(
        last, PdfRect(0, 0, page.mediaBox.width, page.mediaBox.height))!;
    return view.height - rect.bottom;
  }

  for (final multiple in [1.0, 2.0, 5.0]) {
    testWidgets('the tail after the last page stays nominal at ${multiple}x',
        (tester) async {
      expect(await gapAfterLastPageAt(tester, multiple),
          closeTo(spacing + trailing, 1),
          reason: 'the blank space after the last page must not scale with '
              'the zoom window');
    });
  }
}
