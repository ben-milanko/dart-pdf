// The PSPDFKit-style circle eraser: live slice preview (faded original
// + surviving strokes), the ring cursor, the afterimage held until the
// raster lands, the eraser-size slider, and the persisted radius.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // 800px viewport over a 612pt page (fit-width)
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  Future<(PdfEditingController, PdfViewerController)> pumpViewer(
      WidgetTester tester) async {
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
      ),
    ));
    await tester.pump();
    return (editing, viewer);
  }

  group('slicing commits', () {
    testWidgets('an eraser swipe across one stroke leaves two', (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing
        ..addInkStroke(0, [(150, 500), (250, 500)])
        ..finishInk();
      editing.tool = PdfEditTool.eraser;
      await tester.pump();

      final g = await tester.startGesture(view(200, 530),
          kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 6; i++) {
        await g.moveBy(Offset(0, 10 * scale));
        await tester.pump();
      }
      await g.up();
      await tester.pump();

      final ink = editing.document.page(0).annotations.single;
      expect(ink.inkList, hasLength(2));
      expect(ink.inkList![0].first.$1, closeTo(150, 0.5));
      expect(ink.inkList![1].last.$1, closeTo(250, 0.5));
      // one apply: a single undo restores the unbroken stroke
      editing.undo();
      expect(editing.document.page(0).annotations.single.inkList, hasLength(1));
    });

    testWidgets('covering a whole annotation removes it', (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing
        ..addInkStroke(0, [(195, 500), (205, 500)])
        ..finishInk();
      editing.tool = PdfEditTool.eraser;
      editing.eraserRadius = 30;
      await tester.pump();

      await tester.tapAt(view(200, 500), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(editing.document.page(0).annotations, isEmpty);
    });

    testWidgets(
        'erasing one stroke of a two-stroke annotation keeps the '
        'other untouched', (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing
        ..addInkStroke(0, [(150, 500), (250, 500)])
        ..addInkStroke(0, [(150, 400), (250, 400)])
        ..finishInk();
      editing.tool = PdfEditTool.eraser;
      editing.eraserRadius = 30;
      await tester.pump();

      // sweep along the whole upper stroke
      final g = await tester.startGesture(view(140, 500),
          kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 12; i++) {
        await g.moveBy(Offset(10 * scale, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pump();

      final ink = editing.document.page(0).annotations.single;
      expect(ink.inkList, hasLength(1));
      expect(ink.inkList!.single.first.$2, closeTo(400, 0.5));
      expect(ink.inkList!.single.last.$2, closeTo(400, 0.5));
    });
  });

  group('live preview', () {
    testWidgets('mid-swipe the original fades and the remainder paints',
        (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing
        ..addInkStroke(0, [(150, 500), (250, 500)])
        ..finishInk();
      editing.tool = PdfEditTool.eraser;
      await tester.pump();

      final g = await tester.startGesture(view(200, 520),
          kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 4; i++) {
        await g.moveBy(Offset(0, 10 * scale));
        await tester.pump();
      }
      final painter = overlayPainter(tester);
      // the touched annotation washes out along its own strokes (not the
      // bounding box, so surrounding page content isn't dimmed)...
      expect((painter.fadeInk as List), hasLength(1));
      expect((painter.fadeRects as List), isEmpty);
      // ...and its sliced remainder (two pieces) paints over the wash
      final extraInk = painter.extraInk as List;
      expect(extraInk, hasLength(1));
      expect((extraInk.single.strokes as List), hasLength(2));
      // the ring cursor rides the pointer at the page-space radius
      expect(painter.eraserCursor, isNotNull);
      expect(painter.eraserRadius, closeTo(editing.eraserRadius * scale, 1e-6));

      await g.up();
      await tester.pump();
    });

    testWidgets('the committed slice stays painted as the afterimage',
        (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing
        ..addInkStroke(0, [(150, 500), (250, 500)])
        ..finishInk();
      editing.tool = PdfEditTool.eraser;
      await tester.pump();

      await tester.tapAt(view(200, 500), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(editing.document.page(0).annotations.single.inkList, hasLength(2));
      // immediately after the commit (no raster yet) the wash and the
      // remainder keep painting so the old strokes don't pop back
      final painter = overlayPainter(tester);
      expect((painter.fadeInk as List), hasLength(1));
      expect((painter.extraInk as List), hasLength(1));
    });

    testWidgets('hovering with the eraser armed shows the ring cursor',
        (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing.tool = PdfEditTool.eraser;
      await tester.pump();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(5, 5));
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(view(300, 400));
      await tester.pump();

      final painter = overlayPainter(tester);
      expect(painter.eraserCursor, isNotNull);
      expect(painter.eraserRadius, greaterThan(0));
    });
  });

  group('eraser size', () {
    testWidgets('the style menu gains an eraser slider while armed',
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

      // the tune button lives in the Draw group's strip
      await tester.tap(find.byKey(const ValueKey('pdf-group-draw')));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byTooltip('Stroke, opacity, font'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byTooltip('Stroke, opacity, font'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-eraser-size')), findsNothing);

      editing.tool = PdfEditTool.eraser;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-eraser-size')), findsOneWidget);

      await tester.drag(
          find.descendant(
              of: find.byKey(const ValueKey('pdf-eraser-size')),
              matching: find.byType(Slider)),
          const Offset(200, 0));
      await tester.pump();
      expect(editing.eraserRadius, greaterThan(8));
      await tester.pumpAndSettle();
    });

    testWidgets('the tune menu collapses to the eraser size while armed',
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

      // arming the eraser relabels the tune button so the size control
      // is discoverable, not hidden behind 'Stroke, opacity, font'
      editing.tool = PdfEditTool.eraser;
      await tester.pumpAndSettle();
      expect(find.byTooltip('Eraser size'), findsOneWidget);
      expect(find.byTooltip('Stroke, opacity, font'), findsNothing);

      await tester.scrollUntilVisible(find.byTooltip('Eraser size'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byTooltip('Eraser size'));
      await tester.pumpAndSettle();
      // only the eraser slider shows — the paint-only controls are gone
      expect(find.byKey(const ValueKey('pdf-eraser-size')), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Stroke width'), findsNothing);
      expect(find.text('Font size'), findsNothing);
    });

    test('the radius persists as a preference', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      expect(prefs.eraserRadius, 8);
      prefs.eraserRadius = 14;
      await pumpEventQueue();

      final reloaded = PdfEditingPreferences();
      await reloaded.ready;
      expect(reloaded.eraserRadius, 14);
      prefs.dispose();
      reloaded.dispose();
    });
  });
}
