import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The mobile dock shows its colour swatches only when colour is relevant to
// the moment — a colour-using tool armed, or a recolourable selection — and
// gives the space to a selection's quick actions otherwise (Ben: "Only show
// the colours on the mobile toolbar if it's relevant to the current tool").
void main() {
  final swatch = find.byKey(const ValueKey('pdf-mobile-swatch-0'));

  Future<PdfEditingController> pumpToolbar(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildAppearanceAnnotationsPdf());
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        // a width under the 600px mobile breakpoint forces the dock layout
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 380,
            child: PdfEditingToolbar(
                controller: editing, viewerController: viewer),
          ),
        ),
      ),
    ));
    await tester.pump();
    return editing;
  }

  test('toolUsesColor: true for painters, false for colourless tools', () {
    SharedPreferences.setMockInitialValues({});
    final c = PdfEditingController(buildAppearanceAnnotationsPdf());
    addTearDown(c.dispose);

    for (final tool in [
      PdfEditTool.ink,
      PdfEditTool.rectangle,
      PdfEditTool.line,
      PdfEditTool.freeText,
      PdfEditTool.stamp,
      PdfEditTool.measureDistance,
    ]) {
      c.tool = tool;
      expect(c.toolUsesColor, isTrue, reason: '$tool paints in colour');
    }
    for (final tool in [PdfEditTool.eraser, PdfEditTool.form]) {
      c.tool = tool;
      expect(c.toolUsesColor, isFalse, reason: '$tool ignores colour');
    }
    c.tool = null;
    expect(c.toolUsesColor, isFalse, reason: 'select ignores colour');
  });

  testWidgets('swatches hide for a colourless tool, show for a painter',
      (tester) async {
    final editing = await pumpToolbar(tester);

    // resting (Select) — no colour to set
    expect(swatch, findsNothing);

    editing.tool = PdfEditTool.eraser;
    await tester.pump();
    expect(swatch, findsNothing, reason: 'the eraser ignores colour');

    editing.tool = PdfEditTool.ink;
    editing.color = const Color(0xFF123456); // a non-palette colour
    await tester.pump();
    expect(swatch, findsOneWidget, reason: 'ink paints in colour');

    // tapping the swatch sets the creation colour
    await tester.tap(swatch);
    await tester.pump();
    expect(editing.color, PdfEditingToolbar.defaultPalette.first);
  });

  testWidgets('a selection surfaces quick actions, not creation swatches',
      (tester) async {
    final editing = await pumpToolbar(tester);
    editing.tool = PdfEditTool.ink; // swatches up while a colour tool is armed
    await tester.pump();
    expect(swatch, findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    // slot 0 is the Square annotation — selectable, unlike the Link/Widget
    // entries the link fixture carries; selecting arms the select tool
    expect(editing.selectAnnotation(0, 0), isTrue);
    await tester.pump();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget,
        reason: 'a selected annotation can be deleted from the dock');
    expect(swatch, findsNothing,
        reason: 'the creation swatches make way for the selection actions');

    // and the action works: tapping it removes the annotation
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    expect(editing.hasAnnotationSelection, isFalse);
    expect(editing.isModified, isTrue, reason: 'the annotation was removed');
  });
}
