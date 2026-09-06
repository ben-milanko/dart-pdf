// Middle-button drag pans the document, the way every other PDF viewer does:
// it grabs the page past whatever the primary button would have meant there -
// a text selection in the reader, a stroke or a marquee with a tool armed -
// without disarming the tool. Flutter's drag recognizers accept the primary
// button only, so before this the gesture reached nothing at all.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  Future<PdfViewerController> pumpViewer(
    WidgetTester tester, {
    PdfEditingController? editing,
  }) async {
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          document: editing == null ? PdfDocument.open(buildMultiPagePdf(5)) : null,
          editing: editing,
          controller: controller,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return controller;
  }

  Future<void> dragBy(
    WidgetTester tester,
    Offset from,
    Offset delta, {
    required int buttons,
  }) async {
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    );
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(delta / 4);
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a middle drag scrolls the document', (tester) async {
    final controller = await pumpViewer(tester);
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(state.position.pixels, 0);

    await dragBy(tester, const Offset(400, 400), const Offset(0, -160),
        buttons: kMiddleMouseButton);

    expect(state.position.pixels, greaterThan(0),
        reason: 'dragging up with the middle button moves the page up');
    expect(controller.hasSelection, isFalse,
        reason: 'a middle drag pans; it never selects text');
  });

  testWidgets('a middle drag pans without disarming the armed tool',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(5));
    addTearDown(editing.dispose);
    editing.tool = PdfEditTool.rectangle;
    await pumpViewer(tester, editing: editing);
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);

    await dragBy(tester, const Offset(400, 400), const Offset(0, -160),
        buttons: kMiddleMouseButton);

    expect(state.position.pixels, greaterThan(0));
    expect(editing.tool, PdfEditTool.rectangle,
        reason: 'panning is not a tool change');
    expect(editing.pageAt(0).annotations, isEmpty,
        reason: 'the middle drag must not draw the armed shape');
  });
}
