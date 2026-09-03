// Fix 4: on a HEAVY page (raw content over
// PdfViewer.hoverTextExtractMaxRawContentBytes) a mouse hover must not trigger
// the synchronous full-page text extraction the cursor logic used to force -
// which freezes a frame the instant the pointer crosses a dense CAD sheet.
//
// Runs in CI against an ordinary fixture by lowering the threshold to 0 so the
// page counts as "heavy": the I-beam then only appears once the text has been
// warmed by a real action (here, a selection drag), never from hover alone.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

void main() {
  MouseRegion region(WidgetTester tester) => tester.widget<MouseRegion>(find
      .descendant(
          of: find.byType(PdfViewer), matching: find.byType(MouseRegion))
      .first);

  testWidgets('hover over a heavy page does not extract text synchronously',
      (tester) async {
    final previous = PdfViewer.hoverTextExtractMaxRawContentBytes;
    // Treat every page as "heavy" so the ordinary fixture exercises the gate.
    PdfViewer.hoverTextExtractMaxRawContentBytes = 0;
    addTearDown(() => PdfViewer.hoverTextExtractMaxRawContentBytes = previous);

    final document = PdfDocument.open(buildClassicPdf());
    final controller = PdfViewerController();
    addTearDown(controller.dispose);

    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: PdfViewer(
            document: document,
            controller: controller,
            initialFit: PdfViewerFit.width,
          ),
        ),
      ),
    ));
    await tester.pump();

    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 11);
    await gesture.addPointer(location: view(300, 500));
    addTearDown(gesture.removePointer);
    await tester.pump();

    // Hover over 'Page 1' text on a "heavy" page: cursor stays grab because
    // the cold text cache is NOT extracted synchronously from a hover.
    await gesture.moveTo(view(100, 720));
    await tester.pump();
    expect(region(tester).cursor, SystemMouseCursors.grab,
        reason: 'heavy page must not extract text just to pick a hover cursor');

    // A real action warms the cache (selection drag over the same text)...
    final drag =
        await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 12);
    await drag.down(view(96, 722));
    await tester.pump();
    await drag.moveTo(view(140, 722));
    await tester.pump();
    await drag.up();
    await tester.pump();

    // ...after which hovering the now-resident text does show the I-beam.
    await gesture.moveTo(view(300, 500));
    await tester.pump();
    await gesture.moveTo(view(100, 720));
    await tester.pump();
    expect(region(tester).cursor, SystemMouseCursors.text,
        reason: 'once warmed by a real action, the I-beam appears on hover');
  });
}
