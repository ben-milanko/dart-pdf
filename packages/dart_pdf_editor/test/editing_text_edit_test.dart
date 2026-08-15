import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart'
    show CupertinoTextSelectionToolbar, CupertinoTextSelectionToolbarButton;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_overlay.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The editing overlay's preview painter, read through a dynamic cast
/// (the painter class is private to the library).
dynamic overlayPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(find
        .descendant(
            of: find.byType(EditingPageOverlay),
            matching: find.byType(CustomPaint))
        .first)
    .painter;

void main() {
  const editorKey = ValueKey('pdf-freetext-editor');

  group('restyling free text through the controller', () {
    test('restyleSelectedText changes font and size, keeps text and author',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.author = 'Ben'
        ..addFreeText(0, const PdfRect(100, 600, 300, 650), 'Styled');
      expect(editing.selectAnnotation(0, 0), isTrue);
      expect(editing.canRestyleSelectedText, isTrue);

      editing.restyleSelectedText(font: PdfStandardFont.times, size: 24);

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.contents, 'Styled');
      expect(annotation.author, 'Ben');
      expect(annotation.defaultAppearance, contains('/TiRo 24 Tf'));
      // the selection survives the rewrite, so consecutive restyles work
      expect(
          editing.selectedTextStyle, (font: PdfStandardFont.times, size: 24.0));

      editing.restyleSelectedText(size: 8);
      expect(editing.document.page(0).annotations.single.defaultAppearance,
          contains('/TiRo 8 Tf'));
    });

    test('setSelectedText preserves the font family and size', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..fontFamily = PdfStandardFont.courier
        ..preferences.fontSize = 18
        ..addFreeText(0, const PdfRect(100, 600, 300, 650), 'Original');
      expect(editing.selectAnnotation(0, 0), isTrue);

      editing.setSelectedText('Rewritten');

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.contents, 'Rewritten');
      expect(annotation.defaultAppearance, contains('/Cour 18 Tf'));
    });

    test('autosizeSelectedTextBox fits the selected box to its contents', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..fontFamily = PdfStandardFont.courier
        ..preferences.fontSize = 18
        ..addFreeText(0, const PdfRect(100, 600, 500, 720), 'Wide line\nshort');
      expect(editing.selectAnnotation(0, 0), isTrue);

      editing.autosizeSelectedTextBox();

      final annotation = editing.document.page(0).annotations.single;
      final expectedWidth =
          measureStandardText('Wide line', 18, font: PdfStandardFont.courier) +
              6;
      expect(annotation.rect.left, 100);
      expect(annotation.rect.top, 720);
      expect(annotation.rect.width, closeTo(expectedWidth, 0.01));
      expect(annotation.rect.height, closeTo(18 * 1.2 * 2 + 6, 0.01));
      expect(editing.selectedAnnotation, isNotNull);
    });

    test('textAlign preference flows into new free text', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.textAlign = PdfTextAlign.center
        ..addFreeText(0, const PdfRect(100, 600, 360, 650), 'Centered');

      final style = editing.document.page(0).annotations.single.freeTextStyle!;
      expect(style.alignment, PdfTextAlign.center);
    });

    test('setSelectedTextAlign changes the box and the creation default', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addFreeText(0, const PdfRect(100, 600, 360, 650), 'Aligned');
      expect(editing.selectAnnotation(0, 0), isTrue);
      expect(editing.selectedTextAlign, PdfTextAlign.left);

      editing.setSelectedTextAlign(PdfTextAlign.right);

      expect(
          editing.document.page(0).annotations.single.freeTextStyle!.alignment,
          PdfTextAlign.right);
      // the selection survives the rewrite
      expect(editing.selectedTextAlign, PdfTextAlign.right);
      // and right becomes the default for new boxes
      expect(editing.preferences.textAlign, PdfTextAlign.right);
    });

    test('restyleSelectedText preserves alignment across a size change', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.textAlign = PdfTextAlign.center
        ..addFreeText(0, const PdfRect(100, 600, 360, 650), 'Centered');
      expect(editing.selectAnnotation(0, 0), isTrue);
      expect(editing.selectedTextAlign, PdfTextAlign.center);

      editing.restyleSelectedText(size: 22);

      expect(editing.selectedTextAlign, PdfTextAlign.center);
      expect(editing.document.page(0).annotations.single.defaultAppearance,
          contains('22 Tf'));
    });

    test('addFreeTextRich applies the alignment default', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.textAlign = PdfTextAlign.right;
      editing.addFreeTextRich(
          0, const PdfRect(100, 600, 360, 650), [const PdfFreeTextRun('Rich')]);

      final style = editing.document.page(0).annotations.single.freeTextStyle!;
      expect(style.alignment, PdfTextAlign.right);
    });

    test('text fill and border preferences flow into new free text', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.strokeWidth = 3
        ..preferences.textFillColor = const Color(0xFFFFF59D)
        ..preferences.textBorderColor = const Color(0xFF1E88E5)
        ..addFreeText(0, const PdfRect(100, 600, 300, 660), 'Boxed');

      final style = editing.document.page(0).annotations.single.freeTextStyle!;
      expect(style.fillColor, 0xFFF59D);
      expect(style.borderColor, 0x1E88E5);
      expect(style.borderWidth, 3);
    });

    test('text opacity flows through creation, restyling, and text edits', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.opacity = 0.4
        ..addFreeText(0, const PdfRect(100, 600, 300, 660), 'Faded');
      expect(editing.selectAnnotation(0, 0), isTrue);
      expect(editing.selectedAnnotation!.behavior.supportsOpacity, isTrue);
      expect(
          editing.selectedAnnotation!.appearanceOpacity, closeTo(0.4, 1e-9));

      expect(editing.restyleSelected(opacity: 0.65), isTrue);
      expect(
          editing.selectedAnnotation!.appearanceOpacity, closeTo(0.65, 1e-9));

      editing.setSelectedText('Still faded');
      expect(editing.selectedAnnotation!.contents, 'Still faded');
      expect(
          editing.selectedAnnotation!.appearanceOpacity, closeTo(0.65, 1e-9));
    });

    test('restyleSelectedText sets, keeps, and clears fill and border', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addFreeText(0, const PdfRect(100, 600, 300, 660), 'Plain');
      expect(editing.selectAnnotation(0, 0), isTrue);

      PdfFreeTextStyle style() =>
          editing.document.page(0).annotations.single.freeTextStyle!;

      editing.restyleSelectedText(
          fill: (0x43A047,), border: (0xE53935,), borderWidth: 2);
      expect(style().fillColor, 0x43A047);
      expect(style().borderColor, 0xE53935);
      expect(style().borderWidth, 2);

      // omitted box params survive an unrelated restyle
      editing.restyleSelectedText(font: PdfStandardFont.times);
      expect(style().fillColor, 0x43A047);
      expect(style().borderColor, 0xE53935);
      expect(style().borderWidth, 2);

      // the wrapped null clears, unlike the omitted parameter
      editing.restyleSelectedText(fill: (null,), border: (null,));
      expect(style().fillColor, isNull);
      expect(style().borderColor, isNull);
      expect(style().borderWidth, 0);
    });

    test('restyleSelectedTextRange changes only the selected substring', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello world');
      expect(editing.selectAnnotation(0, 0), isTrue);

      expect(
          editing.restyleSelectedTextRange(6, 11,
              font: PdfStandardFont.timesBold, size: 24, color: 0xFF0000),
          isTrue);

      final annotation = editing.document.page(0).annotations.single;
      final content = latin1.decode(
          editing.document.cos.decodeStreamData(annotation.normalAppearance!));
      expect(annotation.contents, 'Hello world');
      expect(content, contains('/Helv 14 Tf'));
      expect(content, contains('(Hello ) Tj'));
      expect(content, contains('/TimesBold 24 Tf'));
      expect(content, contains('1 0 0 rg'));
      expect(content, contains('(world) Tj'));
    });

    test('editing text selection drags do not notify on every range change',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      var notifications = 0;
      editing.addListener(() => notifications++);

      editing.setEditingText(true);
      expect(notifications, 1);

      editing.setEditingTextSelection(
          const TextSelection(baseOffset: 0, extentOffset: 3));
      expect(notifications, 2);

      editing.setEditingTextSelection(
          const TextSelection(baseOffset: 0, extentOffset: 5));
      expect(notifications, 2);

      editing.setEditingTextSelection(const TextSelection.collapsed(offset: 5));
      expect(notifications, 3);
    });

    test('text fill and border persist as preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final a = PdfEditingPreferences();
      await a.ready;
      expect(a.textFillColor, isNull);
      expect(a.textBorderColor, isNull);
      a.textFillColor = const Color(0xFFFFF59D);
      a.textBorderColor = const Color(0xFF1E88E5);
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.textFillColor, const Color(0xFFFFF59D));
      expect(b.textBorderColor, const Color(0xFF1E88E5));

      b.textFillColor = null;
      await pumpEventQueue();
      final c = PdfEditingPreferences();
      await c.ready;
      expect(c.textFillColor, isNull);
      expect(c.textBorderColor, const Color(0xFF1E88E5));
    });

    test('the font family persists as a preference', () async {
      SharedPreferences.setMockInitialValues({});
      final a = PdfEditingPreferences();
      await a.ready;
      expect(a.fontFamily, PdfStandardFont.helvetica);
      a.fontFamily = PdfStandardFont.courier;
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.fontFamily, PdfStandardFont.courier);
    });
  });

  group('in-place text editing in the viewer', () {
    // 800px viewport over a 612pt page
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    /// Drags in two steps: a recognizer that accepts on a single large
    /// move never delivers a pan update for it.
    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await gesture.moveTo(to);
      await gesture.up();
      await tester.pump();
    }

    /// Flushes the viewer's debounced settle timers (200/250ms), which a
    /// document-swap relayout can arm.
    Future<void> settle(WidgetTester tester) =>
        tester.pumpAndSettle(const Duration(milliseconds: 300));

    /// Touch taps resolve only after the viewer's double-tap timeout.
    Future<void> tap(WidgetTester tester, Offset position) async {
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<(PdfEditingController, PdfViewerController)> pumpEditor(
        WidgetTester tester) async {
      // the preference tests above seed the global mock store - these
      // tests assert on default styles, so start from an empty one
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
        ),
      ));
      await tester.pump();
      return (editing, viewer);
    }

    testWidgets('Alt+Z autosizes the selected free-text box', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..fontFamily = PdfStandardFont.courier
        ..preferences.fontSize = 18
        ..addFreeText(0, const PdfRect(100, 600, 500, 720), 'Wide line')
        ..selectAnnotation(0, 0);
      await tester.pump();

      // Focus the viewer the way a user would before using a shortcut.
      await tester.tapAt(view(400, 400));
      await tester.pump();
      editing.selectAnnotation(0, 0);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();

      final annotation = editing.document.page(0).annotations.single;
      final expectedWidth =
          measureStandardText('Wide line', 18, font: PdfStandardFont.courier) +
              6;
      expect(annotation.rect.width, closeTo(expectedWidth, 0.01));
      await settle(tester);
    });

    testWidgets('dragging out a text box opens an inline editor that commits',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.freeText;
      await tester.pump();

      await drag(tester, view(100, 700), view(300, 640));

      // the editor is open in place - nothing committed yet, no dialog
      expect(find.byKey(editorKey), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(editing.isEditingText, isTrue);
      expect(editing.document.page(0).annotations, isEmpty);

      await tester.enterText(find.byKey(editorKey), 'Hello in place');
      await tap(tester, view(450, 400)); // outside the box: commit

      expect(find.byKey(editorKey), findsNothing);
      expect(editing.isEditingText, isFalse);
      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'FreeText');
      expect(annotation.contents, 'Hello in place');
      await settle(tester);
    });

    testWidgets('the inline text editor previews opacity changes',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..preferences.opacity = 0.25
        ..tool = PdfEditTool.freeText;
      await tester.pump();

      await drag(tester, view(100, 700), view(300, 640));
      TextField field() => tester.widget<TextField>(find.byKey(editorKey));
      expect(field().style!.color!.a, closeTo(0.25, 1e-6));

      editing.preferences.opacity = 0.6;
      await tester.pump();
      expect(field().style!.color!.a, closeTo(0.6, 1e-6));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await settle(tester);
    });

    testWidgets('tapping without dragging places a default-sized text box',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.freeText;
      await tester.pump();

      // a plain tap (no drag) opens the inline editor at a default size
      await tap(tester, view(150, 650));
      expect(find.byKey(editorKey), findsOneWidget);
      expect(editing.document.page(0).annotations, isEmpty);

      await tester.enterText(find.byKey(editorKey), 'Tapped in');
      await tap(tester, view(450, 500)); // outside the box: commit

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'FreeText');
      expect(annotation.contents, 'Tapped in');
      await settle(tester);
    });

    testWidgets('a fresh text box is focused for typing immediately',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.freeText;
      await tester.pump();

      await drag(tester, view(100, 700), view(300, 640));
      await tester.pump();

      // the drag's pointer-down put focus on the viewer's own node, so
      // the field's autofocus alone is ignored - typing must still land
      // in the editor without clicking into it first
      final field = tester.widget<TextField>(find.byKey(editorKey));
      expect(field.focusNode!.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await settle(tester);
    });

    testWidgets('the inline editor follows RTL text while typing',
        (tester) async {
      const rtl = 'ڕێباز';
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.freeText;
      await tester.pump();

      await drag(tester, view(100, 700), view(300, 640));
      expect(find.byKey(editorKey), findsOneWidget);

      await tester.enterText(find.byKey(editorKey), rtl);
      await tester.pump();

      final field = tester.widget<TextField>(find.byKey(editorKey));
      expect(field.textDirection, TextDirection.rtl);
      expect(field.textAlign, TextAlign.start);
      expect(Directionality.of(tester.element(find.byKey(editorKey))),
          TextDirection.rtl);

      await tap(tester, view(450, 400)); // outside the box: commit
      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.contents, rtl);
      expect(
          (editing.document.cos.resolve(annotation.dict['Q']) as CosInteger)
              .value,
          2);
      await settle(tester);
    });

    testWidgets('Escape keeps a newly placed box, committing what was typed',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.freeText;
      await tester.pump();

      await drag(tester, view(100, 700), view(300, 640));
      await tester.enterText(find.byKey(editorKey), 'keep me');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byKey(editorKey), findsNothing);
      expect(editing.isEditingText, isFalse);
      // Escape finishes the box rather than discarding it - losing the box
      // you just placed read as Escape "deleting" the annotation
      expect(editing.document.page(0).annotations, hasLength(1));
      expect(editing.document.page(0).annotations.single.contents, 'keep me');
      expect(editing.tool, PdfEditTool.freeText, reason: 'tool stays armed');
      await settle(tester);
    });

    testWidgets('two escapes: first commits the box, second backs out the tool',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.freeText;
      await tester.pump();

      await drag(tester, view(100, 700), view(300, 640));
      await tester.enterText(find.byKey(editorKey), 'keep me');
      await tester.pump();

      // first Escape: commit and close, tool stays armed
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(editorKey), findsNothing);
      expect(editing.document.page(0).annotations, hasLength(1));
      expect(editing.tool, PdfEditTool.freeText);

      // second Escape: the viewer reclaimed focus on close, so its own
      // shortcut runs and backs the tool out to none
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editing.tool, isNull,
          reason: 'a second Escape must reach the viewer and disarm the tool');
      await settle(tester);
    });

    testWidgets('Escape on an empty new box adds nothing', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.freeText;
      await tester.pump();

      await drag(tester, view(100, 700), view(300, 640));
      // no text typed
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byKey(editorKey), findsNothing);
      expect(editing.document.page(0).annotations, isEmpty,
          reason: 'an empty box has nothing to keep');
      await settle(tester);
    });

    testWidgets('Escape releases keyboard focus, not just the editor',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.freeText;
      await tester.pump();

      await drag(tester, view(100, 700), view(300, 640));
      await tester.enterText(find.byKey(editorKey), 'typing');
      await tester.pump();
      final focused = tester.binding.focusManager.primaryFocus;
      expect(focused?.hasFocus, isTrue, reason: 'the field holds focus');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byKey(editorKey), findsNothing);
      expect(focused?.hasFocus, isFalse,
          reason: 'Escape hands the keyboard back, leaving no lingering focus');
      await settle(tester);
    });

    testWidgets('backspace while typing edits text, not the document',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.freeText;
      await tester.pump();

      await drag(tester, view(100, 700), view(300, 640));
      await tester.enterText(find.byKey(editorKey), 'abc');
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      final field = tester.widget<TextField>(find.byKey(editorKey));
      expect(field.controller!.text, 'ab');
      expect(editing.isModified, isFalse,
          reason: 'backspace must not delete annotations or undo edits');
      expect(find.byKey(editorKey), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await settle(tester);
    });

    testWidgets('mouse double-click on free text opens the inline editor',
        (tester) async {
      final (editing, viewer) = await pumpEditor(tester);
      editing.addFreeText(0, const PdfRect(60, 700, 180, 750), 'Original');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();

      // This point also sits over the page-content word "Page". The
      // viewer's raw mouse double-click word selector must stand down so
      // the editing overlay can treat the second click as text-box edit.
      final overTextBoxAndPageText = view(100, 720);
      await tester.tapAt(overTextBoxAndPageText, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 80));
      expect(editing.selectedAnnotation?.subtype, 'FreeText');

      await tester.tapAt(overTextBoxAndPageText, kind: PointerDeviceKind.mouse);
      await tester.pump();

      expect(find.byKey(editorKey), findsOneWidget);
      expect(viewer.selectedText, isEmpty);
      final field = tester.widget<TextField>(find.byKey(editorKey));
      expect(field.controller!.text, 'Original');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editing.document.page(0).annotations, hasLength(1),
          reason: 'Escape (mouse-edit path) must not delete the box');
      await settle(tester);
    });

    testWidgets('tapping the selected free text edits it in place',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addFreeText(0, const PdfRect(100, 600, 300, 660), 'Original');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();

      await tap(tester, view(200, 630)); // first tap selects
      expect(editing.selectedAnnotation?.subtype, 'FreeText');

      await tap(tester, view(200, 630)); // second tap edits
      expect(find.byKey(editorKey), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(editorKey));
      expect(field.controller!.text, 'Original');

      await tester.enterText(find.byKey(editorKey), 'Edited in place');
      await tap(tester, view(450, 400)); // outside: commit

      expect(find.byKey(editorKey), findsNothing);
      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.contents, 'Edited in place');
      // the rewrite kept the original 14pt Helvetica style
      expect(annotation.defaultAppearance, contains('/Helv 14 Tf'));
      await settle(tester);
    });

    testWidgets('Escape while editing existing free text keeps the annotation',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addFreeText(0, const PdfRect(100, 600, 300, 660), 'Original');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();

      await tap(tester, view(200, 630)); // select
      await tap(tester, view(200, 630)); // edit
      expect(find.byKey(editorKey), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byKey(editorKey), findsNothing);
      expect(editing.document.page(0).annotations, hasLength(1),
          reason: 'Escape cancels the edit, it must not delete the box');
      expect(editing.document.page(0).annotations.single.contents, 'Original');
      await settle(tester);
    });

    testWidgets('toolbar edit opens free text inline for character styling',
        (tester) async {
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
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      await tester.pump();

      editing
        ..addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello world')
        ..tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('pdf-edit-selected-text')));
      await tester.pump();
      expect(find.byKey(editorKey), findsOneWidget);
      expect(editing.isEditingText, isTrue);

      final field = tester.widget<TextField>(find.byKey(editorKey));
      field.controller!.value = const TextEditingValue(
        text: 'Hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.pump();
      expect(editing.hasEditingTextSelection, isTrue);

      await tester.scrollUntilVisible(
          find.byTooltip('Stroke, opacity, font'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byTooltip('Stroke, opacity, font'));
      await tester.pumpAndSettle();
      expect(find.byKey(editorKey), findsOneWidget);
      expect(editing.isEditingText, isTrue);
      expect(editing.hasEditingTextSelection, isTrue);

      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-font-std-serif')));
      await tester.pump();

      final span = field.controller!.buildTextSpan(
        context: tester.element(find.byKey(editorKey)),
        style: const TextStyle(),
        withComposing: false,
      );
      final styled = span.children!.whereType<TextSpan>().singleWhere(
            (child) => child.text == 'world',
          );
      expect(styled.style?.fontFamily, 'Times New Roman');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await settle(tester);
    });

    testWidgets('inline text selection can change font size and color',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello world');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();

      await tap(tester, view(200, 630)); // first tap selects
      await tap(tester, view(200, 630)); // second tap edits
      expect(find.byKey(editorKey), findsOneWidget);

      final field = tester.widget<TextField>(find.byKey(editorKey));
      field.controller!.value = const TextEditingValue(
        text: 'Hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.pump();
      expect(editing.hasEditingTextSelection, isTrue);

      expect(
          editing.restyleEditingTextSelection(
              font: PdfStandardFont.timesBold, size: 24, color: 0xFF0000),
          isTrue);
      await tester.pump();

      final span = field.controller!.buildTextSpan(
        context: tester.element(find.byKey(editorKey)),
        style: const TextStyle(),
        withComposing: false,
      );
      final styled = span.children!.whereType<TextSpan>().singleWhere(
            (child) => child.text == 'world',
          );
      expect(styled.style?.color, const Color(0xFFFF0000));
      expect(styled.style?.fontFamily, 'Times New Roman');

      await tap(tester, view(450, 400)); // outside: commit
      final annotation = editing.document.page(0).annotations.single;
      final content = latin1.decode(
          editing.document.cos.decodeStreamData(annotation.normalAppearance!));
      expect(annotation.contents, 'Hello world');
      expect(content, contains('/Helv 14 Tf'));
      expect(content, contains('(Hello ) Tj'));
      expect(content, contains('/TimesBold 24 Tf'));
      expect(content, contains('1 0 0 rg'));
      expect(content, contains('(world) Tj'));
      await settle(tester);
    });

    testWidgets('an embedded font applied to a run previews in its real face',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      final fontBytes =
          File('../pdf_document/test/fonts/DejaVuSans.ttf').readAsBytesSync();
      expect(editing.setCustomFont(fontBytes), isTrue);
      final embedded = editing.activeFont as PdfEmbeddedFont;

      editing.addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello world');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();

      await tap(tester, view(200, 630)); // first tap selects
      await tap(tester, view(200, 630)); // second tap edits

      final field = tester.widget<TextField>(find.byKey(editorKey));
      field.controller!.value = const TextEditingValue(
        text: 'Hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.pump();

      // apply the embedded font to "world" through the public restyle path
      expect(editing.restyleEditingTextSelection(font: embedded), isTrue);
      // let ui.loadFontFromList register the outline bytes and rebuild
      await tester.pumpAndSettle();

      final span = field.controller!.buildTextSpan(
        context: tester.element(find.byKey(editorKey)),
        style: const TextStyle(),
        withComposing: false,
      );
      final styled = span.children!.whereType<TextSpan>().singleWhere(
            (child) => child.text == 'world',
          );
      // the run renders in the registered synthetic family, not the fallback
      expect(styled.style?.fontFamily, startsWith('pdfedit-'));

      await tap(tester, view(450, 400)); // outside: commit
      final annotation = editing.document.page(0).annotations.single;
      final res = editing.document.cos
              .resolve(annotation.normalAppearance!.dictionary['Resources'])
          as CosDictionary;
      final fonts = editing.document.cos.resolve(res['Font']) as CosDictionary;
      // the committed appearance embeds the font (a Type0 face for the run)
      expect(fonts.entries.values.any((ref) {
        final f = editing.document.cos.resolve(ref);
        return f is CosDictionary &&
            (editing.document.cos.resolve(f['Subtype']) as CosName?)?.value ==
                'Type0';
      }), isTrue);
      await settle(tester);
    });

    testWidgets('touch inline style chip changes selected text font',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello world');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();

      await tap(tester, view(200, 630)); // first tap selects
      await tap(tester, view(200, 630)); // second tap edits

      final field = tester.widget<TextField>(find.byKey(editorKey));
      field.controller!.value = const TextEditingValue(
        text: 'Hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('pdf-inline-text-style-chip')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pdf-inline-text-font')));
      await tester.pumpAndSettle();

      final serifRow = find.descendant(
          of: find.byKey(const ValueKey('pdf-font-std-serif')),
          matching: find.text('Serif (Times)'));
      expect(
          tester.widget<Text>(serifRow).style?.fontFamily, 'Times New Roman');
      await tester.tap(find.byKey(const ValueKey('pdf-font-std-serif')));
      await tester.pump();

      final span = field.controller!.buildTextSpan(
        context: tester.element(find.byKey(editorKey)),
        style: const TextStyle(),
        withComposing: false,
      );
      final styled = span.children!.whereType<TextSpan>().singleWhere(
            (child) => child.text == 'world',
          );
      expect(styled.style?.fontFamily, 'Times New Roman');

      await tap(tester, view(450, 400)); // outside: commit
      final annotation = editing.document.page(0).annotations.single;
      final content = latin1.decode(
          editing.document.cos.decodeStreamData(annotation.normalAppearance!));
      expect(content, contains('/TiRo 14 Tf'));
      expect(content, contains('(world) Tj'));
      await settle(tester);
    });

    testWidgets('the inline chip underline button keeps the box in edit mode',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello world');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();

      // enter edit mode with a bare caret (no range selection, so no text
      // selection toolbar floats over the chip): the underline button then
      // styles the whole box and the box must stay in edit mode - tapping a
      // chip button must never commit/deselect it (the mobile report)
      await tap(tester, view(200, 630));
      await tap(tester, view(200, 630));
      expect(find.byKey(editorKey), findsOneWidget);

      final underline =
          find.byKey(const ValueKey('pdf-inline-text-underline'));
      expect(underline, findsOneWidget);
      // invoke the button's handler directly: the chip sits inside scaled,
      // translated chrome that makes a synthetic tap's hit-test unreliable,
      // and the mobile focus-drop it guards against isn't reproducible in a
      // widget test (a tap never blurs a non-focusable button here)
      tester.widget<IconButton>(underline).onPressed!.call();
      await tester.pump();

      // still editing (not committed/deselected) and the box is now underlined
      expect(find.byKey(editorKey), findsOneWidget);
      expect(editing.isEditingText, isTrue);
      final field = tester.widget<TextField>(find.byKey(editorKey));
      expect(field.controller!.text, 'Hello world');
      final span = field.controller!.buildTextSpan(
        context: tester.element(find.byKey(editorKey)),
        style: const TextStyle(),
        withComposing: false,
      );
      final underlined = span.children!
          .whereType<TextSpan>()
          .where((c) => c.style?.decoration == TextDecoration.underline)
          .map((c) => c.text)
          .join();
      expect(underlined, contains('Hello world'));

      editing.textUnderline = false;
      await settle(tester);
    });

    testWidgets('Ctrl+B and Ctrl+I toggle bold/italic on the selection',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello world');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();

      await tap(tester, view(200, 630)); // first tap selects
      await tap(tester, view(200, 630)); // second tap edits

      final field = tester.widget<TextField>(find.byKey(editorKey));
      field.controller!.value = const TextEditingValue(
        text: 'Hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.pump();

      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await press(LogicalKeyboardKey.keyB);
      await press(LogicalKeyboardKey.keyI);

      final span = field.controller!.buildTextSpan(
        context: tester.element(find.byKey(editorKey)),
        style: const TextStyle(),
        withComposing: false,
      );
      final styled = span.children!.whereType<TextSpan>().singleWhere(
            (child) => child.text == 'world',
          );
      expect(styled.style?.fontWeight, FontWeight.bold);
      expect(styled.style?.fontStyle, FontStyle.italic);

      await tap(tester, view(450, 400)); // outside: commit
      final annotation = editing.document.page(0).annotations.single;
      final content = latin1.decode(
          editing.document.cos.decodeStreamData(annotation.normalAppearance!));
      expect(content, contains('/HelvBoldObl 14 Tf'));
      expect(content, contains('(world) Tj'));
      expect(content, contains('(Hello ) Tj'));
      // restyling also moved the persisted creation default; reset it so a
      // later test that builds a controller without clearing prefs still
      // starts from plain Helvetica
      editing.fontFamily = PdfStandardFont.helvetica;
      await settle(tester);
    });

    testWidgets('backspace before a bold run keeps the run bold',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello world');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();

      await tap(tester, view(200, 630));
      await tap(tester, view(200, 630));
      final field = tester.widget<TextField>(find.byKey(editorKey));
      // bold exactly "world" (offsets 6..11)
      field.controller!.value = const TextEditingValue(
        text: 'Hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.pump();
      expect(
          editing.restyleEditingTextSelection(
              font: PdfStandardFont.helveticaBold),
          isTrue);
      await tester.pump();

      // delete the 'o' in "Hello" - the bold run must follow its own
      // characters, not slide down by one (the reported regression)
      field.controller!.value = const TextEditingValue(
        text: 'Hell world',
        selection: TextSelection.collapsed(offset: 4),
      );
      await tester.pump();

      final span = field.controller!.buildTextSpan(
        context: tester.element(find.byKey(editorKey)),
        style: const TextStyle(),
        withComposing: false,
      );
      final bold = span.children!
          .whereType<TextSpan>()
          .where((c) => c.style?.fontWeight == FontWeight.bold)
          .map((c) => c.text)
          .join();
      expect(bold, 'world');

      editing.fontFamily = PdfStandardFont.helvetica;
      await settle(tester);
    });

    testWidgets('Ctrl+U underlines the selection and persists to /RC',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello world');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();

      await tap(tester, view(200, 630));
      await tap(tester, view(200, 630));
      final field = tester.widget<TextField>(find.byKey(editorKey));
      field.controller!.value = const TextEditingValue(
        text: 'Hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      final span = field.controller!.buildTextSpan(
        context: tester.element(find.byKey(editorKey)),
        style: const TextStyle(),
        withComposing: false,
      );
      final styled = span.children!
          .whereType<TextSpan>()
          .singleWhere((c) => c.text == 'world');
      expect(styled.style?.decoration, TextDecoration.underline);

      await tap(tester, view(450, 400)); // commit
      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.richContent, contains('text-decoration:underline'));
      final content = latin1.decode(
          editing.document.cos.decodeStreamData(annotation.normalAppearance!));
      // an underline rule (a filled rectangle) is drawn after the text object
      expect(content.lastIndexOf(' re'), greaterThan(content.lastIndexOf('ET')));
      editing.textUnderline = false;
      await settle(tester);
    });

    testWidgets('the font picker reports an embedded box font, not Sans',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      final fontBytes =
          File('../pdf_document/test/fonts/DejaVuSans.ttf').readAsBytesSync();
      expect(editing.setCustomFont(fontBytes), isTrue);
      final embedded = editing.activeFont as PdfEmbeddedFont;

      editing.addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello');
      await tester.pump();
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();

      final font = editing.selectedTextFont;
      expect(font, isA<PdfEmbeddedFont>());
      expect((font as PdfEmbeddedFont).familyName, embedded.familyName);
      editing.activeFont = null;
      await settle(tester);
    });

    testWidgets('the toolbar font chip shows the embedded face, not Sans',
        (tester) async {
      // regression: the chip parsed only the base-14 family from /DA and
      // collapsed an embedded box to "Sans", while the tune popup's font
      // button reported the real face - so the two disagreed
      SharedPreferences.setMockInitialValues({});
      final fontBytes =
          File('../pdf_document/test/fonts/DejaVuSans.ttf').readAsBytesSync();
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      expect(editing.setCustomFont(fontBytes), isTrue);
      final embedded = editing.activeFont as PdfEmbeddedFont;
      editing.addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello');
      editing.selectAnnotation(0, 0);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));

      final chip = find.byTooltip('Stroke, opacity, font');
      await tester.scrollUntilVisible(chip, 100,
          scrollable: find.byType(Scrollable).first);
      // the chip carries the embedded family name, not the base-14 "Sans"
      expect(
          find.descendant(
              of: chip, matching: find.text(embedded.familyName)),
          findsOneWidget);
      expect(find.descendant(of: chip, matching: find.text('Sans')),
          findsNothing);
      editing.activeFont = null;
    });

    testWidgets('resizing an embedded-font box reflows instead of stretching',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      final fontBytes =
          File('../pdf_document/test/fonts/DejaVuSans.ttf').readAsBytesSync();
      expect(editing.setCustomFont(fontBytes), isTrue);
      editing.addFreeText(
          0, const PdfRect(100, 600, 400, 640), 'reflow me please');
      await tester.pump();
      final box = editing.document.page(0).annotations.single;
      // embedded-font free text now re-wraps on resize (no stretched glyphs)
      expect(box.behavior.resizeBehavior,
          PdfAnnotationResizeBehavior.reflowText);
      editing.activeFont = null;
      await settle(tester);
    });

    testWidgets('reopening a mixed-format box restores its per-run styling',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello world');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();

      // open, bold just "world", commit
      await tap(tester, view(200, 630));
      await tap(tester, view(200, 630));
      var field = tester.widget<TextField>(find.byKey(editorKey));
      field.controller!.value = const TextEditingValue(
        text: 'Hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.pump();
      expect(
          editing.restyleEditingTextSelection(
              font: PdfStandardFont.helveticaBold),
          isTrue);
      await tester.pump();
      await tap(tester, view(450, 400)); // commit
      await settle(tester);

      // the saved box carries /RC describing the bold run
      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.richContent, isNotNull);
      expect(editing.selectAnnotation(0, 0), isTrue);
      final runs = editing.selectedRichRuns!;
      expect(runs.map((r) => r.text).join(), 'Hello world');
      expect(runs.firstWhere((r) => r.text.contains('world')).font,
          PdfStandardFont.helveticaBold);

      // reopen: the editor's span shows "world" bold again, not flattened
      await tap(tester, view(200, 630));
      await tap(tester, view(200, 630));
      expect(find.byKey(editorKey), findsOneWidget);
      field = tester.widget<TextField>(find.byKey(editorKey));
      expect(field.controller!.text, 'Hello world');
      final span = field.controller!.buildTextSpan(
        context: tester.element(find.byKey(editorKey)),
        style: const TextStyle(),
        withComposing: false,
      );
      final styled = span.children!.whereType<TextSpan>().singleWhere(
            (child) => child.text == 'world',
          );
      expect(styled.style?.fontWeight, FontWeight.bold);

      await tap(tester, view(450, 400)); // commit, no change
      editing.fontFamily = PdfStandardFont.helvetica;
      await settle(tester);
    });

    testWidgets('the style menu sets the font family for new text',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));

      // the font controls live in the Insert group's strip (it opens on
      // the freeText tool, whose tune trigger is the font chip)
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('pdf-group-insert')), 80);
      await tester.tap(find.byKey(const ValueKey('pdf-group-insert')));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byTooltip('Stroke, opacity, font'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byTooltip('Stroke, opacity, font'));
      await tester.pumpAndSettle();

      Future<void> pickFont(Key key) async {
        await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(key));
        await tester.pump();
      }

      await pickFont(const ValueKey('pdf-font-std-serif'));
      expect(editing.fontFamily, PdfStandardFont.times);

      await pickFont(const ValueKey('pdf-font-std-mono'));
      expect(editing.fontFamily, PdfStandardFont.courier);

      // the Bold / Italic toggles pick the matching base-14 variant
      await tester.tap(find.byKey(const ValueKey('pdf-font-bold')));
      await tester.pump();
      expect(editing.fontFamily, PdfStandardFont.courierBold);
      await tester.tap(find.byKey(const ValueKey('pdf-font-italic')));
      await tester.pump();
      expect(editing.fontFamily, PdfStandardFont.courierBoldOblique);
      // switching family keeps the bold+italic style
      await pickFont(const ValueKey('pdf-font-std-serif'));
      expect(editing.fontFamily, PdfStandardFont.timesBoldItalic);
    });

    testWidgets('the style menu sets text alignment for new text',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));

      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('pdf-group-insert')), 80);
      await tester.tap(find.byKey(const ValueKey('pdf-group-insert')));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byTooltip('Stroke, opacity, font'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byTooltip('Stroke, opacity, font'));
      await tester.pumpAndSettle();

      // no selection: the buttons set the creation default
      expect(editing.preferences.textAlign, isNull);
      await tester.tap(find.byKey(const ValueKey('pdf-text-align-center')));
      await tester.pump();
      expect(editing.preferences.textAlign, PdfTextAlign.center);

      await tester.tap(find.byKey(const ValueKey('pdf-text-align-right')));
      await tester.pump();
      expect(editing.preferences.textAlign, PdfTextAlign.right);
    });

    testWidgets('the style menu sets text colour, fill, and border defaults',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));

      // the text fill/border rows live in the Insert group's strip
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('pdf-group-insert')), 80);
      await tester.tap(find.byKey(const ValueKey('pdf-group-insert')));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byTooltip('Stroke, opacity, font'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byTooltip('Stroke, opacity, font'));
      await tester.pumpAndSettle();

      // foreground red is slot 0, marker yellow is slot 1, blue is slot 3
      await tester.tap(find.byKey(const ValueKey('pdf-text-color-0')));
      await tester.pump();
      expect(editing.color, PdfEditingToolbar.defaultPalette[0]);
      expect(find.byKey(const ValueKey('pdf-text-color-none')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('pdf-text-fill-1')));
      await tester.pump();
      expect(editing.preferences.textFillColor, PdfEditingToolbar.defaultPalette[1]);

      await tester.tap(find.byKey(const ValueKey('pdf-text-border-3')));
      await tester.pump();
      expect(editing.preferences.textBorderColor, PdfEditingToolbar.defaultPalette[3]);

      await tester.tap(find.byKey(const ValueKey('pdf-text-fill-none')));
      await tester.pump();
      expect(editing.preferences.textFillColor, isNull);
      expect(editing.preferences.textBorderColor, PdfEditingToolbar.defaultPalette[3]);
    });

    testWidgets('the style menu restyles the selected text box',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.strokeWidth = 2.5
        ..addFreeText(0, const PdfRect(100, 600, 300, 660), 'Boxed');
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      editing.selectAnnotation(0, 0);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      expect(editing.canRestyleSelectedText, isTrue);

      // a selected text box raises the selection strip; its tune trigger
      // is the font chip (the first of strip/dock scrollables)
      await tester.scrollUntilVisible(
          find.byTooltip('Stroke, opacity, font'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byTooltip('Stroke, opacity, font'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pdf-text-fill-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-text-border-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-text-color-3')));
      await tester.pumpAndSettle();

      final style = editing.document.page(0).annotations.single.freeTextStyle!;
      expect(style.color, 0x1E88E5);
      expect(style.fillColor, 0xFFD100);
      expect(style.borderColor, 0xE53935);
      expect(style.borderWidth, 2.5);
      expect(editing.document.page(0).annotations.single.contents, 'Boxed');
    });

    testWidgets('the inline editor previews the fill of a fresh box',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..preferences.textFillColor = const Color(0xFFFFF59D)
        ..tool = PdfEditTool.freeText;
      await tester.pump();

      await drag(tester, view(100, 700), view(300, 640));
      await tester.pump();

      final box = tester.widget<Container>(find
          .ancestor(of: find.byKey(editorKey), matching: find.byType(Container))
          .first);
      expect(box.color, const Color(0xFFFFF59D));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await settle(tester);
    });

    testWidgets('the inline editor opens without shifting the text',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addFreeText(0, const PdfRect(100, 600, 300, 660), 'Steady');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();

      await tap(tester, view(200, 630)); // select
      await tap(tester, view(200, 630)); // edit

      // the TextField's content area must sit exactly on the annotation
      // box - the chrome border lives in the inflate(2) gutter outside.
      // (It used to start 2px up-left, so the text jumped on open.)
      expect(tester.getTopLeft(find.byKey(editorKey)),
          offsetMoreOrLessEquals(view(100, 660), epsilon: 0.1));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await settle(tester);
    });

    testWidgets('native text handles and menu counter-scale while zoomed',
        (tester) async {
      final (editing, viewer) = await pumpEditor(tester);
      editing.addFreeText(0, const PdfRect(100, 600, 300, 660), 'Zoom handles');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();

      await tap(tester, view(200, 630)); // select
      await tap(tester, view(200, 630)); // edit
      // zoom is px/pt now; the handles counter-scale the transform zoom, so
      // aim for a 2× transform scale (2 × fit-width in px/pt)
      viewer.setZoom(2 * scale);
      await tester.pump();

      final field = tester.widget<TextField>(find.byKey(editorKey));
      expect(field.cursorWidth, closeTo(1, 0.01));
      final scaled = field.selectionControls!;
      expect(scaled.getHandleSize(20).width, closeTo(18, 0.01));
      expect(field.contextMenuBuilder, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await settle(tester);
    });

    testWidgets('the long-press selection menu holds its place while zoomed',
        (tester) async {
      // The zoom transform used to drag the menu with it: Flutter places it
      // through a CompositedTransformFollower linked to the field, which
      // re-applies the field's scale to a menu already laid out in screen
      // coordinates. At 2x that displaced it by the whole distance from the
      // screen origin to the field - off-screen on a phone, so a long press
      // in a zoomed text box looked like it did nothing.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'pasteable'};
        }
        if (call.method == 'Clipboard.hasStrings') {
          return <String, dynamic>{'value': true};
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final (editing, viewer) = await pumpEditor(tester);
      // sits mid-viewport both unzoomed and at 2x, so neither menu is
      // clamped by a screen edge
      editing.addFreeText(0, const PdfRect(200, 550, 380, 600), 'Zoom menu');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();
      await tap(tester, view(290, 575)); // select
      await tap(tester, view(290, 575)); // edit

      /// The bounds of the menu's buttons - the visible menu. Its own
      /// widget lays out over the whole screen, and which buttons the menu
      /// offers depends on the selection, so measure the buttons and let
      /// the caller compare centers.
      Rect menuBounds() {
        final buttons = find.descendant(
            of: find.byType(CupertinoTextSelectionToolbar),
            matching: find.byType(CupertinoTextSelectionToolbarButton));
        expect(buttons, findsWidgets);
        return List.generate(buttons.evaluate().length, (i) => i)
            .map((i) => tester.getRect(buttons.at(i)))
            .reduce((a, b) => a.expandToInclude(b));
      }

      /// Long-presses the middle of the editor and returns where the menu
      /// landed relative to the anchor the framework measured for it, plus
      /// the height of its buttons.
      Future<(Offset, double)> pressAndMeasure() async {
        final field = tester.getRect(find.byKey(editorKey));
        final gesture = await tester.startGesture(field.center,
            kind: PointerDeviceKind.touch);
        await tester.pump(const Duration(milliseconds: 700));
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final menu = menuBounds();
        // the anchor is in screen coordinates, and the menu is supposed to
        // be laid out around it - whatever the field's own transform is
        final anchor = tester
            .state<EditableTextState>(find.byType(EditableText))
            .contextMenuAnchors
            .primaryAnchor;
        return (
          Offset(menu.center.dx - anchor.dx, menu.bottom - anchor.dy),
          menu.height,
        );
      }

      final (unzoomedOffset, unzoomedHeight) = await pressAndMeasure();
      // on the anchor (within the menu's own padding) and above it
      expect(unzoomedOffset.dx, closeTo(0, 12));
      expect(unzoomedOffset.dy, lessThan(0));

      await tap(tester, view(290, 575)); // dismiss the menu, keep editing
      viewer.setZoom(2 * scale); // 2x transform scale over fit-width
      await tester.pump();

      final (zoomedOffset, zoomedHeight) = await pressAndMeasure();
      expect(zoomedOffset.dx, closeTo(unzoomedOffset.dx, 1));
      expect(zoomedOffset.dy, closeTo(unzoomedOffset.dy, 1));
      // and at its natural size, not the zoom's
      expect(zoomedHeight, closeTo(unzoomedHeight, 0.5));
      // wholly on screen, which is the symptom that started this
      final screen = Offset.zero &
          tester.view.physicalSize / tester.view.devicePixelRatio;
      final menu = menuBounds();
      expect(screen.contains(menu.topLeft), isTrue, reason: 'menu $menu');
      expect(screen.contains(menu.bottomRight), isTrue, reason: 'menu $menu');

      debugDefaultTargetPlatformOverride = null;
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await settle(tester);
    });

    testWidgets('resizing a text box previews re-wrapping, not scaled glyphs',
        (tester) async {
      const previewKey = ValueKey('pdf-text-resize-preview');
      final (editing, _) = await pumpEditor(tester);
      editing
        ..preferences.fontSize = 16
        ..addFreeText(0, const PdfRect(100, 600, 300, 650), 'Wrap me please')
        ..tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();

      // grab the bottom-right handle and pull it inward
      final gesture = await tester.startGesture(view(300, 600));
      await gesture.moveTo(view(260, 580));
      await gesture.moveTo(view(220, 560));
      await tester.pump();

      // mid-drag: the wrapped-text preview rides the dragged box, with
      // the glyphs at their committed size - not stretched
      expect(find.byKey(previewKey), findsOneWidget);
      final text = tester.widget<Text>(find.descendant(
          of: find.byKey(previewKey), matching: find.byType(Text)));
      expect(text.data, 'Wrap me please');
      expect(text.style!.fontSize, closeTo(16 * scale, 0.01));

      // the painter lifts the original off the page: it hides the RESTING
      // box (the original footprint) so the dragged preview isn't doubled
      // up with the old rendering. The hide rect spans the resting box.
      final painter = overlayPainter(tester);
      expect(painter.resizeHideRect, isNotNull);
      expect((painter.resizeHideRect as Rect).width, closeTo(200 * scale, 0.5));

      await gesture.up();
      await tester.pump();

      // committed: the box shrank and the appearance kept its font size
      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.rect.left, closeTo(100, 0.5));
      expect(annotation.rect.right, closeTo(220, 0.5));
      expect(annotation.defaultAppearance, contains('16 Tf'));
      // the afterimage keeps the wrapped text painted until the raster
      // lands - the live preview itself is gone with the drag
      expect(find.byKey(previewKey), findsNothing);
      expect(find.text('Wrap me please'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('resizing an embedded-font box previews the re-wrap too',
        (tester) async {
      const previewKey = ValueKey('pdf-text-resize-preview');
      final (editing, _) = await pumpEditor(tester);
      final fontBytes =
          File('../pdf_document/test/fonts/DejaVuSans.ttf').readAsBytesSync();
      expect(editing.setCustomFont(fontBytes), isTrue);
      editing
        ..preferences.fontSize = 16
        ..addFreeText(0, const PdfRect(100, 600, 300, 650), 'Wrap me please')
        ..tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();
      // genuinely the embedded path, not a base-14 fallback
      expect(editing.selectedTextFont, isA<PdfEmbeddedFont>());

      // grab the bottom-right handle and pull it inward
      final gesture = await tester.startGesture(view(300, 600));
      await gesture.moveTo(view(260, 580));
      await gesture.moveTo(view(220, 560));
      await tester.pump();

      // an embedded/bundled box re-wraps live just like a base-14 box - the
      // wrapped-text preview rides the dragged box at the committed size,
      // rather than falling back to stretched glyphs
      expect(find.byKey(previewKey), findsOneWidget);
      final text = tester.widget<Text>(find.descendant(
          of: find.byKey(previewKey), matching: find.byType(Text)));
      expect(text.data, 'Wrap me please');
      expect(text.style!.fontSize, closeTo(16 * scale, 0.01));

      await gesture.up();
      await tester.pump();
      editing.activeFont = null;
      await settle(tester);
    });

    testWidgets('the resize preview lifts the box, transparent over the page',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..preferences.fontSize = 16
        ..preferences.textFillColor = const Color(0xFFFFEB3B) // a yellow filled box
        ..addFreeText(0, const PdfRect(100, 600, 300, 650), 'Filled box')
        ..tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();

      // shrink the box width by dragging the bottom-right handle inward
      final gesture = await tester.startGesture(view(300, 600));
      await gesture.moveTo(view(260, 600));
      await gesture.moveTo(view(220, 600));
      await tester.pump();

      // the preview itself carries only the box's own fill - it is
      // otherwise transparent, so the page content behind shows through
      // (the original is hidden by the painter's lift layer, not a wash)
      final box = tester.widget<Container>(
          find.byKey(const ValueKey('pdf-text-resize-preview')));
      expect(box.color, const Color(0xFFFFEB3B));

      // the lift fallback (until the async clean render lands) is OPAQUE
      // blank paper, never translucent - the original must never flash
      final painter = overlayPainter(tester);
      expect((painter.resizeHideWash as Color).a, 1.0);
      expect(painter.resizeHideWash, const Color(0xFFFFFFFF));

      await gesture.up();
      await tester.pump();
      await settle(tester);
    });

    testWidgets('releasing a resize keeps the lift, so no opaque flash',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..preferences.fontSize = 16
        // a transparent box (no fill): the one that used to flash opaque
        // white over the page on release
        ..preferences.textFillColor = null
        ..addFreeText(0, const PdfRect(100, 600, 300, 650), 'Clear box')
        ..tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();

      final gesture = await tester.startGesture(view(300, 600));
      await gesture.moveTo(view(260, 600));
      await gesture.moveTo(view(220, 600));
      await tester.pump();

      // wait for the async clean lift (the page rendered without the box)
      // to land during the drag
      var painter = overlayPainter(tester);
      for (var i = 0; i < 40 && painter.resizeClean == null; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        painter = overlayPainter(tester);
      }
      expect(painter.resizeClean, isNotNull, reason: 'clean lift never landed');

      await gesture.up();
      await tester.pump();

      // the commit happened, and the lift carried into the afterimage:
      // the painter still hides the old footprint with real page content
      // (resizeClean) instead of washing opaque paper over a transparent
      // box - that wash was the white flash.
      painter = overlayPainter(tester);
      expect(painter.resizeClean, isNotNull);
      expect(painter.resizeHideRect, isNotNull);
      expect(find.text('Clear box'), findsOneWidget); // text still shown
      await settle(tester);
    });

    testWidgets('a shape resize still previews with the stretch ghost',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..addRectangle(0, const PdfRect(100, 600, 300, 700))
        ..tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();

      final gesture = await tester.startGesture(view(300, 600));
      await gesture.moveTo(view(330, 580));
      await gesture.moveTo(view(360, 560));
      await tester.pump();

      expect(
          find.byKey(const ValueKey('pdf-text-resize-preview')), findsNothing);
      await gesture.up();
      await tester.pump();
      await settle(tester);
    });
  });
}
