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
import 'package:dart_pdf_editor/src/editing/editing_color_pick.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 2x2 RGBA PNG fixture used by image-content replacement tests.
final _tinyPng = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0k'
    'AAAAGUlEQVR4nGP4z8DwHwgbWBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');

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

    test('bookmarks create, edit and delete PDF outline items', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      expect(editing.outline.isEmpty, isTrue);

      expect(editing.addBookmark('Start', pageIndex: 0), isTrue);
      expect(editing.outline.items.single.title, 'Start');
      expect(editing.outline.items.single.destination?.pageIndex, 0);
      expect(PdfOutline.rootCount(editing.document), 1);

      expect(
          editing.addBookmark('Child', pageIndex: 1, parentPath: [0]), isTrue);
      expect(editing.outline.items.single.children.single.title, 'Child');
      expect(PdfOutline.rootCount(editing.document), 2);

      expect(editing.editBookmark([0], title: 'Renamed', pageIndex: 2), isTrue);
      expect(editing.outline.items.single.title, 'Renamed');
      expect(editing.outline.items.single.destination?.pageIndex, 2);

      expect(editing.deleteBookmark([0, 0]), isTrue);
      expect(editing.outline.items.single.children, isEmpty);
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
        ..preferences.strokeWidth = 4
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
      // the sample is adopted opaque - annotation alpha is [opacity]'s job
      expect(editing.color, const Color(0xFF00A040));
    });

    test('pickColorFromPage hands the sample back instead of adopting it', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      final before = editing.color;

      final pick = editing.pickColorFromPage();
      expect(editing.isPickingColor, isTrue);
      editing.finishColorPick(const Color(0x8000A040));
      expect(editing.isPickingColor, isFalse);
      expect(editing.color, before,
          reason: 'a dialog asked for the colour; the tool keeps its own');
      expect(pick, completion(const Color(0xFF00A040)));
    });

    test('a cancelled pickColorFromPage resolves null', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      final pick = editing.pickColorFromPage();
      editing.cancelColorPick();
      expect(pick, completion(isNull));
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
        ..preferences.opacity = 0.5
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

    test('replaceSelectedElementImage removes page content and inserts a stamp',
        () {
      final editing = PdfEditingController(PdfImageDocument.fromImageBytes(
        [_tinyPng],
        pageSize: const PdfPageSize(100, 100),
        fit: PdfImageFit.fill,
      ));
      final elements = editing.elementsOn(0).elements;
      expect(elements, hasLength(1));
      expect(elements.single.kind, PdfElementKind.image);
      expect(editing.selectElementAt(0, 50, 50), isTrue);
      expect(editing.canReplaceSelectedElementImage, isTrue);

      expect(editing.replaceSelectedElementImage(_tinyPng), isTrue);
      expect(editing.selectedElement, isNull);
      expect(editing.elementsOn(0).elements, isEmpty,
          reason: 'the old baked-in image draw was removed');
      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(stamp.rect.left, closeTo(0, 0.01));
      expect(stamp.rect.bottom, closeTo(0, 0.01));
      expect(stamp.rect.right, closeTo(100, 0.01));
      expect(stamp.rect.top, closeTo(100, 0.01));

      editing.undo();
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.elementsOn(0).elements.single.kind, PdfElementKind.image);
    });

    testWidgets('exportSelectedElementImage renders the image as PNG',
        (tester) async {
      final editing = PdfEditingController(PdfImageDocument.fromImageBytes(
        [_tinyPng],
        pageSize: const PdfPageSize(100, 100),
        fit: PdfImageFit.fill,
      ));
      addTearDown(editing.dispose);

      expect(editing.selectElementAt(0, 50, 50), isTrue);
      final exported = await tester
          .runAsync(() => editing.exportSelectedElementImage(dpi: 72));

      expect(exported, isNotNull);
      expect(exported!.pageIndex, 0);
      expect(exported.pageRect.left, closeTo(0, 0.01));
      expect(exported.pageRect.right, closeTo(100, 0.01));
      expect(exported.pngBytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });

    test('replaceSelectedElementImageAsync uses the worker-backed path',
        () async {
      final editing = PdfEditingController(PdfImageDocument.fromImageBytes(
        [_tinyPng],
        pageSize: const PdfPageSize(100, 100),
        fit: PdfImageFit.fill,
      ));
      addTearDown(editing.dispose);

      expect(editing.selectElementAt(0, 50, 50), isTrue);
      expect(await editing.replaceSelectedElementImageAsync(_tinyPng), isTrue);
      expect(editing.elementsOn(0).elements, isEmpty);
      expect(editing.document.page(0).annotations.single.subtype, 'Stamp');
    });

    testWidgets('content toolbar exposes save for a selected image',
        (tester) async {
      final editing = PdfEditingController(PdfImageDocument.fromImageBytes(
        [_tinyPng],
        pageSize: const PdfPageSize(100, 100),
        fit: PdfImageFit.fill,
      ));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      editing
        ..tool = PdfEditTool.content
        ..selectElementAt(0, 50, 50);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
            onExportSelectedContentImage: (context, image) async {},
          ),
        ),
      ));
      await tester.pump();

      expect(
          find.byKey(const ValueKey('pdf-save-element-image')), findsOneWidget);
      expect(
          tester
              .widget<IconButton>(
                  find.byKey(const ValueKey('pdf-save-element-image')))
              .onPressed,
          isNotNull);
    });

    test('replaceSelectedElementText rewrites the run in place', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      editing.selectElementAt(0, 80, 725);
      expect(editing.replaceSelectedElementText('Hello'), 1);
      expect(editing.elementsOn(0).elements.single.text, 'Hello');
      editing.undo();
      expect(editing.elementsOn(0).elements.single.text, 'Page 1');
    });

    test('replaceSelectedElementText leaves identical runs elsewhere alone',
        () {
      // the same words drawn twice, as a header and a footer would be
      final editing = PdfEditingController(buildTextLinesPdf(const [
        'Date: 05/08/2026',
        'Revision: B',
        'Date: 05/08/2026',
      ]));
      editing.selectElementAt(0, 60, 674); // the second "Date:" line
      final selected = editing.selectedElement;
      expect(selected?.text, 'Date: 05/08/2026');

      expect(editing.replaceSelectedElementText('Date: 26/05/2026'), 1);
      expect(
        [for (final e in editing.elementsOn(0).elements) e.text],
        const ['Date: 05/08/2026', 'Revision: B', 'Date: 26/05/2026'],
      );
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

    test('documentAnnotationColors collects annotation stroke/fill colours',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      expect(editing.documentAnnotationColors(), isEmpty);

      editing
        ..color = const Color(0xFF1E88E5)
        ..addInkStroke(0, [(100, 100), (150, 130)])
        ..finishInk();
      editing
        ..color = const Color(0xFFE53935)
        ..addInkStroke(1, [(100, 100), (150, 130)])
        ..finishInk();
      // a second blue stroke makes blue the most-frequent colour
      editing
        ..color = const Color(0xFF1E88E5)
        ..addInkStroke(0, [(120, 90), (140, 95)])
        ..finishInk();

      final colors = editing.documentAnnotationColors();
      expect(colors, [const Color(0xFF1E88E5), const Color(0xFFE53935)],
          reason: 'most-frequent first, deduplicated by RGB');
    });

    test('documentAnnotationColors respects the limit', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      for (var i = 0; i < 5; i++) {
        editing
          ..color = Color(0xFF000000 | (i * 0x102030))
          ..addInkStroke(0, [(100.0 + i, 100), (150, 130)])
          ..finishInk();
      }
      expect(editing.documentAnnotationColors(limit: 3), hasLength(3));
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

    testWidgets('a shape dragged past the page edge keeps its off-page bounds',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.rectangle;
      await tester.pump();

      // start on the page and drag out past its left edge: the annotation
      // keeps the bounds that were drawn - the renderer's page clip is what
      // trims it, not the authoring
      await drag(tester, view(60, 700), view(-40, 640));

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'Square');
      expect(annotation.rect.left, lessThan(0));
      expect(annotation.rect.right, closeTo(60, 2));

      // and it survives the save: nothing downstream normalizes /Rect back
      // onto the page
      final reopened = PdfDocument.open(editing.bytes);
      expect(reopened.page(0).annotations.single.rect.left,
          closeTo(annotation.rect.left, 1e-6));
      await settle(tester);
    });

    testWidgets('dragging with the cloud polygon tool adds a cloudy Polygon',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.cloudPolygon;
      await tester.pump();

      await drag(tester, view(100, 700), view(250, 600));

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'Polygon');
      expect(annotation.hasCloudyBorder, isTrue);
      expect(annotation.vertices, hasLength(4));
      expect(annotation.vertices!.first.$1, closeTo(100, 1));
      expect(annotation.vertices!.first.$2, closeTo(600, 1));
      expect(editing.document.page(1).annotations, isEmpty);
      await settle(tester);
    });

    testWidgets('cloud drag preview uses the configured pattern scale',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing
        ..tool = PdfEditTool.cloudPolygon
        ..preferences.lineScale = 2.5;
      await tester.pump();

      final gesture = await tester.startGesture(view(100, 700));
      await gesture.moveTo(view(250, 600));
      await tester.pump();

      final dynamic painter = editingOverlayPainter(tester);
      expect(painter.lineScale, 2.5,
          reason: 'the rubber-band cloud must size its scallops like /BE /I');
      await gesture.up();
      await settle(tester);
    });

    testWidgets('cloud polygon tool taps points and double-taps to finish',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.cloudPolygon;
      await tester.pump();

      await tester.tapAt(view(100, 700));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(view(250, 720));
      await tester.pump(const Duration(milliseconds: 400));
      // one vertex short of a closed polygon: nothing committed yet
      expect(editing.document.page(0).annotations, isEmpty);

      await tester.tapAt(view(180, 620));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(view(180, 620));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'Polygon');
      expect(annotation.hasCloudyBorder, isTrue);
      expect(annotation.vertices, hasLength(3),
          reason: 'three tapped vertices, the double-tap not double-counted');
      expect(annotation.vertices!.first.$1, closeTo(100, 1));
      expect(annotation.vertices!.first.$2, closeTo(700, 1));
      await settle(tester);
    });

    testWidgets('a drag after the first cloud vertex does not add a rectangle',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.cloudPolygon;
      await tester.pump();

      // place one vertex, then drag: the drag must be ignored, not commit a
      // rectangle over the in-progress polygon
      await tester.tapAt(view(120, 700));
      await tester.pump(const Duration(milliseconds: 400));
      await drag(tester, view(200, 650), view(300, 560));
      await tester.pump();

      expect(editing.document.page(0).annotations, isEmpty);
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
      expect(editing.preferences.fingerDrawsInk, isTrue);

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
      expect(editing.preferences.fingerDrawsInk, isFalse);
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

    testWidgets('the eyedropper samples a page other than the first',
        (tester) async {
      final (editing, viewer) = await pumpEditor(tester, pages: 3);
      editing.apply((e) => e.addSquare(
            1,
            const PdfRect(200, 500, 400, 700),
            strokeColor: null,
            fillColor: 0x00A040,
          ));
      await tester.pump();
      // don't await: the returned future completes only as frames pump
      unawaited(viewer.jumpToPage(1));
      await settle(tester);
      expect(viewer.currentPage, 1);

      editing.startColorPick();
      await tester.pump();
      await tester.tapAt(view(300, 600));
      await settle(tester);
      await tester.runAsync(() async {
        for (var i = 0; i < 40 && editing.isPickingColor; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump();

      expect(editing.isPickingColor, isFalse);
      expect(editing.color, const Color(0xFF00A040),
          reason: 'every page samples, not just the one the tool armed over');
      await settle(tester);
    });

    testWidgets('a touch drag scrolls while the eyedropper is armed',
        (tester) async {
      final (editing, viewer) = await pumpEditor(tester, pages: 5);
      editing.startColorPick();
      await tester.pump();

      final touch = await tester.startGesture(view(300, 600),
          kind: PointerDeviceKind.touch);
      for (var i = 0; i < 24; i++) {
        await touch.moveBy(const Offset(0, -100));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await touch.up();
      await settle(tester);

      // the eyedropper has no drag of its own: the document must still
      // scroll under it, or the tool can only ever reach the page it was
      // armed over
      expect(viewer.currentPage, greaterThan(0));
      expect(editing.isPickingColor, isTrue,
          reason: 'the lift that ends a scroll is not a sample');
      await settle(tester);
    });

    testWidgets('the eyedropper chip keeps its size when the page is zoomed',
        (tester) async {
      final (editing, viewer) = await pumpEditor(tester);
      editing.startColorPick();
      await tester.pump();

      final chip = find.byKey(const ValueKey('pdf-eyedropper-chip'));
      final mouse =
          await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 9);
      await mouse.addPointer(location: view(300, 600));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(view(300, 601));
      await tester.pump();
      expect(chip, findsOne);
      final unzoomed = tester.getRect(chip).size;

      viewer.setZoom(4);
      await settle(tester);
      await mouse.moveTo(view(300, 602));
      await tester.pump();
      expect(chip, findsOne);
      final zoomed = tester.getRect(chip).size;

      // the chip lives inside the viewer's zoom transform; it counter-scales
      // so the swatch stays readable instead of becoming a billboard
      expect(zoomed.width, closeTo(unzoomed.width, 1));
      expect(zoomed.height, closeTo(unzoomed.height, 1));
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
      // width out - the aspect lock must grow the height to match
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
      expect(editing.document.page(0).annotations.single.subtype, 'Square');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editing.tool, isNull);
      expect(editing.document.page(0).annotations.single.subtype, 'Square');
      await settle(tester);
    });

    testWidgets('escape clears an armed text-markup tool', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      await tester.tapAt(view(400, 400));
      await tester.pump();
      editing.markupTool = PdfMarkupKind.squiggly;
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(editing.markupTool, isNull);
      expect(editing.tool, isNull);
      await settle(tester);
    });

    testWidgets('escape commits fresh ink instead of discarding it',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);

      // Focus the viewer before arming ink, so the Escape shortcut is active
      // without creating an extra dot through a page tap.
      await tester.tapAt(view(400, 400));
      await tester.pump();

      editing
        ..tool = PdfEditTool.ink
        ..addInkStroke(0, [(100, 650), (160, 690)]);
      await tester.pump();
      expect(editing.hasPendingInk, isTrue);
      expect(editing.document.page(0).annotations, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(editing.tool, isNull);
      expect(editing.hasPendingInk, isFalse);
      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'Ink');
      final painter = editingOverlayPainter(tester);
      expect(painter.extraInk, hasLength(1),
          reason: 'the committed stroke stays painted until the raster lands');
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
      await tester.tap(find.byTooltip('Cloud polygon (⇧D)'));
      await tester.pump();
      expect(editing.tool, PdfEditTool.cloudPolygon);
      // re-tapping the active tool drops back to Select (not a no-tool
      // limbo) so you can immediately select and move things
      await tester.tap(find.byTooltip('Cloud polygon (⇧D)'));
      await tester.pump();
      expect(editing.tool, PdfEditTool.select);

      editing.addRectangle(0, const PdfRect(100, 650, 250, 750));
      await tester.pump();
      await tester.tap(find.byTooltip('Undo (⌘Z)'));
      await tester.pump();
      expect(editing.document.page(0).annotations, isEmpty);
      await settle(tester);
    });

    testWidgets('the Draw group exposes a freehand highlight tool',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
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

      await tester.tap(find.byKey(const ValueKey('pdf-group-draw')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();

      final highlightButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.border_color));
      expect(highlightButton.onPressed, isNotNull);
      await tester.tap(find.byTooltip('Highlight - draw freehand (⇧H)'));
      await tester.pump();
      expect(editing.tool, PdfEditTool.highlight);
      expect(viewer.hasSelection, isFalse);
      expect(editing.color, const Color(0xFFFFD100));
      expect(editing.preferences.strokeWidth, 12);
      expect(editing.preferences.opacity, 0.45);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.draw));
      await tester.pump();
      expect(editing.tool, PdfEditTool.ink);
      expect(editing.color, const Color(0xFFE53935));
      expect(editing.preferences.strokeWidth, 2);
      expect(editing.preferences.opacity, 1);

      await tester.tap(find.byTooltip('Highlight - draw freehand (⇧H)'));
      await tester.pump();
      expect(editing.tool, PdfEditTool.highlight);
      expect(editing.color, const Color(0xFFFFD100));
      expect(editing.preferences.strokeWidth, 12);
      expect(editing.preferences.opacity, 0.45);

      final gesture = await tester.startGesture(view(80, 720),
          kind: PointerDeviceKind.mouse);
      await gesture.moveTo(view(200, 720));
      await gesture.up();
      await tester.pump();
      editing.finishInk();
      await tester.pump();

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'Ink');
      expect(annotation.color, 0xFFD100);
      expect(annotation.borderWidth, 12);
      expect(annotation.appearanceOpacity, closeTo(0.45, 1e-6));
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

    testWidgets('the element toolbar replaces a selected page image',
        (tester) async {
      final editing = PdfEditingController(PdfImageDocument.fromImageBytes(
        [_tinyPng],
        pageSize: const PdfPageSize(100, 100),
        fit: PdfImageFit.fill,
      ));
      final viewer = PdfViewerController();
      var picks = 0;
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      expect(editing.selectElementAt(0, 50, 50), isTrue);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
            imagePicker: (_) async {
              picks++;
              return _tinyPng;
            },
          ),
        ),
      ));
      await tester.pump();

      final replace = find.byKey(const ValueKey('pdf-replace-element-image'));
      expect(replace, findsOneWidget);
      await tester.tap(replace);
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          if (editing.document.page(0).annotations.isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();

      expect(picks, 1);
      expect(editing.elementsOn(0).elements, isEmpty);
      expect(editing.document.page(0).annotations.single.subtype, 'Stamp');
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
      // scope to the popup's sliders - the strip also has an inline opacity
      final menuSliders = find.descendant(
          of: find.byType(MenuAnchor), matching: find.byType(Slider));
      // the shapes popup carries stroke width, corner radius, opacity, and
      // the pattern scale (font is irrelevant to a rectangle, so it's not
      // shown; corner radius is rectangle-only)
      expect(menuSliders, findsNWidgets(4));

      // sliders are laid out stroke width, corner radius, opacity,
      // pattern scale
      await tester.drag(menuSliders.at(0), const Offset(200, 0));
      await tester.pump();
      expect(editing.preferences.strokeWidth, greaterThan(2));

      await tester.drag(menuSliders.at(1), const Offset(200, 0));
      await tester.pump();
      expect(editing.preferences.cornerRadius, greaterThan(0));

      await tester.drag(menuSliders.at(2), const Offset(-200, 0));
      await tester.pump();
      expect(editing.preferences.opacity, lessThan(1));

      // the pattern scale is independent of the pen width
      final beforeStroke = editing.preferences.strokeWidth;
      await tester.drag(menuSliders.at(3), const Offset(200, 0));
      await tester.pump();
      expect(editing.preferences.lineScale, greaterThan(1));
      expect(editing.preferences.strokeWidth, beforeStroke);
      await tester.pumpAndSettle();
    });

    testWidgets('the style menu rounds a selected rectangle in place',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      editing
        ..addRectangle(0, const PdfRect(100, 100, 300, 200))
        ..selectAnnotation(0, 0);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));

      // the selection strip carries the tune button for the selected shape
      await tester.tap(find.byTooltip('Stroke, opacity, font'));
      await tester.pumpAndSettle();

      final radius = find.byKey(const ValueKey('pdf-corner-radius'));
      expect(radius, findsOneWidget);
      await tester.drag(
          find.descendant(of: radius, matching: find.byType(Slider)),
          const Offset(200, 0));
      await tester.pump();

      // dragging restyled the selection, not just the creation default
      expect(editing.document.page(0).annotations.single.cornerRadius,
          greaterThan(0));
      expect(editing.selectedCornerRadius, greaterThan(0));
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

      // middle of the hue slider ≈ 180° - far from red, every channel moves
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

    testWidgets('the palette grid shows and a swatch tap drives onChanged',
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

      // the fixed palette always shows; recents/document grids do not
      // unless supplied
      expect(find.byKey(const ValueKey('pdf-color-grid-palette')), findsOne);
      expect(find.byKey(const ValueKey('pdf-color-grid-recent')), findsNothing);
      expect(
          find.byKey(const ValueKey('pdf-color-grid-document')), findsNothing);

      await tester
          .tap(find.byKey(const ValueKey('pdf-color-swatch-palette-1E88E5')));
      expect(last, const Color(0xFF1E88E5));
    });

    testWidgets('recent and document grids show their swatches and select',
        (tester) async {
      Color? last;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: PdfColorPicker(
              color: const Color(0xFFE53935),
              onChanged: (color) => last = color,
              recentColors: const [Color(0xFF112233)],
              documentColors: const [Color(0xFF445566), Color(0xFF778899)],
            ),
          ),
        ),
      ));

      expect(find.byKey(const ValueKey('pdf-color-grid-recent')), findsOne);
      expect(find.byKey(const ValueKey('pdf-color-grid-document')), findsOne);

      await tester
          .tap(find.byKey(const ValueKey('pdf-color-swatch-recent-112233')));
      expect(last, const Color(0xFF112233));

      await tester
          .tap(find.byKey(const ValueKey('pdf-color-swatch-document-778899')));
      expect(last, const Color(0xFF778899));
    });

    testWidgets('the eyedropper button shows only when the host offers it',
        (tester) async {
      var picks = 0;
      Widget picker({VoidCallback? onPickFromPage}) => MaterialApp(
            home: Scaffold(
              body: Center(
                child: PdfColorPicker(
                  color: const Color(0xFFE53935),
                  onChanged: (_) {},
                  onPickFromPage: onPickFromPage,
                ),
              ),
            ),
          );
      const key = ValueKey('pdf-color-eyedropper');

      await tester.pumpWidget(picker());
      expect(find.byKey(key), findsNothing);

      await tester.pumpWidget(picker(onPickFromPage: () => picks++));
      expect(find.byKey(key), findsOne);
      await tester.tap(find.byKey(key));
      expect(picks, 1);
    });

    testWidgets('pick-from-page closes the dialog and reopens on the sample',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      Color? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await pickEditingColor(context, editing,
                    initial: const Color(0xFFE53935));
              },
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfColorPicker), findsOne);

      await tester.tap(find.byKey(const ValueKey('pdf-color-eyedropper')));
      await tester.pumpAndSettle();
      expect(find.byType(PdfColorPicker), findsNothing,
          reason: 'the dialog covers the page it would sample');
      expect(editing.isPickingColor, isTrue);

      editing.finishColorPick(const Color(0xFF1E88E5));
      await tester.pumpAndSettle();
      expect(find.byType(PdfColorPicker), findsOne,
          reason: 'the picker comes back on the sampled colour');
      expect(find.text('1E88E5'), findsOne);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(result, const Color(0xFF1E88E5));
      expect(editing.preferences.recentColors.first, const Color(0xFF1E88E5));
    });

    testWidgets('cancelling the page sample ends the whole choice',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      var done = false;
      Color? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await pickEditingColor(context, editing,
                    initial: const Color(0xFFE53935));
                done = true;
              },
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-color-eyedropper')));
      await tester.pumpAndSettle();

      editing.cancelColorPick();
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(result, isNull);
      expect(find.byType(PdfColorPicker), findsNothing);
    });

    testWidgets('a grid deduplicates repeated colours by RGB', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: PdfColorPicker(
              color: const Color(0xFFE53935),
              onChanged: (_) {},
              swatches: const [],
              recentColors: const [
                Color(0xFF112233),
                Color(0xFF112233),
                Color(0xFFABCDEF),
              ],
            ),
          ),
        ),
      ));

      // the duplicate collapses to a single swatch under one key
      expect(find.byKey(const ValueKey('pdf-color-swatch-recent-112233')),
          findsOne);
      expect(find.byKey(const ValueKey('pdf-color-swatch-recent-ABCDEF')),
          findsOne);
    });
  });
}
