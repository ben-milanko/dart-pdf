// The signature-box tool (PdfEditTool.signatureBox): drag a box, then the
// host's onPlaceSignature handler runs with the page and the box in PDF user
// space to collect an identity/appearance and cryptographically sign into it.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('signature-box tool in the viewer', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<PdfEditingController> pumpEditor(WidgetTester tester,
        {PdfSignaturePlacer? onPlaceSignature}) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: viewer,
              editing: editing,
              onPlaceSignature: onPlaceSignature,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('dragging a box calls onPlaceSignature with the page and rect',
        (tester) async {
      int? gotPage;
      PdfRect? gotRect;
      final editing = await pumpEditor(tester,
          onPlaceSignature: (context, {required pageIndex, required pageRect}) async {
        gotPage = pageIndex;
        gotRect = pageRect;
      });
      editing.tool = PdfEditTool.signatureBox;
      await tester.pump();

      final gesture = await tester.startGesture(view(72, 720));
      await gesture.moveTo(view(200, 700));
      await gesture.moveTo(view(320, 640));
      await gesture.up();
      await tester.pump();

      expect(gotPage, 0);
      expect(gotRect, isNotNull);
      // the box maps back to PDF user space (origin bottom-left, y up)
      expect(gotRect!.left, closeTo(72, 1.0));
      expect(gotRect!.right, closeTo(320, 1.0));
      expect(gotRect!.bottom, closeTo(640, 1.0));
      expect(gotRect!.top, closeTo(720, 1.0));
      // placement itself writes nothing to the document - the host signs
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.isModified, isFalse);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('with no handler the tool is inert', (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.signatureBox;
      await tester.pump();

      final gesture = await tester.startGesture(view(72, 720));
      await gesture.moveTo(view(320, 640));
      await gesture.up();
      await tester.pump();

      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.isModified, isFalse);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
