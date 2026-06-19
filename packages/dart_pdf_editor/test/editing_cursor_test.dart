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

dynamic activeStrokePainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(
      of: find.byType(EditingPageOverlay),
      matching: find.byType(CustomPaint),
    ))
    .map((paint) => paint.painter)
    .singleWhere(
      (painter) => painter.runtimeType.toString() == '_ActiveStrokePainter',
    );

/// The overlay's own MouseRegion cursor (the one wrapping the preview
/// painter) — what the system shows while hovering.
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
    expect(overlayPainter(tester).rotateCursor, isNotNull);
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
    final painter = overlayPainter(tester);
    expect(painter.penCursor, isNotNull);
    // the dot draws in the selected pen colour
    expect((painter.color as Color).toARGB32(), 0xFF1565C0);
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
    expect(activeStrokePainter(tester).debugPenCursor, end);
    await g.up();
    await tester.pump();

    expect(overlayPainter(tester).penCursor, end);
  });

  testWidgets('leaving the page retracts the painted pen dot', (tester) async {
    final editing = await pumpViewer(tester);
    editing.tool = PdfEditTool.ink;
    await tester.pump();

    final g = await hoverAt(tester, view(300, 400));
    expect(overlayPainter(tester).penCursor, isNotNull);
    // move far outside the viewer to fire MouseRegion.onExit
    await g.moveTo(const Offset(-50, -50));
    await tester.pump();
    expect(overlayPainter(tester).penCursor, isNull);
  });
}
