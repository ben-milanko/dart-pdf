import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
        ..author = 'Ben'
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
        ..fontSize = 18
        ..addFreeText(0, const PdfRect(100, 600, 300, 650), 'Original');
      expect(editing.selectAnnotation(0, 0), isTrue);

      editing.setSelectedText('Rewritten');

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.contents, 'Rewritten');
      expect(annotation.defaultAppearance, contains('/Cour 18 Tf'));
    });

    test('text fill and border preferences flow into new free text', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..strokeWidth = 3
        ..textFillColor = const Color(0xFFFFF59D)
        ..textBorderColor = const Color(0xFF1E88E5)
        ..addFreeText(0, const PdfRect(100, 600, 300, 660), 'Boxed');

      final style = editing.document.page(0).annotations.single.freeTextStyle!;
      expect(style.fillColor, 0xFFF59D);
      expect(style.borderColor, 0x1E88E5);
      expect(style.borderWidth, 3);
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
      // the preference tests above seed the global mock store — these
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

    testWidgets('dragging out a text box opens an inline editor that commits',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.freeText;
      await tester.pump();

      await drag(tester, view(100, 700), view(300, 640));

      // the editor is open in place — nothing committed yet, no dialog
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
      // the field's autofocus alone is ignored — typing must still land
      // in the editor without clicking into it first
      final field = tester.widget<TextField>(find.byKey(editorKey));
      expect(field.focusNode!.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await settle(tester);
    });

    testWidgets('Escape cancels the editor without committing', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.freeText;
      await tester.pump();

      await drag(tester, view(100, 700), view(300, 640));
      await tester.enterText(find.byKey(editorKey), 'never mind');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byKey(editorKey), findsNothing);
      expect(editing.isEditingText, isFalse);
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.tool, PdfEditTool.freeText, reason: 'tool stays armed');
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

      await tester.tap(find.text('Serif'));
      await tester.pump();
      expect(editing.fontFamily, PdfStandardFont.times);

      await tester.tap(find.text('Mono'));
      await tester.pump();
      expect(editing.fontFamily, PdfStandardFont.courier);

      // the Bold / Italic toggles pick the matching base-14 variant
      await tester.tap(find.byKey(const ValueKey('pdf-font-bold')));
      await tester.pump();
      expect(editing.fontFamily, PdfStandardFont.courierBold);
      await tester.tap(find.byKey(const ValueKey('pdf-font-italic')));
      await tester.pump();
      expect(editing.fontFamily, PdfStandardFont.courierBoldOblique);
      // switching family keeps the bold+italic style
      await tester.tap(find.text('Serif'));
      await tester.pump();
      expect(editing.fontFamily, PdfStandardFont.timesBoldItalic);
    });

    testWidgets('the style menu sets text fill and border defaults',
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

      // marker yellow is palette slot 1, blue is slot 3
      await tester.tap(find.byKey(const ValueKey('pdf-text-fill-1')));
      await tester.pump();
      expect(editing.textFillColor, PdfEditingToolbar.defaultPalette[1]);

      await tester.tap(find.byKey(const ValueKey('pdf-text-border-3')));
      await tester.pump();
      expect(editing.textBorderColor, PdfEditingToolbar.defaultPalette[3]);

      await tester.tap(find.byKey(const ValueKey('pdf-text-fill-none')));
      await tester.pump();
      expect(editing.textFillColor, isNull);
      expect(editing.textBorderColor, PdfEditingToolbar.defaultPalette[3]);
    });

    testWidgets('the style menu restyles the selected text box',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..strokeWidth = 2.5
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

      final style = editing.document.page(0).annotations.single.freeTextStyle!;
      expect(style.fillColor, 0xFFD100);
      expect(style.borderColor, 0xE53935);
      expect(style.borderWidth, 2.5);
      expect(editing.document.page(0).annotations.single.contents, 'Boxed');
    });

    testWidgets('the inline editor previews the fill of a fresh box',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..textFillColor = const Color(0xFFFFF59D)
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
      // box — the chrome border lives in the inflate(2) gutter outside.
      // (It used to start 2px up-left, so the text jumped on open.)
      expect(tester.getTopLeft(find.byKey(editorKey)),
          offsetMoreOrLessEquals(view(100, 660), epsilon: 0.1));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await settle(tester);
    });

    testWidgets('resizing a text box previews re-wrapping, not scaled glyphs',
        (tester) async {
      const previewKey = ValueKey('pdf-text-resize-preview');
      final (editing, _) = await pumpEditor(tester);
      editing
        ..fontSize = 16
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
      // the glyphs at their committed size — not stretched
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
      // lands — the live preview itself is gone with the drag
      expect(find.byKey(previewKey), findsNothing);
      expect(find.text('Wrap me please'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('the resize preview lifts the box, transparent over the page',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..fontSize = 16
        ..textFillColor = const Color(0xFFFFEB3B) // a yellow filled box
        ..addFreeText(0, const PdfRect(100, 600, 300, 650), 'Filled box')
        ..tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();

      // shrink the box width by dragging the bottom-right handle inward
      final gesture = await tester.startGesture(view(300, 600));
      await gesture.moveTo(view(260, 600));
      await gesture.moveTo(view(220, 600));
      await tester.pump();

      // the preview itself carries only the box's own fill — it is
      // otherwise transparent, so the page content behind shows through
      // (the original is hidden by the painter's lift layer, not a wash)
      final box = tester.widget<Container>(
          find.byKey(const ValueKey('pdf-text-resize-preview')));
      expect(box.color, const Color(0xFFFFEB3B));

      // the lift fallback (until the async clean render lands) is OPAQUE
      // blank paper, never translucent — the original must never flash
      final painter = overlayPainter(tester);
      expect((painter.resizeHideWash as Color).a, 1.0);
      expect(painter.resizeHideWash, const Color(0xFFFFFFFF));

      await gesture.up();
      await tester.pump();
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
