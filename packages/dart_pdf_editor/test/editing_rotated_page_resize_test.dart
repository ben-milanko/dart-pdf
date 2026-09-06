// Resizing an annotation on a display-rotated (/Rotate 90) page.
//
// The selection chrome spins for an annotation whose *appearance* is
// rotated inside its /Rect. A page's /Rotate is not that: it turns the
// whole page, chrome included, so an annotation square to its page is
// square on screen too. Reading the on-screen quad alone conflated the
// two - every box on a rotated page looked turned 90°, which transposed
// its handles (the right-middle one resized vertically, with an up-down
// cursor) and committed a transposed box.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_overlay.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The overlay's own MouseRegion cursor - what the system shows on hover.
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

  // A 612×792 page with /Rotate 90 displays landscape: 792pt across an
  // 800px viewport. Page (x, y) lands at view (y, x) · scale.
  const scale = 800 / 792;
  Offset view(double x, double y) => Offset(y * scale, x * scale);

  Future<PdfEditingController> pumpViewer(WidgetTester tester,
      {int rotation = 90}) async {
    final editing =
        PdfEditingController(buildMultiPagePdf(1, rotation: rotation));
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

  // A text box that reads as a wide one on screen: page-space 50×200
  // (x 100..150, y 500..700), which the page's quarter turn shows as
  // 200 wide and 50 tall.
  Future<PdfEditingController> selectedTextBox(WidgetTester tester) async {
    final editing = await pumpViewer(tester);
    editing
      ..preferences.fontSize = 12
      ..addFreeText(0, const PdfRect(100, 500, 150, 700), 'BPM')
      ..tool = PdfEditTool.select;
    expect(editing.selectAnnotationAt(0, 125, 600), isTrue);
    await tester.pump();
    return editing;
  }

  testWidgets('a text box on a rotated page is not treated as rotated',
      (tester) async {
    final editing = await selectedTextBox(tester);
    expect(editing.selectedAnnotation!.appearanceRotation, 0);
  });

  testWidgets('the right-middle handle shows the left-right resize cursor',
      (tester) async {
    await selectedTextBox(tester);
    // the middle of the box's right edge on screen: page (125, 700)
    await hoverAt(tester, view(125, 700));
    expect(regionCursor(tester), SystemMouseCursors.resizeLeftRight);
  });

  testWidgets('dragging the right-middle handle widens the box on screen',
      (tester) async {
    final editing = await selectedTextBox(tester);

    // drag it 50pt to the right on screen - which is +y in page space
    final gesture = await tester.startGesture(view(125, 700));
    await gesture.moveBy(Offset(25 * scale, 0));
    await gesture.moveBy(Offset(25 * scale, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 350));

    // the box grew along its screen width only: page x untouched, page
    // y extended past the dragged edge. Transposing it (the bug) turned
    // the wide box into a tall one instead.
    final rect = editing.document.page(0).annotations.single.rect;
    expect(rect.left, closeTo(100, 0.5));
    expect(rect.right, closeTo(150, 0.5));
    expect(rect.bottom, closeTo(500, 0.5));
    expect(rect.top, closeTo(750, 0.5));
  });

  testWidgets('the top-middle handle still resizes the box vertically',
      (tester) async {
    final editing = await selectedTextBox(tester);

    // the middle of the box's top edge on screen is page (100, 600) -
    // dragged with a mouse, since a vertical touch drag over the page
    // belongs to the scroll view
    final gesture = await tester.startGesture(view(100, 600),
        kind: PointerDeviceKind.mouse);
    await gesture.moveBy(Offset(0, -10 * scale));
    await gesture.moveBy(Offset(0, -10 * scale));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 350));

    // screen-up is -x in page space
    final rect = editing.document.page(0).annotations.single.rect;
    expect(rect.left, closeTo(80, 0.5));
    expect(rect.right, closeTo(150, 0.5));
    expect(rect.bottom, closeTo(500, 0.5));
    expect(rect.top, closeTo(700, 0.5));
  });

  testWidgets('a genuinely rotated annotation still spins its chrome',
      (tester) async {
    // same viewer, unrotated page: a square turned 90° by the rotate
    // knob keeps the local-frame treatment (its cursor follows the
    // handle round, and the resize runs along the artwork's own axes)
    final editing = await pumpViewer(tester, rotation: 0);
    const scale0 = 800 / 612;
    Offset view0(double x, double y) => Offset(x * scale0, (792 - y) * scale0);
    editing
      ..color = const Color(0xFFFF0000)
      ..addRectangle(0, const PdfRect(150, 450, 300, 550))
      ..tool = PdfEditTool.select
      ..selectAnnotation(0, 0)
      ..rotateSelected(90);
    await tester.pump();

    final annotation = editing.selectedAnnotation!;
    expect(annotation.appearanceRotation, closeTo(math.pi / 2, 1e-6));
    // 150×100 about (225,500) → page rect 100×150; the local +x axis
    // points up on screen, so the local right-middle handle sits on the
    // top edge - and its cursor reads up-down, the direction it moves
    await hoverAt(tester, view0(225, 575));
    expect(regionCursor(tester), SystemMouseCursors.resizeUpDown);
  });
}
