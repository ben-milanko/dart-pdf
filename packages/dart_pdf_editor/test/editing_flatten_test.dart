import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpToolbar(
    WidgetTester tester,
    PdfEditingController editing,
    PdfViewerController viewer,
  ) async {
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
        bottomNavigationBar: PdfEditingToolbar(
          controller: editing,
          viewerController: viewer,
        ),
      ),
    ));
    await tester.pump();
    // Flatten moved from the dock into the Edit group's strip — open it
    // (the dock scrolls horizontally; the Edit chip may be off-screen)
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('pdf-group-edit')), 100,
        scrollable: find.descendant(
            of: find.byType(PdfEditingToolbar),
            matching: find.byType(Scrollable)));
    await tester.tap(find.byKey(const ValueKey('pdf-group-edit')));
    await tester.pump();
  }

  group('flatten controller', () {
    test('flattenAllAnnotations reports whether anything was flattened', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      // a fresh page carries no flattenable annotations
      expect(editing.flattenAllAnnotations(), isFalse);

      editing.addRectangle(0, const PdfRect(100, 100, 200, 150));
      expect(editing.document.page(0).annotations, isNotEmpty);

      expect(editing.flattenAllAnnotations(), isTrue);
      expect(editing.document.page(0).annotations, isEmpty);
    });
  });

  group('flatten feedback in the toolbar', () {
    testWidgets('flattening annotations shows a SnackBar with Undo',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 100, 200, 150));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await pumpToolbar(tester, editing, viewer);

      final flatten = find.byTooltip('Flatten annotations into the pages');
      final toolbarScrollable = find.descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(flatten, 100,
          scrollable: toolbarScrollable);
      await tester.tap(flatten);
      // let the SnackBar finish animating in so its action is hit-testable
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Annotations flattened into the pages'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
      expect(editing.document.page(0).annotations, isEmpty);

      // the Undo action restores the annotation
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(editing.document.page(0).annotations, isNotEmpty);
    });

    testWidgets('flattening with nothing to flatten shows an info SnackBar',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await pumpToolbar(tester, editing, viewer);

      final flatten = find.byTooltip('Flatten annotations into the pages');
      final toolbarScrollable = find.descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(flatten, 100,
          scrollable: toolbarScrollable);
      await tester.tap(flatten);
      await tester.pump();

      expect(find.text('No annotations to flatten'), findsOneWidget);
      // nothing changed, so there is no Undo offered
      expect(find.widgetWithText(SnackBarAction, 'Undo'), findsNothing);
    });
  });
}
