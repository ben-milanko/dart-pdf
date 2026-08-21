import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The mobile dock shows its colour swatches only when colour is relevant to
// the moment - a colour-using tool armed, or a recolourable selection - and
// gives the space to a selection's quick actions otherwise (Ben: "Only show
// the colours on the mobile toolbar if it's relevant to the current tool").
void main() {
  final swatch = find.byKey(const ValueKey('pdf-mobile-swatch-0'));

  Future<PdfEditingController> pumpToolbar(WidgetTester tester,
      {Uint8List? bytes, double width = 380}) async {
    SharedPreferences.setMockInitialValues({});
    final editing =
        PdfEditingController(bytes ?? buildAppearanceAnnotationsPdf());
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        // a width under the 600px mobile breakpoint forces the dock layout
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: width,
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
      PdfEditTool.highlight,
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
    c.markupTool = PdfMarkupKind.highlight;
    expect(c.toolUsesColor, isTrue, reason: 'text markup paints in colour');
  });

  testWidgets('swatches hide for a colourless tool, show for a painter',
      (tester) async {
    final editing = await pumpToolbar(tester);

    // resting (Select) - no colour to set
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

  testWidgets('active tool status yields when phone actions consume the dock',
      (tester) async {
    final editing = await pumpToolbar(tester, width: 320);

    editing.tool = PdfEditTool.note;
    await tester.pump();

    expect(
        find.byKey(const ValueKey('pdf-mobile-current-tool')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-tools-handle')), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'the tool switcher must not overflow a narrow dock');
  });

  testWidgets('current tool popup recalls previous tools in MRU order',
      (tester) async {
    final editing = await pumpToolbar(tester, width: 500);

    editing.tool = PdfEditTool.select;
    await tester.pump();
    editing.tool = PdfEditTool.ink;
    await tester.pump();
    editing.tool = PdfEditTool.rectangle;
    await tester.pump();

    final switcher = find.byKey(const ValueKey('pdf-mobile-current-tool'));
    final semantics = tester.getSemantics(switcher);
    expect(semantics.label, contains('Rectangle'));
    expect(semantics.label, contains('Recently used'));

    await tester.tap(switcher);
    await tester.pumpAndSettle();

    final ink = find.byKey(const ValueKey('pdf-recent-tool-ink'));
    final select = find.byKey(const ValueKey('pdf-recent-tool-select'));
    expect(ink, findsOneWidget);
    expect(select, findsOneWidget);
    expect(
        find.byKey(const ValueKey('pdf-recent-tool-rectangle')), findsNothing,
        reason: 'the active tool is not repeated in its previous-tool list');
    expect(tester.getTopLeft(ink).dy, lessThan(tester.getTopLeft(select).dy),
        reason: 'the most recently used previous tool comes first');

    await tester.tap(ink);
    await tester.pumpAndSettle();
    expect(editing.tool, PdfEditTool.ink);
  });

  testWidgets('armed markup is the current tool and participates in history',
      (tester) async {
    final editing = await pumpToolbar(tester, width: 500);
    editing.markupTool = PdfMarkupKind.highlight;
    await tester.pump();

    final switcher = find.byKey(const ValueKey('pdf-mobile-current-tool'));
    expect(tester.getSemantics(switcher).label, contains('Highlight'));
    expect(editing.tool, isNull,
        reason: 'markup keeps native text-selection gestures enabled');

    editing.tool = PdfEditTool.note;
    await tester.pump();
    await tester.tap(switcher);
    await tester.pumpAndSettle();
    final markup = find.byKey(const ValueKey('pdf-recent-markup-highlight'));
    expect(markup, findsOneWidget);

    await tester.tap(markup);
    await tester.pumpAndSettle();
    expect(editing.markupTool, PdfMarkupKind.highlight);
    expect(tester.getSemantics(switcher).label, contains('Highlight'));
  });

  testWidgets('tool switcher fills its surface and clears only from popup',
      (tester) async {
    final editing = await pumpToolbar(tester, width: 590);
    final switcher = find.byKey(const ValueKey('pdf-mobile-current-tool'));
    expect(tester.getSemantics(switcher).label, contains('Hand'));
    expect(
        find.descendant(
            of: switcher, matching: find.byIcon(Icons.pan_tool_alt)),
        findsOneWidget,
        reason: 'the Hand navigation mode is visibly distinct from Select');

    editing.tool = PdfEditTool.note;
    await tester.pump();

    final surface =
        find.byKey(const ValueKey('pdf-mobile-current-tool-surface'));
    expect(find.byKey(const ValueKey('pdf-mobile-clear-tool')), findsNothing);
    expect(tester.getRect(switcher), tester.getRect(surface),
        reason: 'the popup target fills the entire shaded tool surface');
    expect(tester.getSize(surface).width, 180,
        reason: 'the shaded popup button does not consume the whole dock');

    await tester.tap(switcher);
    await tester.pumpAndSettle();
    final clear = find.byKey(const ValueKey('pdf-recent-tool-clear'));
    expect(clear, findsOneWidget);
    await tester.tap(clear);
    await tester.pumpAndSettle();

    expect(editing.tool, isNull);
    expect(tester.getSemantics(switcher).label, contains('Hand'));
    expect(
        find.descendant(
            of: switcher, matching: find.byIcon(Icons.pan_tool_alt)),
        findsOneWidget);
    expect(clear, findsNothing,
        reason: 'clearing closes the popup and returns to Hand mode');

    // Clearing does not erase history: the prior tool remains one tap away.
    await tester.tap(find.byKey(const ValueKey('pdf-mobile-current-tool')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-recent-tool-note')), findsOneWidget);
  });

  testWidgets('clear remains available in the popup on a narrow phone',
      (tester) async {
    final editing = await pumpToolbar(tester, width: 320);
    editing.tool = PdfEditTool.note;
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('pdf-mobile-current-tool')));
    await tester.pumpAndSettle();
    final clear = find.byKey(const ValueKey('pdf-recent-tool-clear'));
    expect(clear, findsOneWidget);

    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(editing.tool, isNull);
  });

  testWidgets('Select group directly arms Select and closes the tool sheet',
      (tester) async {
    final editing = await pumpToolbar(tester);

    Future<void> chooseSelect() async {
      await tester.tap(find.byKey(const ValueKey('pdf-tools-handle')));
      await tester.pumpAndSettle();
      final selectGroup = find.byKey(const ValueKey('pdf-group-tab-select'));
      expect(selectGroup, findsOneWidget);

      await tester.tap(selectGroup);
      await tester.pumpAndSettle();
      expect(editing.tool, PdfEditTool.select);
      final switcher = find.byKey(const ValueKey('pdf-mobile-current-tool'));
      expect(tester.getSemantics(switcher).label, contains('Select'));
      expect(
          find.descendant(of: switcher, matching: find.byIcon(Icons.near_me)),
          findsOneWidget,
          reason: 'Select keeps its arrow instead of looking like Hand');
      expect(
          find.descendant(
              of: switcher, matching: find.byIcon(Icons.pan_tool_alt)),
          findsNothing);
      expect(selectGroup, findsNothing,
          reason: 'choosing the one-option group closes the sheet');
    }

    expect(editing.tool, isNull);
    await chooseSelect();

    editing.tool = PdfEditTool.ink;
    await tester.pump();
    await chooseSelect();
  });

  testWidgets('a selection surfaces quick actions, not creation swatches',
      (tester) async {
    final editing = await pumpToolbar(tester);
    editing.tool = PdfEditTool.ink; // swatches up while a colour tool is armed
    await tester.pump();
    expect(swatch, findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    // slot 0 is the Square annotation - selectable, unlike the Link/Widget
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

  testWidgets('a selected form field exposes its mobile toolbar controls',
      (tester) async {
    final editing = await pumpToolbar(tester, bytes: buildAcroFormPdf());
    expect(editing.selectFormWidgetAt(0, 186, 712), isTrue);
    await tester.pump();

    expect(
        find.byKey(const ValueKey('pdf-selected-form-more')), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'the field controls fit the 380px mobile dock');

    await tester.tap(find.byKey(const ValueKey('pdf-selected-form-more')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('pdf-selected-form-edit')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('pdf-selected-form-rename')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('pdf-selected-form-style')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-selected-form-type-text')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-selected-form-type-checkbox')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-selected-form-type-button')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('pdf-selected-form-delete')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-selected-form-flatten')),
        findsOneWidget);
  });

  testWidgets('a selected content element surfaces mobile edit actions',
      (tester) async {
    final editing = await pumpToolbar(tester, bytes: buildMultiPagePdf(1));
    editing.tool = PdfEditTool.content;
    expect(editing.selectElementAt(0, 80, 725), isTrue);
    await tester.pump();

    expect(find.byKey(const ValueKey('pdf-mobile-delete-element')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('pdf-replace-element-text')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('pdf-reflow-element-text')), findsOneWidget);
    expect(swatch, findsNothing,
        reason: 'content element actions take precedence over swatches');

    await tester.tap(find.byKey(const ValueKey('pdf-mobile-delete-element')));
    await tester.pump();
    expect(editing.selectedElement, isNull);
    expect(editing.elementsOn(0).elements, isEmpty);
  });
}
