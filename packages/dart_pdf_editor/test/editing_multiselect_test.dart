import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  group('PdfEditingController multi-selection', () {
    /// A square (slot 0) and a circle (slot 1) near the top of page 0.
    PdfEditingController twoShapes() =>
        PdfEditingController(buildMultiPagePdf(2))
          ..addRectangle(0, const PdfRect(100, 650, 180, 700))
          ..addEllipse(0, const PdfRect(250, 650, 330, 700));

    /// A band over both shapes.
    const both = PdfRect(90, 640, 340, 710);

    test('toggle selection adds and removes; plain click replaces', () {
      final editing = twoShapes();
      expect(editing.selectAnnotationAt(0, 140, 675), isTrue);
      expect(editing.selectedAnnotationSlots, [(0, 0)]);

      expect(editing.selectAnnotationAt(0, 290, 675, toggle: true), isTrue);
      expect(editing.selectedAnnotationSlots, [(0, 0), (0, 1)]);
      // the most recently selected is the primary
      expect(editing.selectedAnnotationSlot, (0, 1));
      expect(editing.isAnnotationSelected(0, 0), isTrue);

      // toggling a member removes just it
      editing.selectAnnotationAt(0, 140, 675, toggle: true);
      expect(editing.selectedAnnotationSlots, [(0, 1)]);

      // a toggle miss leaves the selection alone, a plain miss clears it
      editing.selectAnnotationAt(0, 500, 400, toggle: true);
      expect(editing.selectedAnnotationSlots, [(0, 1)]);
      editing.selectAnnotationAt(0, 500, 400);
      expect(editing.hasAnnotationSelection, isFalse);
    });

    test('the rubber band selects intersecting annotations', () {
      final editing = twoShapes();
      expect(editing.selectAnnotationsIn(0, both), 2);
      expect(editing.selectedAnnotationSlots, [(0, 0), (0, 1)]);

      // a narrower band replaces the selection
      expect(
          editing.selectAnnotationsIn(0, const PdfRect(90, 640, 200, 710)), 1);
      expect(editing.selectedAnnotationSlots, [(0, 0)]);

      // add joins instead
      expect(
          editing.selectAnnotationsIn(0, const PdfRect(240, 640, 340, 710),
              add: true),
          1);
      expect(editing.selectedAnnotationSlots, [(0, 0), (0, 1)]);
    });

    test(
        'select all takes every selectable annotation, skipping links '
        'and form fields', () {
      // page 0 carries 5 links (one hidden) and a Widget — all unselectable
      final editing = PdfEditingController(buildAnnotatedPdf())
        ..addRectangle(0, const PdfRect(100, 100, 200, 150))
        ..addEllipse(0, const PdfRect(250, 100, 350, 150));
      expect(editing.selectAllAnnotationsOn(0), 2);
      for (final (page, slot) in editing.selectedAnnotationSlots) {
        final subtype = editing.document.page(page).annotations[slot].subtype;
        expect(const {'Square', 'Circle'}, contains(subtype));
      }
    });

    test('moveSelected moves the whole selection as one revision', () {
      final editing = twoShapes();
      editing.selectAnnotationsIn(0, both);
      final revisions = editing.bytes.length;

      editing.moveSelected(10, 20);
      final annotations = editing.document.page(0).annotations;
      expect(annotations[0].rect.left, closeTo(110, 0.5));
      expect(annotations[0].rect.top, closeTo(720, 0.5));
      expect(annotations[1].rect.left, closeTo(260, 0.5));
      // the selection survives the move
      expect(editing.selectedAnnotationSlots, [(0, 0), (0, 1)]);

      // one undo restores both
      editing.undo();
      expect(editing.bytes.length, revisions);
      final restored = editing.document.page(0).annotations;
      expect(restored[0].rect.left, closeTo(100, 0.5));
      expect(restored[1].rect.left, closeTo(250, 0.5));
    });

    test('deleteSelected removes the whole selection as one revision', () {
      final editing = twoShapes();
      editing.selectAnnotationsIn(0, both);
      editing.deleteSelected();
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.hasAnnotationSelection, isFalse);

      editing.undo();
      expect(editing.document.page(0).annotations, hasLength(2));
    });

    test('resize, rotate, and text editing demand a single selection', () {
      final editing = twoShapes();
      editing.selectAnnotationAt(0, 140, 675);
      expect(editing.canResizeSelected, isTrue);
      expect(editing.canRotateSelected, isTrue);

      editing.selectAnnotationAt(0, 290, 675, toggle: true);
      expect(editing.canResizeSelected, isFalse);
      expect(editing.canRotateSelected, isFalse);
      expect(editing.canEditSelectedText, isFalse);
      expect(editing.canRestyleSelectedText, isFalse);
    });

    test('deleting one annotation remaps the surviving selected slots', () {
      final editing = twoShapes();
      editing.selectAnnotationsIn(0, both);
      editing.deleteAnnotation(0, 0);
      // the circle slid into slot 0 and stayed selected
      expect(editing.selectedAnnotationSlots, [(0, 0)]);
      expect(editing.selectedAnnotation!.subtype, 'Circle');
    });
  });

  group('multi-selection in the viewer', () {
    // 800px viewport over a 612pt page
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<void> settle(WidgetTester tester) =>
        tester.pumpAndSettle(const Duration(milliseconds: 300));

    Future<(PdfEditingController, PdfViewerController)> pumpEditor(
        WidgetTester tester,
        {int pages = 2}) async {
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
        ),
      ));
      await tester.pump();
      return (editing, viewer);
    }

    /// The square + circle the controller tests use, on screen.
    Future<void> addShapes(
        WidgetTester tester, PdfEditingController editing) async {
      editing
        ..addRectangle(0, const PdfRect(100, 650, 180, 700))
        ..addEllipse(0, const PdfRect(250, 650, 330, 700));
      await tester.pump();
    }

    testWidgets('a mouse drag on empty page area rubber-bands a selection',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      await addShapes(tester, editing);
      editing.tool = PdfEditTool.select;
      await tester.pump();

      final gesture = await tester.startGesture(view(80, 730),
          kind: PointerDeviceKind.mouse);
      await gesture.moveTo(view(200, 690));
      await tester.pump();
      await gesture.moveTo(view(340, 630));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(editing.selectedAnnotationSlots, [(0, 0), (0, 1)]);
      await settle(tester);
    });

    testWidgets('shift-click toggles membership in the selection',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      await addShapes(tester, editing);
      editing.tool = PdfEditTool.select;
      await tester.pump();

      await tester.tapAt(view(140, 675), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(editing.selectedAnnotationSlots, [(0, 0)]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(view(290, 675), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(editing.selectedAnnotationSlots, [(0, 0), (0, 1)]);

      // shift-clicking a member removes it again
      await tester.tapAt(view(140, 675), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(editing.selectedAnnotationSlots, [(0, 1)]);
      await settle(tester);
    });

    testWidgets('dragging one selected annotation moves the whole selection',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      await addShapes(tester, editing);
      editing.tool = PdfEditTool.select;
      editing.selectAnnotationsIn(0, const PdfRect(90, 640, 340, 710));
      await tester.pump();

      final gesture = await tester.startGesture(view(290, 675));
      await gesture.moveBy(const Offset(15, 0)); // past the slop
      await tester.pump();
      await gesture.moveBy(const Offset(25, -20));
      await tester.pump();
      await gesture.up();
      await settle(tester);

      final annotations = editing.document.page(0).annotations;
      final dxSquare = annotations[0].rect.left - 100;
      final dxCircle = annotations[1].rect.left - 250;
      expect(dxSquare, closeTo(40 / scale, 1));
      expect(dxCircle, closeTo(dxSquare, 0.1),
          reason: 'both members move together');
      expect(annotations[0].rect.top - 700, closeTo(20 / scale, 1));
      // the selection survives the move
      expect(editing.selectedAnnotationSlots, [(0, 0), (0, 1)]);
    });

    testWidgets(
        'cmd+A selects every annotation on the current page '
        'while the select tool is armed', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      await addShapes(tester, editing);
      editing.tool = PdfEditTool.select;
      await tester.pump();

      // focus the viewer (an empty-area tap selects nothing)
      await tester.tapAt(view(450, 400));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(editing.selectedAnnotationSlots, [(0, 0), (0, 1)]);
      await settle(tester);
    });

    testWidgets('cmd+A without the select tool selects the page text',
        (tester) async {
      final (_, viewer) = await pumpEditor(tester);
      await tester.tapAt(view(450, 400));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(viewer.selectedText, contains('Page 1'));
    });

    testWidgets('a mouse click selects an annotation with no tool armed',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      await addShapes(tester, editing);
      expect(editing.tool, isNull);

      // a touch tap stays a reader gesture
      await tester.tapAt(view(140, 675));
      await tester.pump(const Duration(milliseconds: 400));
      expect(editing.hasAnnotationSelection, isFalse);

      // a mouse click selects — selection is the mouse's default mode
      await tester.tapAt(view(140, 675), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(editing.selectedAnnotation?.subtype, 'Square');
      expect(editing.tool, isNull, reason: 'no tool got armed');

      // clicking empty page area clears it again
      await tester.tapAt(view(450, 400), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(editing.hasAnnotationSelection, isFalse);
      await settle(tester);
    });

    testWidgets(
        'a touch drag on empty page area still pans the document '
        'in select mode', (tester) async {
      final (editing, viewer) = await pumpEditor(tester, pages: 3);
      editing.tool = PdfEditTool.select;
      await tester.pump();

      final before = viewer.visiblePageRegion(0)!;
      final gesture = await tester.startGesture(view(450, 400));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final after = viewer.visiblePageRegion(0)!;
      expect(after.top, greaterThan(before.top + 0.05),
          reason: 'the drag scrolled the list');
      await settle(tester);
    });

    testWidgets(
        'a shift+drag rubber-bands a selection with no tool armed',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      await addShapes(tester, editing);
      expect(editing.tool, isNull);

      // hold shift: a drag over both shapes rubber-bands them, the same
      // gesture the select tool offers but without arming it
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final gesture = await tester.startGesture(view(80, 730),
          kind: PointerDeviceKind.mouse);
      await gesture.moveTo(view(200, 690));
      await tester.pump();
      await gesture.moveTo(view(340, 630));
      await tester.pump();
      await gesture.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(editing.selectedAnnotationSlots, [(0, 0), (0, 1)]);
      expect(editing.tool, isNull, reason: 'no tool got armed');
      await settle(tester);
    });

    testWidgets('without shift, a mouse drag on empty area does not marquee',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      await addShapes(tester, editing);

      final gesture = await tester.startGesture(view(80, 730),
          kind: PointerDeviceKind.mouse);
      await gesture.moveTo(view(200, 690));
      await tester.pump();
      await gesture.moveTo(view(340, 630));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(editing.hasAnnotationSelection, isFalse,
          reason: 'a plain drag grab-pans, it does not rubber-band');
      await settle(tester);
    });

    testWidgets('the delete key removes the whole selection as one undo step',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      await addShapes(tester, editing);
      editing.tool = PdfEditTool.select;
      await tester.pump();

      // focus the viewer first — the tap would clear a live selection
      await tester.tapAt(view(450, 400));
      await tester.pump(const Duration(milliseconds: 400));
      editing.selectAnnotationsIn(0, const PdfRect(90, 640, 340, 710));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(editing.document.page(0).annotations, isEmpty);

      editing.undo();
      expect(editing.document.page(0).annotations, hasLength(2));
      await settle(tester);
    });
  });
}
