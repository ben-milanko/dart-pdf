import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  dynamic editingOverlayPainter(WidgetTester tester) {
    for (final paint
        in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
      final painter = paint.painter;
      if (painter.runtimeType.toString() == '_EditingPreviewPainter') {
        return painter;
      }
    }
    fail('No editing overlay painter found');
  }

  group('PdfEditingController', () {
    test('apply commits a revision; undo and redo walk the prefix stack', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      final originalLength = editing.bytes.length;
      expect(editing.isModified, isFalse);
      expect(editing.canUndo, isFalse);

      editing.addRectangle(0, const PdfRect(100, 100, 200, 150));
      expect(editing.document.page(0).annotations, hasLength(1));
      expect(editing.isModified, isTrue);
      final oneEditLength = editing.bytes.length;
      expect(oneEditLength, greaterThan(originalLength));

      editing.addEllipse(0, const PdfRect(250, 100, 350, 150));
      expect(editing.document.page(0).annotations, hasLength(2));
      // incremental updates: each revision extends the previous one
      expect(editing.bytes.length, greaterThan(oneEditLength));
      expect(editing.bytes.sublist(0, originalLength), buildMultiPagePdf(2));

      editing.undo();
      expect(editing.document.page(0).annotations, hasLength(1));
      expect(editing.bytes.length, oneEditLength);
      expect(editing.canRedo, isTrue);

      editing.undo();
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.isModified, isFalse);
      expect(editing.canUndo, isFalse);

      editing.redo();
      editing.redo();
      expect(editing.document.page(0).annotations, hasLength(2));
      expect(editing.canRedo, isFalse);
    });

    test('an edit after undo discards the redoable revisions', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      editing.addRectangle(0, const PdfRect(100, 100, 200, 150));
      editing.undo();
      editing.addEllipse(0, const PdfRect(250, 100, 350, 150));
      expect(editing.canRedo, isFalse);
      expect(editing.document.page(0).annotations.single.subtype, 'Circle');
    });

    test('apply with no staged changes is not a revision', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      expect(editing.apply((_) {}), isFalse);
      expect(editing.isModified, isFalse);
    });

    test('ink strokes buffer until finishInk commits one Ink annotation', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addInkStroke(0, [(100, 100), (150, 130), (200, 100)])
        ..addInkStroke(0, [(120, 90), (140, 95)]);
      expect(editing.hasPendingInk, isTrue);
      expect(editing.strokesOn(0), hasLength(2));
      expect(editing.isModified, isFalse, reason: 'nothing committed yet');

      editing.finishInk();
      expect(editing.hasPendingInk, isFalse);
      expect(editing.strokesOn(0), isEmpty);
      final ink = editing.document.page(0).annotations.single;
      expect(ink.subtype, 'Ink');
    });

    test('ink pressures are buffered and committed with the annotation', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..strokeWidth = 4
        ..addInkStroke(0, [(100, 100), (150, 130), (200, 100)],
            pressures: [0.0, 0.5, 1.0])
        ..addInkStroke(0, [(120, 90), (140, 95)]);
      expect(editing.strokePressuresOn(0), [
        [0.0, 0.5, 1.0],
        null,
      ]);

      editing.finishInk();
      expect(editing.strokePressuresOn(0), isEmpty);
      final ink = editing.document.page(0).annotations.single;
      final content = latin1
          .decode(editing.document.cos.decodeStreamData(ink.normalAppearance!));
      // pressure-mapped segment widths next to the uniform 4pt stroke
      expect(content, contains('2.8 w'));
      expect(content, contains('5.2 w'));
      expect(content, contains('4 w'));
    });

    test('the eyedropper arms, cancels, and adopts a sampled color', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      expect(editing.isPickingColor, isFalse);

      editing.startColorPick();
      expect(editing.isPickingColor, isTrue);
      editing.cancelColorPick();
      expect(editing.isPickingColor, isFalse);

      editing.startColorPick();
      editing.finishColorPick(const Color(0x8000A040));
      expect(editing.isPickingColor, isFalse);
      // the sample is adopted opaque — annotation alpha is [opacity]'s job
      expect(editing.color, const Color(0xFF00A040));
    });

    test('discardInk throws the buffer away without a revision', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addInkStroke(0, [(100, 100), (150, 130)])
        ..discardInk();
      expect(editing.hasPendingInk, isFalse);
      expect(editing.isModified, isFalse);
    });

    test('leaving the ink tool commits the pending drawing', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..tool = PdfEditTool.ink
        ..addInkStroke(0, [(100, 100), (150, 130)])
        ..tool = PdfEditTool.select;
      expect(editing.hasPendingInk, isFalse);
      expect(editing.document.page(0).annotations.single.subtype, 'Ink');
    });

    test('switching from ink to eraser defers the pending drawing commit',
        () async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..tool = PdfEditTool.ink
        ..addInkStroke(0, [(100, 100), (150, 130)])
        ..tool = PdfEditTool.eraser;

      expect(editing.tool, PdfEditTool.eraser);
      expect(editing.hasPendingInk, isTrue,
          reason: 'the eraser should arm before the PDF rewrite runs');
      expect(editing.document.page(0).annotations, isEmpty);

      await Future<void>.delayed(Duration.zero);
      expect(editing.hasPendingInk, isFalse);
      expect(editing.document.page(0).annotations.single.subtype, 'Ink');
    });

    test('addMarkup highlights the given quads', () {
      final editing = PdfEditingController(buildMultiPagePdf(2))
        ..addMarkup(PdfMarkupKind.highlight, {
          0: const [PdfRect(72, 700, 200, 712)],
          1: const [PdfRect(72, 650, 180, 662)],
        });
      expect(editing.document.page(0).annotations.single.subtype, 'Highlight');
      expect(editing.document.page(1).annotations.single.subtype, 'Highlight');
    });

    test('select, move, resize, and delete an annotation', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 100, 200, 150))
        ..tool = PdfEditTool.select;

      expect(editing.selectAnnotationAt(0, 150, 125), isTrue);
      expect(editing.selectedAnnotation!.subtype, 'Square');
      expect(editing.canResizeSelected, isTrue);

      editing.moveSelected(10, 20);
      // the annotation keeps its /Annots slot, so the selection survives
      expect(editing.selectedAnnotation, isNotNull);
      expect(
          editing.selectedAnnotation!.rect, const PdfRect(110, 120, 210, 170));

      editing.resizeSelected(const PdfRect(110, 120, 310, 270));
      expect(
          editing.selectedAnnotation!.rect, const PdfRect(110, 120, 310, 270));

      editing.deleteSelected();
      expect(editing.selectedAnnotation, isNull);
      expect(editing.document.page(0).annotations, isEmpty);

      expect(editing.selectAnnotationAt(0, 150, 125), isFalse);
    });

    test('line-family annotations show resize and rotate controls', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addLine(0, (100, 100), (220, 160), arrow: true)
        ..addPolyLine(0, [(100, 220), (150, 260), (220, 230)])
        ..addPolygon(0, [(260, 220), (320, 280), (380, 220)])
        ..tool = PdfEditTool.select;

      for (var slot = 0; slot < 3; slot++) {
        editing.selectAnnotation(0, slot);
        expect(editing.canResizeSelected, isTrue);
        expect(editing.canRotateSelected, isTrue);
      }

      editing.selectAnnotation(0, 0);
      final before = editing.selectedAnnotation!.rect;
      editing.resizeSelected(const PdfRect(80, 80, 260, 200));
      expect(editing.selectedAnnotation!.rect, const PdfRect(80, 80, 260, 200));
      expect(editing.selectedAnnotation!.line, isNotNull);

      editing.rotateSelected(15);
      expect(editing.selectedAnnotation!.rect, isNot(before));
      expect(editing.canRotateSelected, isTrue);
    });

    test('links and widgets are not selectable', () {
      final editing = PdfEditingController(buildAnnotatedPdf());
      // dead center of the URI link at (72,640)-(200,664) on page 0
      expect(editing.selectAnnotationAt(0, 136, 652), isFalse);
    });

    test('setSelectedText rewrites a note in place', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addNote(0, 100, 700, 'hello')
        ..tool = PdfEditTool.select;
      expect(editing.selectAnnotationAt(0, 110, 690), isTrue);
      expect(editing.canEditSelectedText, isTrue);
      expect(editing.selectedText, 'hello');

      editing.setSelectedText('world');
      final note = editing.document.page(0).annotations.single;
      expect(note.subtype, 'Text');
      expect(note.contents, 'world');
    });

    test('undo and redo clear the annotation selection', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 100, 200, 150))
        ..tool = PdfEditTool.select;
      editing.selectAnnotationAt(0, 150, 125);
      editing.undo();
      expect(editing.selectedAnnotation, isNull);
    });

    test('opacity is baked into new annotation appearances', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..opacity = 0.5
        ..addRectangle(0, const PdfRect(100, 100, 200, 150));
      final written = String.fromCharCodes(editing.bytes);
      expect(written, contains('/ExtGState'));
      expect(written, contains('/CA 0.5'));

      // full opacity adds no alpha state
      final opaque = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 100, 200, 150));
      expect(String.fromCharCodes(opaque.bytes), isNot(contains('/ExtGState')));
    });

    test('selectAnnotation and deleteAnnotation address /Annots slots', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 100, 200, 150))
        ..addEllipse(0, const PdfRect(250, 100, 350, 150));

      expect(editing.selectAnnotation(0, 1), isTrue);
      expect(editing.tool, PdfEditTool.select,
          reason: 'selecting from a list arms the select tool');
      expect(editing.selectedAnnotation!.subtype, 'Circle');
      expect(editing.selectedAnnotationSlot, (0, 1));
      expect(editing.selectAnnotation(0, 5), isFalse);

      // deleting slot 0 shifts the circle into it; the selection is
      // remapped to follow the annotation, not the stale slot number
      editing.deleteAnnotation(0, 0);
      expect(editing.document.page(0).annotations.single.subtype, 'Circle');
      expect(editing.selectedAnnotationSlot, (0, 0));
      expect(editing.selectedAnnotation!.subtype, 'Circle');
    });

    test('selectAnnotation refuses links and widgets', () {
      final editing = PdfEditingController(buildAnnotatedPdf());
      expect(editing.selectAnnotation(0, 0), isFalse); // a Link
      expect(editing.selectAnnotation(0, 3), isFalse); // a Widget
    });

    test('selectElementAt finds the text run; delete removes it', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..tool = PdfEditTool.content;
      // "Page 1" is shown at (72, 720) in 24pt
      expect(editing.selectElementAt(0, 80, 725), isTrue);
      final element = editing.selectedElement!;
      expect(element.kind, PdfElementKind.text);
      expect(element.text, 'Page 1');
      expect(editing.canEditSelectedElementText, isTrue);

      expect(editing.selectElementAt(0, 400, 400), isFalse,
          reason: 'empty page area clears the element selection');
      expect(editing.selectedElement, isNull);

      editing.selectElementAt(0, 80, 725);
      editing.deleteSelectedElement();
      expect(editing.selectedElement, isNull);
      expect(editing.elementsOn(0).elements, isEmpty);

      editing.undo();
      expect(editing.elementsOn(0).elements.single.text, 'Page 1');
    });

    test('replaceSelectedElementText rewrites the run in place', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      editing.selectElementAt(0, 80, 725);
      expect(editing.replaceSelectedElementText('Hello'), 1);
      expect(editing.elementsOn(0).elements.single.text, 'Hello');
      editing.undo();
      expect(editing.elementsOn(0).elements.single.text, 'Page 1');
    });

    test('arming a non-content tool clears the element selection', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..tool = PdfEditTool.content;
      editing.selectElementAt(0, 80, 725);
      expect(editing.selectedElement, isNotNull);
      editing.tool = PdfEditTool.select;
      expect(editing.selectedElement, isNull);
    });

    test('movePage and removePage commit undoable revisions', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      String shown(int page) => editing
          .elementsOn(page)
          .elements
          .firstWhere((e) => e.kind == PdfElementKind.text)
          .text!;

      editing.movePage(0, 2);
      expect(shown(0), 'Page 2');
      expect(shown(1), 'Page 3');
      expect(shown(2), 'Page 1');

      editing.undo();
      expect(shown(0), 'Page 1');
      editing.redo();

      editing.removePage(0);
      expect(editing.document.pageCount, 2);
      expect(shown(0), 'Page 3');
      expect(shown(1), 'Page 1');
    });

    test('page edits clear the selection; the last page is kept', () {
      final editing = PdfEditingController(buildMultiPagePdf(2))
        ..addRectangle(1, const PdfRect(100, 100, 200, 150))
        ..tool = PdfEditTool.select;
      editing.selectAnnotationAt(1, 150, 125);
      expect(editing.selectedAnnotation, isNotNull);

      editing.movePage(1, 0);
      expect(editing.selectedAnnotation, isNull,
          reason: 'page indices shifted under the slot');

      editing.removePage(1);
      expect(editing.document.pageCount, 1);
      editing.removePage(0);
      expect(editing.document.pageCount, 1,
          reason: 'the last page cannot be removed');
      expect(editing.document.page(0).annotations.single.subtype, 'Square');
    });
  });

  group('editing in the viewer', () {
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

    Future<(PdfEditingController, PdfViewerController)> pumpEditor(
        WidgetTester tester,
        {int pages = 3}) async {
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

    testWidgets('dragging with the rectangle tool adds a Square',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.rectangle;
      await tester.pump();

      await drag(tester, view(100, 700), view(250, 600));

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'Square');
      expect(annotation.rect.width, greaterThan(100));
      expect(annotation.rect.height, greaterThan(50));
      expect(editing.document.page(1).annotations, isEmpty);
      await settle(tester);
    });

    testWidgets('dragging with the arrow tool adds a dashed Line',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..tool = PdfEditTool.arrow
        ..dashedStroke = true;
      await tester.pump();

      await drag(tester, view(100, 700), view(250, 620));

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'Line');
      expect(annotation.line, isNotNull);
      expect(annotation.borderDash, isNotNull);
      final le =
          editing.document.cos.resolve(annotation.dict['LE']) as CosArray;
      expect((editing.document.cos.resolve(le[1]) as CosName).value,
          'ClosedArrow');
      editing
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0);
      expect(editing.canResizeSelected, isTrue);
      expect(editing.canRotateSelected, isTrue);
      await settle(tester);
    });

    testWidgets('line-family selection drags vertex handles', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..tool = PdfEditTool.arrow
        ..dashedStroke = true;
      await tester.pump();
      await drag(tester, view(100, 700), view(250, 620));

      editing
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0);
      await tester.pump();

      final gesture = await tester.startGesture(view(250, 620),
          kind: PointerDeviceKind.mouse);
      await gesture.moveTo(view(300, 610));
      await tester.pump();

      final live = editingOverlayPainter(tester).livePath;
      expect(live, isNotNull);
      expect(live.tool, PdfEditTool.arrow);
      expect(live.dashed, isTrue);
      expect((live.points as List).cast<Offset>(),
          [view(100, 700), view(300, 610)]);
      await gesture.up();
      await tester.pump();

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'Line');
      expect(annotation.line!.$1.$1, closeTo(100, 1));
      expect(annotation.line!.$1.$2, closeTo(700, 1));
      expect(annotation.line!.$2.$1, closeTo(300, 1));
      expect(annotation.line!.$2.$2, closeTo(610, 1));
      await settle(tester);
    });

    testWidgets('polyline tool taps points and double-taps to finish',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.polyline;
      await tester.pump();

      await tester.tapAt(view(100, 700));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(view(150, 660));
      await tester.pump(const Duration(milliseconds: 400));
      expect(editing.document.page(0).annotations, isEmpty);

      await tester.tapAt(view(220, 680));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(view(220, 680));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'PolyLine');
      expect(annotation.vertices, hasLength(3));
      expect(annotation.vertices!.first.$1, closeTo(100, 1));
    });

    testWidgets('polyline point preview anchors on pointer down',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.polyline;
      await tester.pump();

      final down = view(100, 700);
      final moved = view(180, 680);
      final gesture =
          await tester.startGesture(down, kind: PointerDeviceKind.mouse);
      await tester.pump();

      var path =
          (editingOverlayPainter(tester).dragPath as List).cast<Offset>();
      expect(path, [down]);

      await gesture.moveTo(moved);
      await tester.pump();
      path = (editingOverlayPainter(tester).dragPath as List).cast<Offset>();
      expect(path, [down],
          reason: 'the just-clicked vertex must not chase pointer movement');

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(editing.document.page(0).annotations, isEmpty);
    });

    testWidgets('the ink tool buffers strokes drawn on the page',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.ink;
      await tester.pump();

      final gesture = await tester.startGesture(view(100, 700));
      await gesture.moveTo(view(150, 680));
      await gesture.moveTo(view(200, 700));
      await gesture.up();
      await tester.pump();

      expect(editing.strokesOn(0), hasLength(1));
      expect(editing.isModified, isFalse);
      editing.finishInk();
      expect(editing.document.page(0).annotations.single.subtype, 'Ink');
      await settle(tester);
    });

    testWidgets('a stylus draws with pressure and parks finger drawing',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.ink;
      await tester.pump();
      expect(editing.fingerDrawsInk, isTrue);

      // TestGesture can't carry pressure, so dispatch the Apple Pencil
      // contact as raw events: pressure rising over the stroke
      const pointer = 71;
      final binding = tester.binding;
      final p0 = view(100, 700);
      final p1 = view(150, 690);
      final p2 = view(200, 700);
      binding.handlePointerEvent(PointerDownEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: p0,
        pressure: 0.2,
        pressureMin: 0,
        pressureMax: 1,
      ));
      await tester.pump();
      // the first stylus contact turns palm rejection on
      expect(editing.fingerDrawsInk, isFalse);
      binding.handlePointerEvent(PointerMoveEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: p1,
        delta: p1 - p0,
        pressure: 0.6,
        pressureMin: 0,
        pressureMax: 1,
      ));
      await tester.pump();
      binding.handlePointerEvent(PointerMoveEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: p2,
        delta: p2 - p1,
        pressure: 1.0,
        pressureMin: 0,
        pressureMax: 1,
      ));
      await tester.pump();
      binding.handlePointerEvent(PointerUpEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: p2,
      ));
      await tester.pump();

      expect(editing.strokesOn(0), hasLength(1));
      final pressures = editing.strokePressuresOn(0).single;
      expect(pressures, isNotNull, reason: 'stylus strokes carry pressure');
      expect(pressures, hasLength(editing.strokesOn(0).single.length));
      expect(pressures!.last, 1.0);
      expect(pressures.first, lessThan(pressures.last));

      // palm rejection: a finger drag now scrolls instead of drawing
      await drag(tester, view(300, 700), view(300, 650));
      expect(editing.strokesOn(0), hasLength(1));

      editing.finishInk();
      expect(editing.document.page(0).annotations.single.subtype, 'Ink');
      await settle(tester);
    });

    testWidgets('the eyedropper picks up the rendered page color',
        (tester) async {
      final (editing, _) = await pumpEditor(tester, pages: 1);
      editing.apply((e) => e.addSquare(
            0,
            const PdfRect(200, 500, 400, 700),
            strokeColor: null,
            fillColor: 0x00A040,
          ));
      await tester.pump();

      editing.startColorPick();
      await tester.pump();

      // hovering shows a live preview chip with the color under the
      // pointer; the page raster builds on the real event loop, so poll
      // with hover jitters until the sample lands
      final mouse =
          await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 9);
      await mouse.addPointer(location: view(300, 600));
      addTearDown(mouse.removePointer);
      await tester.pump();
      var shown = false;
      for (var i = 0; i < 40 && !shown; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await mouse.moveTo(view(300, i.isEven ? 600 : 601));
        await tester.pump();
        shown = find.text('#00A040').evaluate().isNotEmpty;
      }
      expect(shown, isTrue, reason: 'hover previews the sampled color');
      expect(editing.isPickingColor, isTrue, reason: 'preview does not pick');

      // releasing a tap picks the color
      await tester.tapAt(view(300, 600));
      await settle(tester);
      await tester.runAsync(() async {
        for (var i = 0; i < 40 && editing.isPickingColor; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump();

      expect(editing.isPickingColor, isFalse);
      expect(editing.color, const Color(0xFF00A040));
      expect(find.text('#00A040'), findsNothing,
          reason: 'the chip leaves with the eyedropper');
      await settle(tester);
    });

    testWidgets('tap selects, delete key removes', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..tool = PdfEditTool.select;
      await tester.pump();

      await tester.tapAt(view(175, 700));
      // the viewer's touch double-tap recognizer holds taps for 300ms
      await settle(tester);
      expect(editing.selectedAnnotation?.subtype, 'Square');

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(editing.document.page(0).annotations, isEmpty);
      await settle(tester);
    });

    testWidgets('dragging a corner handle resizes the selection',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..tool = PdfEditTool.select;
      await tester.pump();
      await tester.tapAt(view(175, 700));
      await settle(tester);
      expect(editing.selectedAnnotation, isNotNull);

      // bottom-right handle in view space = page (right, bottom)
      await drag(tester, view(250, 650), view(290, 620));

      final rect = editing.selectedAnnotation!.rect;
      expect(rect.right, greaterThan(270));
      expect(rect.bottom, lessThan(640));
      expect(rect.left, closeTo(100, 1));
      expect(rect.top, closeTo(750, 1));
      await settle(tester);
    });

    testWidgets('Shift-dragging a corner handle keeps the aspect ratio',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..addRectangle(0, const PdfRect(100, 650, 250, 750)) // 150×100 (3:2)
        ..tool = PdfEditTool.select;
      await tester.pump();
      await tester.tapAt(view(175, 700));
      await settle(tester);
      expect(editing.selectedAnnotation, isNotNull);

      // hold Shift across a bottom-right corner drag that only pushes the
      // width out — the aspect lock must grow the height to match
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      const from = Offset(250, 650), to = Offset(330, 650);
      final gesture = await tester.startGesture(view(from.dx, from.dy));
      await gesture.moveTo(view((from.dx + to.dx) / 2, from.dy));
      await gesture.moveTo(view(to.dx, to.dy));
      await gesture.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      final rect = editing.selectedAnnotation!.rect;
      expect(rect.width, greaterThan(150),
          reason: 'the corner drag widened the box');
      expect(rect.width / rect.height, closeTo(1.5, 0.05),
          reason: 'Shift locked the 3:2 aspect, so the height grew too');
      await settle(tester);
    });

    testWidgets('ctrl+Z undoes, ctrl+shift+Z redoes', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addRectangle(0, const PdfRect(100, 650, 250, 750));
      await tester.pump();

      // focus the viewer the way a user would: click it
      await tester.tapAt(view(400, 400));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(editing.document.page(0).annotations, isEmpty);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(editing.document.page(0).annotations, hasLength(1));
      await settle(tester);
    });

    testWidgets('an edit keeps the scroll position', (tester) async {
      final (editing, viewer) = await pumpEditor(tester, pages: 5);
      // don't await: the returned future completes only as frames pump
      unawaited(viewer.jumpToPage(2));
      await settle(tester);
      expect(viewer.currentPage, 2);

      editing.addRectangle(2, const PdfRect(100, 650, 250, 750));
      await settle(tester);
      expect(viewer.currentPage, 2,
          reason: 'a same-geometry revision swap must not reset the scroll');
    });

    testWidgets('escape backs out: selection, then tool', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..tool = PdfEditTool.select;
      await tester.pump();
      await tester.tapAt(view(175, 700));
      await settle(tester);
      expect(editing.selectedAnnotation, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editing.selectedAnnotation, isNull);
      expect(editing.tool, PdfEditTool.select);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editing.tool, isNull);
      await settle(tester);
    });

    testWidgets('the toolbar arms tools and undoes', (tester) async {
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
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      await tester.pump();

      // opening a group raises its strip and arms its default tool
      await tester.tap(find.byKey(const ValueKey('pdf-group-shapes')));
      await tester.pump();
      expect(editing.tool, PdfEditTool.rectangle);
      // the strip exposes the group's other tools
      await tester.tap(find.byTooltip('Ellipse (O)'));
      await tester.pump();
      expect(editing.tool, PdfEditTool.ellipse);
      // re-tapping the active tool drops back to Select (not a no-tool
      // limbo) so you can immediately select and move things
      await tester.tap(find.byTooltip('Ellipse (O)'));
      await tester.pump();
      expect(editing.tool, PdfEditTool.select);

      editing.addRectangle(0, const PdfRect(100, 650, 250, 750));
      await tester.pump();
      await tester.tap(find.byTooltip('Undo (⌘Z)'));
      await tester.pump();
      expect(editing.document.page(0).annotations, isEmpty);
      await settle(tester);
    });

    testWidgets('the content tool selects a text run; delete removes it',
        (tester) async {
      final (editing, _) = await pumpEditor(tester, pages: 1);
      editing.tool = PdfEditTool.content;
      await tester.pump();

      // "Page 1" sits at (72, 720) in 24pt
      await tester.tapAt(view(80, 725));
      await settle(tester);
      expect(editing.selectedElement?.text, 'Page 1');

      // escape clears the element selection but keeps the tool
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editing.selectedElement, isNull);
      expect(editing.tool, PdfEditTool.content);

      await tester.tapAt(view(80, 725));
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await settle(tester);
      expect(editing.elementsOn(0).elements, isEmpty);
    });

    testWidgets('the sidebar lists, selects, and deletes annotations',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(2))
        ..addNote(0, 100, 700, 'first note')
        ..addRectangle(1, const PdfRect(100, 100, 200, 150));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            Expanded(
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
            PdfAnnotationSidebar(
              controller: editing,
              viewerController: viewer,
            ),
          ]),
        ),
      ));
      await tester.pump();

      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('first note'), findsOneWidget);
      expect(find.text('Square'), findsOneWidget);

      await tester.tap(find.text('Note'));
      await settle(tester);
      expect(editing.tool, PdfEditTool.select);
      expect(editing.selectedAnnotation?.subtype, 'Text');

      // the first Delete button belongs to the page-1 note tile
      await tester.tap(find.byTooltip('Delete').first);
      await settle(tester);
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.document.page(1).annotations, hasLength(1));
      expect(find.text('first note'), findsNothing);
    });

    testWidgets('the style menu drives stroke width and opacity',
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

      // open the Shapes group; its strip carries the tune button
      await tester.tap(find.byKey(const ValueKey('pdf-group-shapes')));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byTooltip('Stroke, opacity, font'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byTooltip('Stroke, opacity, font'));
      await tester.pumpAndSettle();
      // scope to the popup's sliders — the strip also has an inline opacity
      final menuSliders = find.descendant(
          of: find.byType(MenuAnchor), matching: find.byType(Slider));
      // the shapes popup carries stroke width + opacity (font is irrelevant
      // to a rectangle, so it's no longer shown)
      expect(menuSliders, findsNWidgets(2));

      // sliders are laid out stroke width, opacity
      await tester.drag(menuSliders.at(0), const Offset(200, 0));
      await tester.pump();
      expect(editing.strokeWidth, greaterThan(2));

      await tester.drag(menuSliders.at(1), const Offset(-200, 0));
      await tester.pump();
      expect(editing.opacity, lessThan(1));
      await tester.pumpAndSettle();
    });

    testWidgets('the thumbnail sidebar jumps, reorders, and deletes pages',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(
              controller: editing,
              viewerController: viewer,
              width: 130,
            ),
            Expanded(
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
          ]),
        ),
      ));
      await tester.pump();

      String shown(int page) => editing
          .elementsOn(page)
          .elements
          .firstWhere((e) => e.kind == PdfElementKind.text)
          .text!;

      // a footer label per page
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 3'), findsOneWidget);

      // the viewport indicator: page 1 is partially visible (fit-width
      // pages are taller than the viewport), page 3 is off-screen
      final region = viewer.visiblePageRegion(0)!;
      expect(region.top, closeTo(0, 0.01));
      expect(region.bottom, lessThan(1));
      expect(viewer.visiblePageRegion(2), isNull);

      // tapping a thumbnail jumps the viewer
      await tester.tap(find.text('Page 3'));
      await settle(tester);
      expect(viewer.currentPage, 2);
      expect(viewer.visiblePageRegion(0), isNull);

      // long-press a tile, then drag it one tile down to reorder
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('Page 1')));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 90));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 90));
      await tester.pump();
      await gesture.up();
      await settle(tester);
      expect(shown(0), 'Page 2');
      expect(shown(1), 'Page 1');
      expect(shown(2), 'Page 3');

      // the first tile's footer button deletes that page
      await tester
          .tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
      await settle(tester);
      expect(editing.document.pageCount, 2);
      expect(shown(0), 'Page 1');
      expect(shown(1), 'Page 3');

      // a mouse drags tiles without the long press
      final mouse = await tester.startGesture(
          tester.getCenter(find.text('Page 1')),
          kind: PointerDeviceKind.mouse);
      await mouse.moveBy(const Offset(0, 90));
      await tester.pump();
      await mouse.moveBy(const Offset(0, 90));
      await tester.pump();
      await mouse.up();
      await settle(tester);
      expect(shown(0), 'Page 3');
      expect(shown(1), 'Page 1');
    });
  });

  group('PdfColorPicker', () {
    testWidgets('hex entry, the SV area, and the hue slider drive onChanged',
        (tester) async {
      Color? last;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: PdfColorPicker(
              color: const Color(0xFFE53935),
              onChanged: (color) => last = color,
            ),
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField), '00A040');
      expect(last, const Color(0xFF00A040));

      // layout: 260×160 SV area, 12 gap, 20 hue slider
      final origin = tester.getTopLeft(find.byType(PdfColorPicker));

      // top-right of the SV area: full saturation and brightness
      await tester.tapAt(origin + const Offset(258, 2));
      var hsv = HSVColor.fromColor(last!);
      expect(hsv.saturation, greaterThan(0.95));
      expect(hsv.value, greaterThan(0.95));

      // middle of the hue slider ≈ 180° (the hex field follows along)
      await tester.tapAt(origin + const Offset(130, 160 + 12 + 10));
      hsv = HSVColor.fromColor(last!);
      expect(hsv.hue, closeTo(180, 10));
      final hex = tester.widget<TextField>(find.byType(TextField)).controller!;
      expect('#${hex.text}',
          '#${(last!.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}');
    });

    Future<({List<Color> changed, List<PdfColorFormat> formats})> pumpPicker(
      WidgetTester tester, {
      Color color = const Color(0xFFE53935),
    }) async {
      final changed = <Color>[];
      final formats = <PdfColorFormat>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: PdfColorPicker(
              color: color,
              onChanged: changed.add,
              onFormatChanged: formats.add,
            ),
          ),
        ),
      ));
      return (changed: changed, formats: formats);
    }

    Future<void> switchFormat(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(const ValueKey('pdf-color-format')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    String channelText(WidgetTester tester, int i) => tester
        .widget<TextField>(find.byKey(ValueKey('pdf-color-channel-$i')))
        .controller!
        .text;

    Future<void> enterChannel(WidgetTester tester, int i, String text) =>
        tester.enterText(find.byKey(ValueKey('pdf-color-channel-$i')), text);

    testWidgets('RGB mode shows the channels and drives onChanged',
        (tester) async {
      final calls = await pumpPicker(tester);
      await switchFormat(tester, 'RGB');
      expect(calls.formats, [PdfColorFormat.rgb]);
      expect(channelText(tester, 0), '229');
      expect(channelText(tester, 1), '57');
      expect(channelText(tester, 2), '53');

      await enterChannel(tester, 0, '0');
      await enterChannel(tester, 1, '160');
      await enterChannel(tester, 2, '64');
      expect(calls.changed.last, const Color(0xFF00A040));
    });

    testWidgets('HSL mode round-trips', (tester) async {
      final calls = await pumpPicker(tester, color: const Color(0xFF00FF00));
      await switchFormat(tester, 'HSL');
      expect(channelText(tester, 0), '120');
      expect(channelText(tester, 1), '100');
      expect(channelText(tester, 2), '50');

      await enterChannel(tester, 0, '240');
      expect(calls.changed.last, const Color(0xFF0000FF));
    });

    testWidgets('CMYK mode round-trips through the naive device conversion',
        (tester) async {
      final calls = await pumpPicker(tester, color: const Color(0xFFFF0000));
      await switchFormat(tester, 'CMYK');
      expect(channelText(tester, 0), '0');
      expect(channelText(tester, 1), '100');
      expect(channelText(tester, 2), '100');
      expect(channelText(tester, 3), '0');

      await enterChannel(tester, 1, '0');
      await enterChannel(tester, 2, '0');
      expect(calls.changed.last, const Color(0xFFFFFFFF));
      await enterChannel(tester, 0, '100');
      expect(calls.changed.last, const Color(0xFF00FFFF));
    });

    testWidgets('picking on the sliders rewrites the visible channel fields',
        (tester) async {
      await pumpPicker(tester);
      await switchFormat(tester, 'RGB');
      final before = channelText(tester, 0);

      // middle of the hue slider ≈ 180° — far from red, every channel moves
      final origin = tester.getTopLeft(find.byType(PdfColorPicker));
      await tester.tapAt(origin + const Offset(130, 160 + 12 + 10));
      await tester.pump();
      expect(channelText(tester, 0), isNot(before));
    });

    testWidgets('an emptied field leaves the color alone until it parses',
        (tester) async {
      final calls = await pumpPicker(tester);
      await switchFormat(tester, 'RGB');
      await enterChannel(tester, 0, '');
      expect(calls.changed, isEmpty);
      await enterChannel(tester, 0, '12');
      expect(calls.changed.last, const Color(0xFF0C3935));
    });
  });
}
