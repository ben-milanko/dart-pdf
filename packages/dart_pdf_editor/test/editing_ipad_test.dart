// The iPad input round: touch pinch zoom, raw-driven (zero-latency)
// stylus/finger ink, multi-touch bail, the touch selection action chip,
// and the eraser tool.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // the mock store is process-global; stale prefs leak across tests
    SharedPreferences.setMockInitialValues({});
  });

  // 800px viewport over a 612pt page (fit-width)
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  Future<(PdfEditingController, PdfViewerController)> pumpViewer(
      WidgetTester tester,
      {int pages = 1}) async {
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

  group('touch pinch zoom', () {
    testWidgets('two fingers moving apart zoom in around the gesture',
        (tester) async {
      final (_, viewer) = await pumpViewer(tester, pages: 3);
      expect(viewer.zoom, closeTo(1, 0.01));

      final g1 = await tester.startGesture(const Offset(300, 200));
      final g2 = await tester.startGesture(const Offset(500, 400));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await g1.moveBy(const Offset(-12, -12));
        await g2.moveBy(const Offset(12, 12));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 400));

      // span grew 283 → 487 px; the settle clamp keeps it past fit-width
      expect(viewer.zoom, greaterThan(1.3));
    });

    testWidgets('pinching back together zooms out again', (tester) async {
      final (_, viewer) = await pumpViewer(tester, pages: 3);
      final g1 = await tester.startGesture(const Offset(300, 200));
      final g2 = await tester.startGesture(const Offset(500, 400));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await g1.moveBy(const Offset(-12, -12));
        await g2.moveBy(const Offset(12, 12));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 400));
      final zoomedIn = viewer.zoom;
      expect(zoomedIn, greaterThan(1.3));

      final g3 = await tester.startGesture(const Offset(240, 140));
      final g4 = await tester.startGesture(const Offset(560, 460));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await g3.moveBy(const Offset(12, 12));
        await g4.moveBy(const Offset(-12, -12));
        await tester.pump();
      }
      await g3.up();
      await g4.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(viewer.zoom, lessThan(zoomedIn - 0.2));
    });
  });

  group('raw-driven ink', () {
    testWidgets('a stylus stroke starts on pointer-down, well under the slop',
        (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing.tool = PdfEditTool.ink;
      await tester.pump();

      // 16px of total motion — under every recognizer's slop, so the
      // old arena path would have dropped this stroke as a tap
      final g = await tester.startGesture(view(200, 500),
          kind: PointerDeviceKind.stylus);
      await g.moveBy(const Offset(8, 0));
      await g.moveBy(const Offset(8, 0));
      await g.up();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));

      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(1));
      expect(annotations.single.subtype, 'Ink');
      expect(annotations.single.inkList!.single.length, greaterThan(2));
    });

    testWidgets('a quick stylus dot commits as a zero-length stroke',
        (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing.tool = PdfEditTool.ink;
      await tester.pump();

      final g = await tester.startGesture(view(300, 500),
          kind: PointerDeviceKind.stylus);
      await g.up();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));

      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(1));
      final stroke = annotations.single.inkList!.single;
      expect(stroke, hasLength(2));
      expect(stroke[0], stroke[1]); // the dot: both ends at the tap
    });

    testWidgets('two quick dots aggregate into ink and never zoom',
        (tester) async {
      final (editing, viewer) = await pumpViewer(tester);
      editing.tool = PdfEditTool.ink;
      await tester.pump();

      final g1 = await tester.startGesture(view(300, 500),
          kind: PointerDeviceKind.stylus);
      await g1.up();
      await tester.pump(const Duration(milliseconds: 80));
      final g2 = await tester.startGesture(view(302, 510),
          kind: PointerDeviceKind.stylus);
      await g2.up();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));

      // both dots landed (one annotation: they share the commit window),
      // and the viewer's stylus double-tap zoom stood aside
      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(1));
      expect(annotations.single.inkList, hasLength(2));
      expect(viewer.zoom, closeTo(1, 0.01));
    });

    testWidgets('a finger draws raw when finger drawing is on', (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing.tool = PdfEditTool.ink;
      expect(editing.fingerDrawsInk, isTrue);
      await tester.pump();

      final g = await tester.startGesture(view(200, 500));
      await g.moveBy(const Offset(10, 0));
      await g.up();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));

      expect(editing.document.page(0).annotations, hasLength(1));
    });
  });

  group('multi-touch bail', () {
    testWidgets('a second finger cancels the stroke in flight', (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing.tool = PdfEditTool.ink;
      await tester.pump();

      final g1 = await tester.startGesture(view(200, 520));
      await g1.moveBy(const Offset(15, 0));
      await tester.pump();
      final g2 = await tester.startGesture(view(350, 450));
      await tester.pump();
      // the dead remainder of the gesture must not revive the stroke
      await g1.moveBy(const Offset(40, 10));
      await tester.pump();
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));

      expect(editing.document.page(0).annotations, isEmpty);
    });

    testWidgets('a bail re-arms the auto-commit for buffered strokes',
        (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing.tool = PdfEditTool.ink;
      await tester.pump();
      editing.addInkStroke(0, [(100, 500), (150, 510)]);

      final g1 = await tester.startGesture(view(200, 520));
      await g1.moveBy(const Offset(15, 0));
      await tester.pump();
      final g2 = await tester.startGesture(view(350, 450));
      await tester.pump();
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));

      // the earlier stroke committed alone; the bailed one is gone
      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(1));
      expect(annotations.single.inkList, hasLength(1));
    });

    testWidgets('palm touches do not cancel a stylus stroke', (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing.tool = PdfEditTool.ink;
      await tester.pump();

      final pen = await tester.startGesture(view(200, 500),
          kind: PointerDeviceKind.stylus);
      await pen.moveBy(const Offset(10, 0));
      await tester.pump();
      // the palm settles: two touch contacts while the pen keeps moving
      final palm1 = await tester.startGesture(view(350, 420));
      final palm2 = await tester.startGesture(view(380, 410));
      await tester.pump();
      await pen.moveBy(const Offset(10, 0));
      await pen.up();
      await palm1.up();
      await palm2.up();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));

      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(1));
      expect(annotations.single.inkList!.single.length, greaterThan(2));
    });
  });

  group('pencil-mode finger pan', () {
    ScrollPosition scrollPosition(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    // A single-finger upward drag with explicit timestamps (TestGesture
    // stamps every event t=0 otherwise, which reads as zero velocity).
    Future<(TestGesture, Duration)> swipeUp(WidgetTester tester) async {
      var stamp = Duration.zero;
      final g = await tester.startGesture(view(300, 600),
          kind: PointerDeviceKind.touch);
      for (var i = 0; i < 6; i++) {
        stamp += const Duration(milliseconds: 16);
        await g.moveBy(const Offset(0, -40), timeStamp: stamp);
        await tester.pump(const Duration(milliseconds: 16));
      }
      return (g, stamp);
    }

    testWidgets('a finger scrolls when ink is armed and finger drawing is off',
        (tester) async {
      final (editing, _) = await pumpViewer(tester, pages: 4);
      editing.tool = PdfEditTool.ink;
      // the state the first Apple Pencil touch leaves behind: pen draws,
      // fingers scroll
      editing.fingerDrawsInk = false;
      await tester.pump();

      final (g, stamp) = await swipeUp(tester);
      expect(scrollPosition(tester).pixels, greaterThan(100));
      // the finger panned the page; it did NOT draw
      expect(editing.document.page(0).annotations, isEmpty);

      await g.up(timeStamp: stamp + const Duration(milliseconds: 16));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a finger draws (does not scroll) when finger drawing is on',
        (tester) async {
      final (editing, _) = await pumpViewer(tester, pages: 4);
      editing.tool = PdfEditTool.ink;
      expect(editing.fingerDrawsInk, isTrue);
      await tester.pump();

      final (g, stamp) = await swipeUp(tester);
      // finger-draws mode: the stroke is raw-driven, the page stays put
      expect(scrollPosition(tester).pixels, 0);
      await g.up(timeStamp: stamp + const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));

      expect(editing.document.page(0).annotations, hasLength(1));
    });

    testWidgets('a touch during a pen stroke is a palm, not a pan',
        (tester) async {
      final (editing, _) = await pumpViewer(tester, pages: 4);
      editing.tool = PdfEditTool.ink;
      editing.fingerDrawsInk = false;
      await tester.pump();

      final pen = await tester.startGesture(view(200, 500),
          kind: PointerDeviceKind.stylus);
      await pen.moveBy(const Offset(10, 0));
      await tester.pump();
      // the palm rests and "drags" while the pen draws: it must not pan
      final palm = await tester.startGesture(view(350, 600),
          kind: PointerDeviceKind.touch);
      for (var i = 0; i < 4; i++) {
        await palm.moveBy(const Offset(0, -40));
        await tester.pump();
      }
      expect(scrollPosition(tester).pixels, 0);

      await pen.up();
      await palm.up();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));
      expect(editing.document.page(0).annotations, hasLength(1));
    });
  });

  group('eraser', () {
    test('inkAnnotationAt demands proximity to the strokes, not the rect',
        () async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addInkStroke(0, [(100, 500), (200, 500), (200, 600)])
        ..finishInk();
      // near the horizontal segment: hit
      expect(editing.inkAnnotationAt(0, 150, 502), isNotNull);
      // inside the bounding rect but far from both segments: miss
      expect(editing.inkAnnotationAt(0, 110, 590), isNull);
      editing.dispose();
    });

    testWidgets('a mouse drag slices crossed strokes as one undo step',
        (tester) async {
      final (editing, _) = await pumpViewer(tester);
      // two commits: strokes buffered together would aggregate into one
      editing
        ..addInkStroke(0, [(150, 500), (250, 500)])
        ..finishInk()
        ..addInkStroke(0, [(150, 450), (250, 450)])
        ..finishInk();
      expect(editing.document.page(0).annotations, hasLength(2));
      editing.tool = PdfEditTool.eraser;
      await tester.pump();

      final g = await tester.startGesture(view(200, 520),
          kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 10; i++) {
        await g.moveBy(Offset(0, 10 * scale));
        await tester.pump();
      }
      await g.up();
      await tester.pump();

      // the circle eraser slices, PSPDFKit-style: both annotations
      // survive, each split where the swipe crossed them
      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(2));
      for (final annotation in annotations) {
        expect(annotation.inkList, hasLength(2));
      }
      editing.undo();
      for (final annotation in editing.document.page(0).annotations) {
        expect(annotation.inkList, hasLength(1));
      }
    });

    testWidgets('a stylus erases raw, from the pointer-down', (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing
        ..addInkStroke(0, [(150, 500), (250, 500)])
        ..finishInk();
      editing.tool = PdfEditTool.eraser;
      await tester.pump();

      // a bare tap stamps one circle out of the stroke's middle
      final g = await tester.startGesture(view(200, 500),
          kind: PointerDeviceKind.stylus);
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));

      final ink = editing.document.page(0).annotations.single;
      expect(ink.inkList, hasLength(2));
      // the cut hugs the eraser circle (default radius 8pt about x=200)
      expect(ink.inkList![0].last.$1, closeTo(192, 0.5));
      expect(ink.inkList![1].first.$1, closeTo(208, 0.5));
    });

    testWidgets('a flipped pencil erases while the ink tool is armed',
        (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing
        ..addInkStroke(0, [(150, 500), (250, 500)])
        ..finishInk();
      editing.tool = PdfEditTool.ink;
      await tester.pump();

      final g = await tester.startGesture(view(200, 500),
          kind: PointerDeviceKind.invertedStylus);
      await g.moveBy(const Offset(5, 0));
      await g.up();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));

      // sliced the stroke under it and drew nothing of its own
      final ink = editing.document.page(0).annotations.single;
      expect(ink.subtype, 'Ink');
      expect(ink.inkList, hasLength(2));
    });
  });

  group('selection action chip', () {
    testWidgets('shows for a touch selection; delete deletes', (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing
        ..addRectangle(0, const PdfRect(150, 450, 300, 550))
        ..tool = PdfEditTool.select;
      await tester.pump();

      await tester.tapAt(view(225, 500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(editing.hasAnnotationSelection, isTrue);
      expect(find.byKey(const ValueKey('pdf-selection-chip')), findsOneWidget);
      // a plain shape offers no text edit
      expect(
          find.byKey(const ValueKey('pdf-selection-chip-edit')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('pdf-selection-chip-delete')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(editing.document.page(0).annotations, isEmpty);
      expect(find.byKey(const ValueKey('pdf-selection-chip')), findsNothing);
    });

    testWidgets('stays hidden for mouse selections', (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing
        ..addRectangle(0, const PdfRect(150, 450, 300, 550))
        ..tool = PdfEditTool.select;
      await tester.pump();

      await tester.tapAt(view(225, 500), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(editing.hasAnnotationSelection, isTrue);
      expect(find.byKey(const ValueKey('pdf-selection-chip')), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the more button opens the annotation context menu',
        (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing
        ..addRectangle(0, const PdfRect(150, 450, 300, 550))
        ..tool = PdfEditTool.select;
      await tester.pump();

      await tester.tapAt(view(225, 500));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('pdf-selection-chip-menu')));
      // touch taps resolve only after the viewer's double-tap timeout
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('pdf-annot-menu-delete')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-delete')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(editing.document.page(0).annotations, isEmpty);
    });

    testWidgets('free text gets an edit button that opens the inline editor',
        (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing
        ..addFreeText(0, const PdfRect(150, 450, 350, 520), 'hello')
        ..tool = PdfEditTool.select;
      await tester.pump();

      await tester.tapAt(view(250, 485));
      await tester.pump(const Duration(milliseconds: 400));
      final edit = find.byKey(const ValueKey('pdf-selection-chip-edit'));
      expect(edit, findsOneWidget);
      await tester.tap(edit);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('pdf-freetext-editor')), findsOneWidget);
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const ValueKey('pdf-freetext-editor')))
              .controller!
              .text,
          'hello');
    });
  });
}
