// The colour the style controls read back: with an annotation selected the
// swatches show its own colour, not the last-used creation colour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _red = Color(0xFFE53935);
const _blue = Color(0xFF1E88E5);
const _green = Color(0xFF43A047);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('displayColor on the controller', () {
    test('without a selection it is the creation colour', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))..color = _red;
      addTearDown(editing.dispose);
      expect(editing.displayColor, _red);
    });

    test('a selected annotation shows its own colour', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))..color = _red;
      addTearDown(editing.dispose);
      editing
        ..addRectangle(0, const PdfRect(100, 100, 300, 200))
        ..color = _blue // draw red, then move the creation default on
        ..selectAnnotation(0, 0);
      expect(editing.displayColor, _red);
      expect(editing.color, _blue, reason: 'the creation default is untouched');
    });

    test('deselecting falls back to the creation colour', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))..color = _red;
      addTearDown(editing.dispose);
      editing
        ..addRectangle(0, const PdfRect(100, 100, 300, 200))
        ..color = _blue
        ..selectAnnotation(0, 0)
        ..clearAnnotationSelection();
      expect(editing.displayColor, _blue);
    });

    test('it follows a restyle of the selection', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))..color = _red;
      addTearDown(editing.dispose);
      editing
        ..addRectangle(0, const PdfRect(100, 100, 300, 200))
        ..selectAnnotation(0, 0);
      expect(editing.restyleSelected(color: _green), isTrue);
      expect(editing.displayColor, _green);
    });

    test('a selected free text shows its text colour', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))..color = _red;
      addTearDown(editing.dispose);
      editing
        ..addFreeText(0, const PdfRect(100, 100, 300, 160), 'hello')
        ..color = _blue
        ..selectAnnotation(0, 0);
      expect(editing.canRestyleSelected, isTrue);
      expect(editing.displayColor, _red);
    });

    test('a multi-selection shows the primary annotation colour', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))..color = _red;
      addTearDown(editing.dispose);
      editing
        ..addRectangle(0, const PdfRect(100, 100, 300, 200))
        ..color = _green
        ..addEllipse(0, const PdfRect(320, 100, 400, 200))
        ..color = _blue
        ..selectAnnotationsIn(0, const PdfRect(0, 0, 612, 792));
      expect(editing.selectedAnnotationSlots, hasLength(2));
      // the primary is the last slot added to the selection
      final primary = editing.selectedAnnotation!;
      expect(editing.displayColor, Color(0xFF000000 | primary.color!));
    });
  });

  group('in the toolbar', () {
    Future<PdfEditingController> pumpEditor(WidgetTester tester) async {
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
          bottomNavigationBar:
              PdfEditingToolbar(controller: editing, viewerController: viewer),
        ),
      ));
      await tester.pump();
      return editing;
    }

    /// The ring width the palette swatch for [color] is drawn with - 3 when
    /// it reads as the current colour, 1 otherwise.
    double ringWidth(WidgetTester tester, Color color) {
      final swatch = find.descendant(
        of: find.byType(PdfEditingToolbar),
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == color &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle),
      );
      expect(swatch, findsOneWidget);
      final decoration =
          tester.widget<Container>(swatch).decoration! as BoxDecoration;
      return (decoration.border! as Border).top.width;
    }

    testWidgets('the palette ring follows the selected annotation',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing
        ..color = _red
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..color = _blue
        // arm a shape tool so the strip carries the palette with nothing
        // selected; a selection takes the strip over and carries it too
        ..tool = PdfEditTool.rectangle;
      await tester.pump();
      expect(ringWidth(tester, _blue), 3, reason: 'the last-used colour');
      expect(ringWidth(tester, _red), 1);

      editing.selectAnnotation(0, 0);
      await tester.pump();
      expect(ringWidth(tester, _red), 3, reason: "the selection's own colour");
      expect(ringWidth(tester, _blue), 1);

      editing
        ..clearAnnotationSelection()
        ..tool = PdfEditTool.rectangle;
      await tester.pump();
      expect(ringWidth(tester, _blue), 3);
      expect(ringWidth(tester, _red), 1);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });
  });
}
