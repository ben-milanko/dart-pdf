import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opening the tune popup over a live free-text editing session must not drop
/// the text selection: the highlight shows the user which text the popup's
/// controls will restyle. On some platforms the popup blurs the field, so the
/// editor reclaims focus when asked.
void main() {
  const editorKey = ValueKey('pdf-freetext-editor');
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  Future<void> tap(WidgetTester tester, Offset position) async {
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<(PdfEditingController, PdfViewerController)> pumpEditor(
      WidgetTester tester, {
      bool withToolbar = false}) async {
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
          ),
        ),
        bottomNavigationBar: withToolbar
            ? PdfEditingToolbar(controller: editing, viewerController: viewer)
            : null,
      ),
    ));
    await tester.pump();
    return (editing, viewer);
  }

  Future<TextField> openEditorWithSelection(
      WidgetTester tester, PdfEditingController editing) async {
    editing.addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello world');
    await tester.pump();
    editing.tool = PdfEditTool.select;
    await tester.pump();

    await tap(tester, view(200, 630)); // select
    await tap(tester, view(200, 630)); // edit
    expect(find.byKey(editorKey), findsOneWidget);

    final field = tester.widget<TextField>(find.byKey(editorKey));
    field.controller!.value = const TextEditingValue(
      text: 'Hello world',
      selection: TextSelection(baseOffset: 6, extentOffset: 11),
    );
    await tester.pump();
    expect(editing.hasEditingTextSelection, isTrue);
    return field;
  }

  testWidgets('the editor reclaims focus (and its selection) when asked',
      (tester) async {
    final (editing, _) = await pumpEditor(tester);
    final field = await openEditorWithSelection(tester, editing);
    expect(field.focusNode!.hasFocus, isTrue);

    // Simulate the tune popup opening: the hold keeps the session alive while
    // the field blurs (as it can on desktop/web), so no commit fires.
    editing.beginEditingTextFocusHold();
    field.focusNode!.unfocus();
    await tester.pump();
    expect(field.focusNode!.hasFocus, isFalse);
    expect(find.byKey(editorKey), findsOneWidget,
        reason: 'the hold keeps the editor open through the blur');

    // The refocus request pulls the keyboard back to the field.
    editing.refocusEditingText();
    await tester.pump();
    await tester.pump();
    expect(field.focusNode!.hasFocus, isTrue,
        reason: 'the editor reclaims focus so the selection stays visible');
    expect(editing.hasEditingTextSelection, isTrue);
    expect(field.controller!.selection,
        const TextSelection(baseOffset: 6, extentOffset: 11));

    editing.endEditingTextFocusHold();
    await tester.pump();
  });

  testWidgets('refocusEditingText is a no-op with no editor open',
      (tester) async {
    final (editing, _) = await pumpEditor(tester);
    final before = editing.refocusEditingTextRevision;
    editing.refocusEditingText();
    expect(editing.refocusEditingTextRevision, before,
        reason: 'nothing to refocus when no text editor is open');
  });

  testWidgets('opening the tune popup asks the editor to reclaim focus',
      (tester) async {
    final (editing, _) = await pumpEditor(tester, withToolbar: true);
    await openEditorWithSelection(tester, editing);

    final before = editing.refocusEditingTextRevision;
    // the selected free text's tune trigger is the font chip ("Aa …")
    await tester.tap(find.text('Aa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // the tune popup is open and it requested a refocus so the selection
    // highlight survives the open on platforms that blur the field
    expect(find.byKey(const ValueKey('pdf-text-fill-1')), findsOneWidget);
    expect(editing.refocusEditingTextRevision, greaterThan(before));
  });
}
