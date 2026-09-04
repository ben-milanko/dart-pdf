import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_overlay.dart';
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

dynamic cursorPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(
      of: find.byType(EditingPageOverlay),
      matching: find.byType(CustomPaint),
    ))
    .map((paint) => paint.painter)
    .singleWhere(
      (painter) => painter.runtimeType.toString() == '_HoverCursorPainter',
    );

dynamic gridPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(
      of: find.byType(EditingPageOverlay),
      matching: find.byType(CustomPaint),
    ))
    .map((paint) => paint.painter)
    .singleWhere(
      (painter) => painter.runtimeType.toString() == '_SnapGridPainter',
    );

dynamic alignmentPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byKey(
      const ValueKey('pdf-alignment-guides'),
    ))
    .painter;

dynamic rulerPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byKey(
      const ValueKey('pdf-page-rulers'),
    ))
    .painter;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 800px viewport over a 612x792pt page at fit-width.
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  Future<PdfEditingController> pumpEditor(WidgetTester tester) async {
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

  Future<void> dragMouse(WidgetTester tester, Offset from, Offset to) async {
    final gesture =
        await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
    await gesture.moveTo(to);
    await gesture.up();
    await tester.pump();
  }

  testWidgets('horizontal and vertical cursor guides follow page hover',
      (tester) async {
    final editing = await pumpEditor(tester);
    editing.preferences
      ..showVerticalCursorGuide = true
      ..showHorizontalCursorGuide = true;
    await tester.pump();

    // Guides alone mount a passive editing overlay even with no tool or
    // annotation selection.
    expect(editing.tool, isNull);
    expect(find.byType(EditingPageOverlay), findsWidgets);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(5, 5));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(view(220, 700));
    await tester.pump();

    final painter = cursorPainter(tester);
    expect(painter.verticalGuide, isTrue);
    expect(painter.horizontalGuide, isTrue);
    expect(painter.guideStrokeWidth, 0.75);
    expect(painter.guideHaloWidth, 1.75);
    expect(painter.guideCursor.dx, closeTo(view(220, 700).dx, 0.1));
    expect(painter.guideCursor.dy, closeTo(view(220, 700).dy, 0.1));

    await gesture.moveTo(const Offset(-30, -30));
    await tester.pump();
    expect(cursorPainter(tester).guideCursor, isNull);
  });

  testWidgets('visible snap grid follows the page-space snapping interval',
      (tester) async {
    final editing = await pumpEditor(tester);
    editing.preferences
      ..gridSpacing = 25
      ..showSnapGrid = true;
    await tester.pump();

    // A visible grid alone mounts the otherwise passive overlay. It does not
    // require snapping or an editing tool to be enabled.
    expect(editing.tool, isNull);
    expect(editing.preferences.snapToGrid, isFalse);
    expect(find.byKey(const ValueKey('pdf-snap-grid')), findsWidgets);
    final painter = gridPainter(tester);
    expect(painter.gridSpacing, 25);
    expect(painter.strokeWidth, 0.5);

    final paint = find.byKey(const ValueKey('pdf-snap-grid')).first;
    final segments = List<dynamic>.from(
        painter.segmentsFor(tester.getSize(paint)) as Iterable);
    expect(
      segments.any((segment) =>
          (segment.$1 - view(100, 0)).distance < 0.1 &&
          (segment.$2 - view(100, 792)).distance < 0.1),
      isTrue,
      reason: 'the x=100pt grid line should span the crop box',
    );
  });

  testWidgets('grid snaps creation, movement, and resizing in page points',
      (tester) async {
    final editing = await pumpEditor(tester);
    editing.preferences
      ..gridSpacing = 25
      ..snapToGrid = true;
    editing.tool = PdfEditTool.rectangle;
    await tester.pump();

    await dragMouse(tester, view(103, 703), view(247, 612));
    var rect = editing.document.page(0).annotations.single.rect;
    expect(rect.left, closeTo(100, 0.01));
    expect(rect.bottom, closeTo(600, 0.01));
    expect(rect.right, closeTo(250, 0.01));
    expect(rect.top, closeTo(700, 0.01));

    editing
      ..tool = PdfEditTool.select
      ..selectAnnotation(0, 0);
    await tester.pump();

    // A raw +13/-17pt move snaps the primary box's left/top corner from
    // (100,700) to (125,675), independent of the center grab position.
    await dragMouse(tester, view(175, 650), view(188, 633));
    rect = editing.document.page(0).annotations.single.rect;
    expect(rect.left, closeTo(125, 0.01));
    expect(rect.bottom, closeTo(575, 0.01));
    expect(rect.right, closeTo(275, 0.01));
    expect(rect.top, closeTo(675, 0.01));

    // The bottom-right handle lands at the nearest grid intersection.
    await dragMouse(tester, view(275, 575), view(292, 541));
    rect = editing.document.page(0).annotations.single.rect;
    expect(rect.left, closeTo(125, 0.01));
    expect(rect.bottom, closeTo(550, 0.01));
    expect(rect.right, closeTo(300, 0.01));
    expect(rect.top, closeTo(675, 0.01));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });

  testWidgets('Alt temporarily bypasses grid snapping', (tester) async {
    final editing = await pumpEditor(tester);
    editing.preferences
      ..gridSpacing = 25
      ..snapToGrid = true;
    editing.tool = PdfEditTool.rectangle;
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await dragMouse(tester, view(103, 703), view(247, 612));

    final rect = editing.document.page(0).annotations.single.rect;
    expect(rect.left, closeTo(103, 0.5));
    expect(rect.bottom, closeTo(612, 0.5));
    expect(rect.right, closeTo(247, 0.5));
    expect(rect.top, closeTo(703, 0.5));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });

  testWidgets('smart guides snap annotation edges and centres while moving',
      (tester) async {
    final editing = await pumpEditor(tester);
    editing
      ..addRectangle(0, const PdfRect(100, 650, 200, 750))
      ..addRectangle(0, const PdfRect(300, 500, 400, 600))
      ..tool = PdfEditTool.select
      ..selectAnnotation(0, 0);
    await tester.pump();

    final gesture = await tester.startGesture(view(150, 700),
        kind: PointerDeviceKind.mouse);
    // Raw placement is two points shy on x; y is already aligned. The smart
    // guide should magnetize both axes to the second annotation.
    await gesture.moveTo(view(348, 550));
    await tester.pump();

    expect(find.byKey(const ValueKey('pdf-alignment-guides')), findsOneWidget);
    final painter = alignmentPainter(tester);
    final guides = List<dynamic>.from(painter.guides as Iterable);
    expect(guides.length, 2);
    expect(
        guides.any((g) =>
            g.axis == Axis.vertical &&
            (g.position - view(350, 0).dx).abs() < 0.1),
        isTrue,
        reason: guides.toString());
    expect(
        guides.any((g) =>
            g.axis == Axis.horizontal &&
            (g.position - view(0, 550).dy).abs() < 0.1),
        isTrue);

    await gesture.up();
    await tester.pump();
    final moved = editing.document.page(0).annotations[0].rect;
    expect(moved.left, closeTo(300, 0.01));
    expect(moved.bottom, closeTo(500, 0.01));
    expect(moved.right, closeTo(400, 0.01));
    expect(moved.top, closeTo(600, 0.01));
    expect(find.byKey(const ValueKey('pdf-alignment-guides')), findsNothing);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });

  testWidgets('smart guides snap resize axes and Alt bypasses them',
      (tester) async {
    final editing = await pumpEditor(tester);
    editing
      ..addRectangle(0, const PdfRect(100, 600, 200, 700))
      ..addRectangle(0, const PdfRect(300, 500, 400, 600))
      ..tool = PdfEditTool.select
      ..selectAnnotation(0, 0);
    await tester.pump();

    // Bottom-right is (200, 600) in page space. Land both dragged edges two
    // points from the reference box; they should snap exactly onto it.
    await dragMouse(tester, view(200, 600), view(298, 502));
    var resized = editing.document.page(0).annotations[0].rect;
    expect(resized.right, closeTo(300, 0.01));
    expect(resized.bottom, closeTo(500, 0.01),
        reason: 'target=${editing.document.page(0).annotations[1].rect}');

    // Undo, then make the same drag with Alt down: the raw off-guide values
    // survive and no alignment line is mounted.
    editing.undo();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final gesture = await tester.startGesture(view(200, 600),
        kind: PointerDeviceKind.mouse);
    await gesture.moveTo(view(298, 502));
    await tester.pump();
    expect(find.byKey(const ValueKey('pdf-alignment-guides')), findsNothing);
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    resized = editing.document.page(0).annotations[0].rect;
    expect(resized.right, closeTo(298, 0.5));
    expect(resized.bottom, closeTo(502, 0.5));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });

  testWidgets('optional page rulers use adaptive point ticks and hover marks',
      (tester) async {
    final editing = await pumpEditor(tester);
    editing.preferences.showPageRulers = true;
    await tester.pump();

    expect(find.byKey(const ValueKey('pdf-page-rulers')), findsOneWidget);
    var painter = rulerPainter(tester);
    expect(painter.bandWidth, 24);
    expect(painter.majorStepFor(const Size(800, 1035)), 50);
    expect(painter.cursor, isNull);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(5, 5));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(view(220, 700));
    await tester.pump();
    painter = rulerPainter(tester);
    expect(painter.cursor.dx, closeTo(view(220, 700).dx, 0.1));
    expect(painter.cursor.dy, closeTo(view(220, 700).dy, 0.1));
  });

  testWidgets('editor settings exposes persistent guide and grid controls',
      (tester) async {
    final preferences = PdfEditingPreferences();
    addTearDown(preferences.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfEditorView(
          bytes: buildMultiPagePdf(1),
          preferences: preferences,
        ),
      ),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('pdf-editing-guides')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-shell-editing-guides')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-smart-alignment-guides')));
    await tester.tap(find.byKey(const ValueKey('pdf-page-rulers')));
    await tester.tap(find.byKey(const ValueKey('pdf-cursor-guide-vertical')));
    await tester.tap(find.byKey(const ValueKey('pdf-grid-snap')));
    await tester.tap(find.byKey(const ValueKey('pdf-grid-visible')));
    await tester.pump();

    expect(preferences.smartAlignmentGuides, isFalse);
    expect(preferences.showPageRulers, isTrue);
    expect(preferences.showVerticalCursorGuide, isTrue);
    expect(preferences.snapToGrid, isTrue);
    expect(preferences.showSnapGrid, isTrue);

    await tester.tap(find.byKey(const ValueKey('pdf-guides-done')));
    await tester.pumpAndSettle();
  });

  test('guide and grid preferences persist', () async {
    final first = PdfEditingPreferences();
    await first.ready;
    first
      ..smartAlignmentGuides = false
      ..showPageRulers = true
      ..showVerticalCursorGuide = true
      ..showHorizontalCursorGuide = true
      ..showSnapGrid = true
      ..snapToGrid = true
      ..gridSpacing = 12.5;
    await pumpEventQueue();

    final second = PdfEditingPreferences();
    await second.ready;
    expect(second.smartAlignmentGuides, isFalse);
    expect(second.showPageRulers, isTrue);
    expect(second.showVerticalCursorGuide, isTrue);
    expect(second.showHorizontalCursorGuide, isTrue);
    expect(second.showSnapGrid, isTrue);
    expect(second.snapToGrid, isTrue);
    expect(second.gridSpacing, 12.5);
    first.dispose();
    second.dispose();
  });
}
