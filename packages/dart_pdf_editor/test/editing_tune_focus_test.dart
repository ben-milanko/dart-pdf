import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('the editor reclaims focus while the tune popup keeps it',
      (tester) async {
    final (editing, _) = await pumpEditor(tester);
    final field = await openEditorWithSelection(tester, editing);
    expect(field.focusNode!.hasFocus, isTrue);

    // The tune popup opens: it keeps the editor focused for the whole session
    // (both the commit-hold and the keep-focused window).
    editing.beginEditingTextFocusHold();
    editing.beginKeepEditingTextFocused();
    expect(editing.shouldKeepEditingTextFocused, isTrue);

    // A control tap steals focus (as it does on desktop/web). The field takes
    // it straight back, so the selection - and its highlight - survives.
    field.focusNode!.unfocus();
    await tester.pump();
    await tester.pump();
    expect(field.focusNode!.hasFocus, isTrue,
        reason: 'the editor reclaims focus so the selection stays visible');
    expect(find.byKey(editorKey), findsOneWidget,
        reason: 'reclaiming focus never commits the box');
    expect(editing.hasEditingTextSelection, isTrue);
    expect(field.controller!.selection,
        const TextSelection(baseOffset: 6, extentOffset: 11));

    // A second control tap (e.g. applying another style) must keep it too.
    field.focusNode!.unfocus();
    await tester.pump();
    await tester.pump();
    expect(field.focusNode!.hasFocus, isTrue,
        reason: 'the highlight survives repeated edits from the popup');

    editing.endKeepEditingTextFocused();
    editing.endEditingTextFocusHold();
    await tester.pump();
  });

  testWidgets('a popup value field keeps the keyboard - no reclaim',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(2));
    final viewer = PdfViewerController();
    final valueField = FocusNode();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    addTearDown(valueField.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned.fill(
            child: ListenableBuilder(
              listenable: editing,
              builder: (context, _) => PdfViewer(
                initialFit: PdfViewerFit.width,
                document: editing.document,
                controller: viewer,
                editing: editing,
              ),
            ),
          ),
          // stands in for a tune-popup value field - a real text input the
          // user taps to type an exact number
          Positioned(width: 1, height: 1, child: TextField(focusNode: valueField)),
        ]),
      ),
    ));
    await tester.pump();

    final field = await openEditorWithSelection(tester, editing);
    editing.beginEditingTextFocusHold();
    editing.beginKeepEditingTextFocused();

    // focus moves to the popup's value field: the editor must NOT snatch it
    // back, or the user could never type into the popup
    valueField.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(valueField.hasFocus, isTrue,
        reason: 'the popup value field keeps the keyboard');
    expect(field.focusNode!.hasFocus, isFalse);
    expect(find.byKey(editorKey), findsOneWidget,
        reason: 'the session stays open (held), just not focused');

    editing.endKeepEditingTextFocused();
    editing.endEditingTextFocusHold();
    await tester.pump();
  });

  testWidgets('keeping focus is only active while editing text',
      (tester) async {
    final (editing, _) = await pumpEditor(tester);
    // no editor open: the window is inert
    editing.beginKeepEditingTextFocused();
    expect(editing.shouldKeepEditingTextFocused, isFalse,
        reason: 'nothing to keep focused when no text editor is open');
    editing.endKeepEditingTextFocused();
  });

  testWidgets('opening the tune popup keeps the editor focused',
      (tester) async {
    final (editing, _) = await pumpEditor(tester, withToolbar: true);
    await openEditorWithSelection(tester, editing);

    expect(editing.shouldKeepEditingTextFocused, isFalse);
    // the selected free text's tune trigger is the font chip ("Aa …")
    await tester.tap(find.text('Aa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // the tune popup is open and it holds the editing field's focus so the
    // selection highlight survives the open on platforms that blur the field
    expect(find.byKey(const ValueKey('pdf-text-fill-1')), findsOneWidget);
    expect(editing.shouldKeepEditingTextFocused, isTrue);

    // closing the popup releases the window
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(editing.shouldKeepEditingTextFocused, isFalse);
  });
}
