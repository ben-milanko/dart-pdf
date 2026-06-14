// Count tool (PdfEditTool.count): tap to drop check-marks Bluebeam-style.
// Each tap places a /Stamp check-mark annotation and bumps the running
// tally (PdfEditingController.checkMarkCount); the marks behave like any
// other annotation (select/move/delete) and the tally tracks undo/redo.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PdfEditingController check-marks', () {
    test('placeCheckMark drops a /Stamp /Check centered on the tap', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      expect(editing.placeCheckMark(0, 300, 400), isTrue);
      final mark = editing.document.page(0).annotations.single;
      expect(mark.isCheckMark, isTrue);
      expect((mark.rect.left + mark.rect.right) / 2, closeTo(300, 1e-9));
      expect((mark.rect.bottom + mark.rect.top) / 2, closeTo(400, 1e-9));
      // a default-size square mark
      expect(mark.rect.width, closeTo(PdfEditingController.checkMarkSize, 1e-9));
      expect(mark.rect.width, closeTo(mark.rect.height, 1e-9));
    });

    test('the mark follows the selected colour', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      editing.color = const Color(0xFFC03030);
      editing.placeCheckMark(0, 100, 100);
      expect(editing.document.page(0).annotations.single.color, 0xC03030);
    });

    test('placeCheckMark clamps the mark to keep it on the page', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      expect(editing.placeCheckMark(0, 2, 2), isTrue);
      final rect = editing.document.page(0).annotations.single.rect;
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.bottom, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(612));
      expect(rect.top, lessThanOrEqualTo(792));
    });

    test('checkMarkCount tallies marks across pages and tracks undo/redo', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);

      expect(editing.checkMarkCount, 0);
      editing.placeCheckMark(0, 100, 100);
      editing.placeCheckMark(0, 200, 200);
      editing.placeCheckMark(1, 100, 100);
      expect(editing.checkMarkCount, 3);

      editing.undo();
      expect(editing.checkMarkCount, 2);
      editing.redo();
      expect(editing.checkMarkCount, 3);
    });

    test('non-check stamps do not count towards the tally', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      editing.placeTextStamp(0, 200, 200, 'APPROVED');
      expect(editing.checkMarkCount, 0);
    });
  });

  group('count tool in the viewer', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<void> tap(WidgetTester tester, Offset position) async {
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<PdfEditingController> pumpEditor(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
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
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('each tap drops a check-mark and bumps the tally',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.count;
      await tester.pump();

      await tap(tester, view(200, 400));
      await tester.pump();
      await tap(tester, view(300, 400));
      await tester.pump();

      final marks = editing.document.page(0).annotations;
      expect(marks.length, 2);
      expect(marks.every((a) => a.isCheckMark), isTrue);
      expect(editing.checkMarkCount, 2);
    });

    testWidgets('the toolbar shows the running tally while the tool is armed',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => const SizedBox.expand(),
          ),
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      await tester.pump();

      const tally = ValueKey('pdf-count-tally');
      // the tally chip only shows with the count tool armed
      expect(find.byKey(tally), findsNothing);
      editing.tool = PdfEditTool.count;
      await tester.pump();
      expect(find.byKey(tally), findsOneWidget);
      expect(
          find.descendant(of: find.byKey(tally), matching: find.text('0')),
          findsOneWidget);

      editing.placeCheckMark(0, 100, 100);
      editing.placeCheckMark(0, 200, 200);
      await tester.pump();
      expect(
          find.descendant(of: find.byKey(tally), matching: find.text('2')),
          findsOneWidget);
    });
  });
}
