// Copy/cut/paste of annotations (controller clipboard, shortcuts, the
// context menu) and restyling a selected annotation (controller +
// toolbar wiring).

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('controller clipboard', () {
    test('copy + paste duplicates the selection and selects the copies', () {
      final editing = PdfEditingController(buildMultiPagePdf(2))
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..addEllipse(0, const PdfRect(300, 650, 380, 720));
      addTearDown(editing.dispose);
      editing.selectAnnotationsIn(0, const PdfRect(0, 0, 612, 792));
      expect(editing.selectedAnnotationSlots, hasLength(2));
      expect(editing.hasAnnotationClipboard, isFalse);

      expect(editing.copySelectedAnnotations(), 2);
      expect(editing.hasAnnotationClipboard, isTrue);
      final revisions = editing.document;
      expect(identical(editing.document, revisions), isTrue,
          reason: 'copying touches no document bytes');

      expect(editing.pasteAnnotations(0), isTrue);
      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(4));
      // the first same-page paste already steps 12pt so it doesn't stack
      expect(annotations[2].rect, const PdfRect(112, 638, 262, 738));
      expect(annotations[3].rect.left, closeTo(312, 1e-6));
      expect(editing.selectedAnnotationSlots, [(0, 2), (0, 3)]);

      // one revision: a single undo removes both pasted annotations
      editing.undo();
      expect(editing.document.page(0).annotations, hasLength(2));
    });

    test('repeat pastes cascade; another page keeps the position', () {
      final editing = PdfEditingController(buildMultiPagePdf(2))
        ..addRectangle(0, const PdfRect(100, 650, 250, 750));
      addTearDown(editing.dispose);
      editing.selectAnnotation(0, 0);
      editing.copySelectedAnnotations();

      editing.pasteAnnotations(0);
      editing.pasteAnnotations(0);
      final annotations = editing.document.page(0).annotations;
      expect(annotations[1].rect.left, closeTo(112, 1e-6));
      expect(annotations[2].rect.left, closeTo(124, 1e-6));

      // a fresh clipboard fill resets the cascade; a different page
      // pastes at the source position (paste selects the copies, so
      // re-select the original first)
      editing.selectAnnotation(0, 0);
      editing.copySelectedAnnotations();
      editing.pasteAnnotations(1);
      expect(editing.document.page(1).annotations.single.rect,
          const PdfRect(100, 650, 250, 750));
      expect(editing.selectedAnnotationSlots, [(1, 0)]);
    });

    test('paste centers on a point and clamps into the crop box', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 650, 250, 750));
      addTearDown(editing.dispose);
      editing.selectAnnotation(0, 0);
      editing.copySelectedAnnotations();

      editing.pasteAnnotations(0, at: (300, 400));
      expect(editing.document.page(0).annotations[1].rect,
          const PdfRect(225, 350, 375, 450));

      // a corner point clamps the 150×100 group inside the page
      editing.pasteAnnotations(0, at: (5, 5));
      expect(editing.document.page(0).annotations[2].rect,
          const PdfRect(0, 0, 150, 100));
    });

    test('cut removes in one undo step and the clipboard survives undo', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 650, 250, 750));
      addTearDown(editing.dispose);
      editing.selectAnnotation(0, 0);

      expect(editing.cutSelectedAnnotations(), 1);
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.hasAnnotationClipboard, isTrue);

      // undoing the cut restores the original; the clipboard still pastes
      editing.undo();
      expect(editing.document.page(0).annotations, hasLength(1));
      expect(editing.pasteAnnotations(0), isTrue);
      expect(editing.document.page(0).annotations, hasLength(2));
    });

    test('the clipboard outlives the revision it was copied from', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 650, 250, 750));
      addTearDown(editing.dispose);
      editing.selectAnnotation(0, 0);
      editing.copySelectedAnnotations();

      editing.undo(); // the source annotation no longer exists
      expect(editing.document.page(0).annotations, isEmpty);

      expect(editing.pasteAnnotations(0), isTrue);
      final pasted = editing.document.page(0).annotations.single;
      expect(pasted.subtype, 'Square');
      expect(pasted.rect.left, closeTo(112, 1e-6));
    });
  });

  group('controller restyle', () {
    test('restyleSelected recolors in place, keeping slot and selection', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..color = const Color(0xFFE53935)
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..addRectangle(0, const PdfRect(300, 650, 400, 700));
      addTearDown(editing.dispose);
      editing.selectAnnotation(0, 0);
      expect(editing.canRestyleSelected, isTrue);

      expect(editing.restyleSelected(color: const Color(0xFF1E88E5)), isTrue);
      final annotations = editing.document.page(0).annotations;
      expect(annotations[0].color, 0x1E88E5);
      expect(annotations[1].color, 0xE53935, reason: 'unselected untouched');
      expect(editing.selectedAnnotationSlots, [(0, 0)],
          reason: 'in-place restyle keeps the slot');

      editing.undo();
      expect(editing.document.page(0).annotations[0].color, 0xE53935);
    });

    test('a multi-selection restyles in one revision', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..color = const Color(0xFFE53935)
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..addEllipse(0, const PdfRect(300, 650, 380, 720));
      addTearDown(editing.dispose);
      editing.selectAnnotationsIn(0, const PdfRect(0, 0, 612, 792));

      editing.restyleSelected(
          color: const Color(0xFF43A047), strokeWidth: 5, opacity: 0.5);
      for (final annotation in editing.document.page(0).annotations) {
        expect(annotation.color, 0x43A047);
        expect(annotation.borderWidth, 5);
        expect(annotation.appearanceOpacity, closeTo(0.5, 1e-6));
      }
      expect(editing.selectedAnnotationSlots, hasLength(2));

      editing.undo();
      for (final annotation in editing.document.page(0).annotations) {
        expect(annotation.color, 0xE53935);
      }
    });

    test('selectedAnnotationStyle reads the current style', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..color = const Color(0xFFE53935)
        ..strokeWidth = 4
        ..opacity = 0.5
        ..addRectangle(0, const PdfRect(100, 650, 250, 750));
      addTearDown(editing.dispose);
      expect(editing.selectedAnnotationStyle, isNull);

      editing.selectAnnotation(0, 0);
      final style = editing.selectedAnnotationStyle!;
      expect(style.color, const Color(0xFFE53935));
      expect(style.strokeWidth, 4);
      expect(style.opacity, closeTo(0.5, 1e-6));
    });

    test('free text: color restyles the text, fill the background', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addFreeText(0, const PdfRect(100, 560, 300, 620), 'Hello');
      addTearDown(editing.dispose);
      editing.selectAnnotation(0, 0);

      editing.restyleSelected(color: const Color(0xFF1E88E5));
      editing.restyleSelected(fill: (const Color(0xFFFFF59D),));
      final style = editing.document.page(0).annotations.single.freeTextStyle!;
      expect(style.color, 0x1E88E5);
      expect(style.fillColor, 0xFFF59D);
      expect(editing.selectedAnnotationSlots, [(0, 0)]);
      // and the text-edit machinery still recognizes it
      expect(editing.canEditSelectedText, isTrue);
    });
  });

  group('in the viewer', () {
    // 800px viewport over a 612pt page
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<void> settle(WidgetTester tester) =>
        tester.pumpAndSettle(const Duration(milliseconds: 300));

    Future<(PdfEditingController, PdfViewerController)> pumpEditor(
        WidgetTester tester,
        {int pages = 2,
        bool toolbar = false}) async {
      final editing = PdfEditingController(buildMultiPagePdf(pages));
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
          bottomNavigationBar: toolbar
              ? PdfEditingToolbar(controller: editing, viewerController: viewer)
              : null,
        ),
      ));
      await tester.pump();
      return (editing, viewer);
    }

    Future<void> sendCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    Future<void> rightClick(WidgetTester tester, Offset at) async {
      await tester.tapAt(at,
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+C copies the selection and Ctrl+V pastes',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..tool = PdfEditTool.select;
      await tester.pump();
      await tester.tapAt(view(175, 700));
      await settle(tester);
      expect(editing.selectedAnnotation, isNotNull);

      await sendCtrl(tester, LogicalKeyboardKey.keyC);
      expect(editing.hasAnnotationClipboard, isTrue);

      await sendCtrl(tester, LogicalKeyboardKey.keyV);
      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(2));
      expect(annotations[1].rect, const PdfRect(112, 638, 262, 738));
      expect(editing.selectedAnnotationSlots, [(0, 1)]);
      await settle(tester);
    });

    testWidgets('Ctrl+X cuts; Ctrl+V brings it back', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..tool = PdfEditTool.select;
      await tester.pump();
      await tester.tapAt(view(175, 700));
      await settle(tester);

      await sendCtrl(tester, LogicalKeyboardKey.keyX);
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.hasAnnotationClipboard, isTrue);

      await sendCtrl(tester, LogicalKeyboardKey.keyV);
      expect(editing.document.page(0).annotations, hasLength(1));
      await settle(tester);
    });

    testWidgets('the context menu copies, and pastes at the click point',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addRectangle(0, const PdfRect(100, 650, 250, 750));
      await tester.pump();

      await rightClick(tester, view(175, 700));
      // paste is offered but disabled while the clipboard is empty
      final paste =
          tester.widget(find.byKey(const ValueKey('pdf-annot-menu-paste')))
              as PopupMenuItem;
      expect(paste.enabled, isFalse);

      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-copy')));
      await tester.pumpAndSettle();
      expect(editing.hasAnnotationClipboard, isTrue);

      // an empty-area right-click with nothing selected offers paste alone
      editing.clearAnnotationSelection();
      await tester.pump();
      await rightClick(tester, view(450, 350));
      expect(
          find.byKey(const ValueKey('pdf-annot-menu-paste')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-annot-menu-copy')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-annot-menu-front')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-paste')));
      await tester.pumpAndSettle();
      final pasted = editing.document.page(0).annotations[1];
      // centered on the click: the 150×100 box about (450, 350)
      expect(pasted.rect, const PdfRect(375, 300, 525, 400));
      await settle(tester);
    });

    testWidgets('an empty-area right-click without a clipboard is silent',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addRectangle(0, const PdfRect(100, 650, 250, 750));
      await tester.pump();

      await rightClick(tester, view(450, 350));
      expect(find.byKey(const ValueKey('pdf-annot-menu-paste')), findsNothing);
      await settle(tester);
    });

    testWidgets('cutting from the menu removes the annotation', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addRectangle(0, const PdfRect(100, 650, 250, 750));
      await tester.pump();

      await rightClick(tester, view(175, 700));
      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-cut')));
      await tester.pumpAndSettle();
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.hasAnnotationClipboard, isTrue);
      await settle(tester);
    });

    testWidgets('a palette tap recolors the selected annotation',
        (tester) async {
      final (editing, _) = await pumpEditor(tester, toolbar: true);
      editing
        ..color = const Color(0xFFE53935)
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..selectAnnotation(0, 0);
      await tester.pump();

      // the green swatch in the toolbar palette
      final swatch = find.descendant(
        of: find.byType(PdfEditingToolbar),
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == const Color(0xFF43A047) &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle),
      );
      await tester.scrollUntilVisible(swatch, 100,
          scrollable: find
              .descendant(
                  of: find.byType(PdfEditingToolbar),
                  matching: find.byType(Scrollable))
              .first);
      await tester.tap(swatch);
      await tester.pump();

      expect(editing.color, const Color(0xFF43A047));
      expect(editing.document.page(0).annotations.single.color, 0x43A047);
      expect(editing.selectedAnnotationSlots, [(0, 0)]);

      editing.undo();
      expect(editing.document.page(0).annotations.single.color, 0xE53935);
      await settle(tester);
    });

    testWidgets('the style menu shows and restyles the selection stroke',
        (tester) async {
      final (editing, _) = await pumpEditor(tester, toolbar: true);
      editing
        ..strokeWidth = 2
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..selectAnnotation(0, 0);
      await tester.pump();

      final tune = find.descendant(
          of: find.byType(PdfEditingToolbar),
          matching: find.byIcon(Icons.tune));
      await tester.scrollUntilVisible(tune, 100,
          scrollable: find
              .descendant(
                  of: find.byType(PdfEditingToolbar),
                  matching: find.byType(Scrollable))
              .first);
      await tester.tap(tune);
      await tester.pumpAndSettle();

      // the stroke slider shows the selected annotation's width (scope to
      // the popup — the strip also carries an inline opacity slider)
      final menuSlider = find.descendant(
          of: find.byType(MenuAnchor), matching: find.byType(Slider));
      final slider = tester.widget(menuSlider.first) as Slider;
      expect(slider.value, closeTo(2, 1e-6));

      // dragging it restyles on release
      await tester.drag(menuSlider.first, const Offset(150, 0));
      await tester.pumpAndSettle();
      final width = editing.document.page(0).annotations.single.borderWidth!;
      expect(width, greaterThan(2));
      expect(editing.selectedAnnotationSlots, [(0, 0)]);
      await settle(tester);
    });
  });
}
