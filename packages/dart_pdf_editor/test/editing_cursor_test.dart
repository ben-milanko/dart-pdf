// Mouse cursors over the editing overlay: the grab hand on a selected
// annotation, the diagonal/orthogonal resize cursors on the handles, the
// painted pen-preview dot for the ink tool, and the painted rotation
// glyph over the rotate knob (Flutter ships no rotation cursor).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

/// The overlay's hover-cursor layer: the pen dot, eraser ring, count/stamp
/// previews and the rotation glyph all live here, read off the live overlay
/// state and repainted from a notifier - a hover moves them without
/// rebuilding the overlay, so the *painter instance* may predate the hover
/// and its getters must be read fresh.
dynamic cursorPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(
      of: find.byType(EditingPageOverlay),
      matching: find.byType(CustomPaint),
    ))
    .map((paint) => paint.painter)
    .singleWhere(
      (painter) => painter.runtimeType.toString() == '_HoverCursorPainter',
    );

/// The overlay's own MouseRegion cursor (the one wrapping the preview
/// painter) - what the system shows while hovering.
MouseCursor regionCursor(WidgetTester tester) {
  final paint = find
      .descendant(
          of: find.byType(EditingPageOverlay),
          matching: find.byType(CustomPaint))
      .first;
  final region =
      find.ancestor(of: paint, matching: find.byType(MouseRegion)).first;
  return tester.widget<MouseRegion>(region).cursor;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // 800px viewport over a 612pt page (fit-width)
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  Future<PdfEditingController> pumpViewer(WidgetTester tester) async {
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
    return editing;
  }

  Future<TestGesture> hoverAt(WidgetTester tester, Offset target) async {
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(5, 5));
    addTearDown(g.removePointer);
    await tester.pump();
    await g.moveTo(target);
    await tester.pump();
    return g;
  }

  // a selected, unrotated Square: resizable + rotatable, page x 150..300,
  // y 450..550 (so its centre is page (225, 500))
  Future<PdfEditingController> selectedSquare(WidgetTester tester) async {
    final editing = await pumpViewer(tester);
    editing
      ..addRectangle(0, const PdfRect(150, 450, 300, 550))
      ..tool = PdfEditTool.select;
    expect(editing.selectAnnotationAt(0, 225, 500), isTrue);
    await tester.pump();
    return editing;
  }

  testWidgets('hovering a selected annotation shows the move cursor',
      (tester) async {
    await selectedSquare(tester);
    await hoverAt(tester, view(225, 500));
    expect(regionCursor(tester), SystemMouseCursors.move);
  });

  testWidgets('the top-left handle shows the ↖↘ diagonal resize cursor',
      (tester) async {
    await selectedSquare(tester);
    // the chrome's top-left corner sits at the annotation's (left, top)
    await hoverAt(tester, view(150, 550));
    expect(regionCursor(tester), SystemMouseCursors.resizeUpLeftDownRight);
  });

  testWidgets('the top-right handle shows the ↗↙ diagonal resize cursor',
      (tester) async {
    await selectedSquare(tester);
    await hoverAt(tester, view(300, 550));
    expect(regionCursor(tester), SystemMouseCursors.resizeUpRightDownLeft);
  });

  testWidgets('an edge handle shows a straight resize cursor', (tester) async {
    await selectedSquare(tester);
    // top-centre handle: vertical resize
    await hoverAt(tester, view(225, 550));
    expect(regionCursor(tester), SystemMouseCursors.resizeUpDown);
  });

  testWidgets('the rotate knob hides the cursor and paints the glyph',
      (tester) async {
    await selectedSquare(tester);
    // the knob rides 22px above the chrome's top-centre (zoom 1)
    final top = view(225, 550);
    await hoverAt(tester, Offset(top.dx, top.dy - 22));
    expect(regionCursor(tester), SystemMouseCursors.none);
    expect(cursorPainter(tester).rotateCursor, isNotNull);
  });

  testWidgets('the ink tool paints a pen-preview dot in place of the cursor',
      (tester) async {
    final editing = await pumpViewer(tester);
    editing
      ..color = const Color(0xFF1565C0)
      ..tool = PdfEditTool.ink;
    await tester.pump();

    await hoverAt(tester, view(300, 400));
    expect(regionCursor(tester), SystemMouseCursors.none);
    expect(cursorPainter(tester).penCursor, isNotNull);
    // the dot draws in the selected pen colour
    expect((overlayPainter(tester).color as Color).toARGB32(), 0xFF1565C0);
  });

  testWidgets('the ink cursor follows a mouse-drawn stroke', (tester) async {
    final editing = await pumpViewer(tester);
    editing
      ..inkCommitDelay = null
      ..tool = PdfEditTool.ink;
    await tester.pump();

    final start = view(250, 450);
    final end = view(330, 420);
    await hoverAt(tester, start);
    final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await tester.pump();

    await g.moveTo(end);
    await tester.pump();
    expect(cursorPainter(tester).penCursor, end);
    await g.up();
    await tester.pump();

    expect(cursorPainter(tester).penCursor, end);
  });

  // A stylus never hovers, so pointer-down is the only thing that positions
  // the pen dot for it. This pins that the raw-pointer stroke path sets it -
  // it asserts the *state*, not that the cursor layer was repainted (a widget
  // test reading the painter's getter can't see repaint scheduling, and the
  // one-point stroke paints its own dot at the same spot anyway).
  testWidgets('a stylus press positions the pen cursor with no hover first',
      (tester) async {
    final editing = await pumpViewer(tester);
    editing
      ..inkCommitDelay = null
      ..tool = PdfEditTool.ink;
    await tester.pump();

    final start = view(250, 450);
    final g = await tester.startGesture(start, kind: PointerDeviceKind.stylus);
    await tester.pump();

    expect(cursorPainter(tester).penCursor, start);

    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('leaving the page retracts the painted pen dot', (tester) async {
    final editing = await pumpViewer(tester);
    editing.tool = PdfEditTool.ink;
    await tester.pump();

    final g = await hoverAt(tester, view(300, 400));
    expect(cursorPainter(tester).penCursor, isNotNull);
    // move far outside the viewer to fire MouseRegion.onExit
    await g.moveTo(const Offset(-50, -50));
    await tester.pump();
    expect(cursorPainter(tester).penCursor, isNull);
  });

  // #403: the cursors used to be snapshot arguments of the heavy preview
  // painter, so every mouse-move setState'd the overlay - rebuilding its
  // whole subtree through exactly the moment the user is about to draw.
  // They now live on a repaint-only layer. The tell is the preview painter's
  // identity: a rebuild constructs a fresh one from new arguments, so the
  // same instance still being mounted after a move means no rebuild ran.
  group('hover moves cursors without rebuilding the overlay', () {
    Future<void> expectNoRebuildOnHover(
      WidgetTester tester,
      PdfEditTool tool,
      Object? Function(dynamic cursors) read, {
      void Function(PdfEditingController editing)? setUp,
    }) async {
      final editing = await pumpViewer(tester);
      setUp?.call(editing);
      editing.tool = tool;
      await tester.pump();

      final from = view(300, 400);
      final to = view(340, 420);
      final g = await hoverAt(tester, from);
      expect(read(cursorPainter(tester)), isNotNull,
          reason: '$tool arms a painted cursor');
      final painterBefore = overlayPainter(tester);

      await g.moveTo(to);
      await tester.pump();

      expect(read(cursorPainter(tester)), isNotNull,
          reason: '$tool cursor still painted after the move');
      expect(identical(overlayPainter(tester), painterBefore), isTrue,
          reason: 'a $tool hover rebuilt the overlay');

      // ...and the identity check is sensitive: a change the overlay really
      // does rebuild for swaps the painter out
      editing.color = const Color(0xFF7B1FA2);
      await tester.pump();
      expect(identical(overlayPainter(tester), painterBefore), isFalse);
    }

    testWidgets('ink', (tester) async {
      await expectNoRebuildOnHover(
          tester, PdfEditTool.ink, (cursors) => cursors.penCursor);
    });

    testWidgets('eraser', (tester) async {
      await expectNoRebuildOnHover(
          tester, PdfEditTool.eraser, (cursors) => cursors.eraserCursor);
    });

    testWidgets('count', (tester) async {
      await expectNoRebuildOnHover(
          tester, PdfEditTool.count, (cursors) => cursors.countPreview);
    });

    testWidgets('stamp', (tester) async {
      await expectNoRebuildOnHover(
          tester, PdfEditTool.stamp, (cursors) => cursors.stampPreview);
    });

    testWidgets('signature', (tester) async {
      await expectNoRebuildOnHover(
        tester,
        PdfEditTool.signature,
        (cursors) => cursors.signaturePreview,
        setUp: (editing) => editing.preferences.signature = PdfInkSignature(
          strokes: const [
            [(0.0, 0.0), (1.0, 0.5), (0.0, 1.0)],
          ],
          pressures: const [null],
          color: 0x1A237E,
          aspect: 2,
        ),
      );
    });
  });
}
