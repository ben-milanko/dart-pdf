// Line-ending picker: the controller threads the persisted start/end
// endings into new lines and polylines, and restyles a selected
// /Line or /PolyLine's endings in place. The toolbar's _StyleMenu exposes
// two dropdowns while a line tool is armed or a line is selected.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('controller line endings', () {
    test('new lines and polylines use the persisted endings', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..lineStartEnding = PdfLineEnding.circle
        ..lineEndEnding = PdfLineEnding.closedArrow;
      addTearDown(editing.dispose);

      editing.addLine(0, (100, 100), (220, 160));
      editing.addPolyLine(0, [(100, 220), (150, 260), (220, 230)]);

      final line = editing.document.page(0).annotations[0];
      final poly = editing.document.page(0).annotations[1];
      expect(pdfLineEndings(line),
          (PdfLineEnding.circle, PdfLineEnding.closedArrow));
      expect(pdfLineEndings(poly),
          (PdfLineEnding.circle, PdfLineEnding.closedArrow));
    });

    test('the arrow tool still forces a closed arrow at the end', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..lineStartEnding = PdfLineEnding.diamond
        ..lineEndEnding = PdfLineEnding.none;
      addTearDown(editing.dispose);

      editing.addLine(0, (100, 100), (220, 160), arrow: true);
      expect(pdfLineEndings(editing.document.page(0).annotations.single),
          (PdfLineEnding.none, PdfLineEnding.closedArrow));
    });

    test('setSelectedLineEndings restyles in place, keeping the slot', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addLine(0, (100, 100), (220, 160))
        ..addLine(0, (100, 240), (220, 300))
        ..tool = PdfEditTool.select;
      addTearDown(editing.dispose);

      expect(editing.selectAnnotation(0, 1), isTrue);
      expect(editing.canSetLineEndings, isTrue);
      expect(editing.selectedLineEndings,
          (PdfLineEnding.none, PdfLineEnding.none));

      editing.setSelectedLineEndings(end: PdfLineEnding.openArrow);
      // the selection survives — still slot 1
      expect(editing.selectedAnnotationSlots, [(0, 1)]);
      expect(editing.selectedLineEndings,
          (PdfLineEnding.none, PdfLineEnding.openArrow));
      // the other line is untouched
      expect(pdfLineEndings(editing.document.page(0).annotations[0]),
          (PdfLineEnding.none, PdfLineEnding.none));

      // one undo reverts it
      editing.undo();
      expect(pdfLineEndings(editing.document.page(0).annotations[1]),
          (PdfLineEnding.none, PdfLineEnding.none));
    });

    test('canSetLineEndings is false for shapes and multi-selection', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 100, 200, 200))
        ..addLine(0, (100, 240), (220, 300))
        ..tool = PdfEditTool.select;
      addTearDown(editing.dispose);

      editing.selectAnnotation(0, 0); // the square
      expect(editing.canSetLineEndings, isFalse);
      expect(editing.selectedLineEndings, isNull);

      editing.selectAllAnnotationsOn(0); // both
      expect(editing.canSetLineEndings, isFalse);
    });
  });

  group('line-ending picker', () {
    Future<void> openStyleMenu(WidgetTester tester) async {
      await tester.scrollUntilVisible(
          find.byTooltip('Stroke, opacity, font'), 100);
      await tester.tap(find.byTooltip('Stroke, opacity, font'));
      await tester.pumpAndSettle();
    }

    Widget host(PdfEditingController editing, PdfViewerController viewer) =>
        MaterialApp(
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: ListenableBuilder(
              listenable: editing,
              builder: (context, _) => PdfEditingToolbar(
                controller: editing,
                viewerController: viewer,
              ),
            ),
          ),
        );

    testWidgets('two dropdowns appear with a line tool armed and set defaults',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..tool = PdfEditTool.line;
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(host(editing, viewer));
      await openStyleMenu(tester);

      expect(find.byKey(const ValueKey('pdf-line-start-ending')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-line-end-ending')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-line-end-ending')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Closed arrow').last);
      await tester.pumpAndSettle();
      expect(editing.lineEndEnding, PdfLineEnding.closedArrow);
    });

    testWidgets('the picker restyles a selected line in place', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addLine(0, (100, 100), (220, 160))
        ..tool = PdfEditTool.select;
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      editing.selectAnnotation(0, 0);

      await tester.pumpWidget(host(editing, viewer));
      await openStyleMenu(tester);

      await tester.tap(find.byKey(const ValueKey('pdf-line-start-ending')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diamond').last);
      await tester.pumpAndSettle();

      expect(editing.selectedLineEndings?.$1, PdfLineEnding.diamond);
      expect(pdfLineEndings(editing.document.page(0).annotations.single)?.$1,
          PdfLineEnding.diamond);
    });
  });
}
