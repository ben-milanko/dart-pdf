import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Placing a polyline vertex by vertex: Ctrl+Z steps back through the placed
/// vertices, the middle button pans without dropping a node, and resting the
/// pointer against a viewport edge scrolls the document under the path.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  // 800px viewport over a 612x792pt page (matches editing_test.dart).
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  Future<(PdfEditingController, PdfViewerController)> pumpEditor(
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
    editing.tool = PdfEditTool.polyline;
    await tester.pump();
    return (editing, viewer);
  }

  Future<void> click(WidgetTester tester, Offset at) async {
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> finishAt(WidgetTester tester, Offset at) async {
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  }

  Future<void> pressUndo(WidgetTester tester) async {
    await simulateKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await simulateKeyDownEvent(LogicalKeyboardKey.keyZ);
    await simulateKeyUpEvent(LogicalKeyboardKey.keyZ);
    await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('Ctrl+Z drops the last placed vertex, not a revision',
      (tester) async {
    final (editing, _) = await pumpEditor(tester);
    await click(tester, view(100, 700));
    await click(tester, view(200, 650));
    await click(tester, view(300, 700));
    expect(editing.hasPlacementDraft, isTrue);
    expect(editing.canUndo, isTrue);

    await pressUndo(tester); // drops (300, 700)
    expect(editing.document.page(0).annotations, isEmpty);

    await finishAt(tester, view(250, 600));
    final v = editing.document.page(0).annotations.single.vertices!;
    expect(v, hasLength(3));
    expect(v[1].$1, closeTo(200, 1));
    expect(v[1].$2, closeTo(650, 1));
    expect(v[2].$1, closeTo(250, 1), reason: 'the undone vertex is gone');
    expect(v[2].$2, closeTo(600, 1));
    expect(editing.hasPlacementDraft, isFalse);

    // with no draft left, Ctrl+Z is the document undo again
    await pressUndo(tester);
    expect(editing.document.page(0).annotations, isEmpty);
  });

  testWidgets('undoing the first vertex abandons the draft', (tester) async {
    final (editing, _) = await pumpEditor(tester);
    await click(tester, view(100, 700));
    await pressUndo(tester);
    expect(editing.hasPlacementDraft, isFalse);
    expect(editing.canUndo, isFalse);

    // the next click starts a fresh path
    await click(tester, view(150, 500));
    await finishAt(tester, view(300, 500));
    final v = editing.document.page(0).annotations.single.vertices!;
    expect(v, hasLength(2));
    expect(v.first.$1, closeTo(150, 1));
  });

  testWidgets('a middle-button drag pans without placing a vertex',
      (tester) async {
    final (editing, viewer) = await pumpEditor(tester);
    await click(tester, view(100, 700));
    await click(tester, view(200, 650));
    final before = viewer.visiblePageRegion(0)!;

    final pan = await tester.startGesture(const Offset(400, 400),
        kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    for (var i = 1; i <= 6; i++) {
      await pan.moveTo(Offset(400, 400.0 - 30 * i));
      await tester.pump();
    }
    await pan.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    final after = viewer.visiblePageRegion(0)!;
    expect(after.top, greaterThan(before.top), reason: 'the document panned');
    expect(editing.hasPlacementDraft, isTrue, reason: 'the path survives');
    expect(editing.document.page(0).annotations, isEmpty);
  });

  testWidgets('Space pans an unfinished path without adding a vertex',
      (tester) async {
    final (editing, viewer) = await pumpEditor(tester);
    await click(tester, view(100, 700));
    await click(tester, view(200, 650));
    final before = viewer.visiblePageRegion(0)!;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final pan = await tester.startGesture(const Offset(400, 400),
        kind: PointerDeviceKind.mouse);
    await pan.moveBy(const Offset(0, -120));
    await tester.pump();
    await pan.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(viewer.visiblePageRegion(0)!.top, greaterThan(before.top));
    expect(editing.hasPlacementDraft, isTrue);
    expect(editing.tool, PdfEditTool.polyline);
    expect(editing.document.page(0).annotations, isEmpty);
    await pressUndo(tester);
    expect(editing.hasPlacementDraft, isTrue);
    await pressUndo(tester);
    expect(editing.hasPlacementDraft, isFalse,
        reason: 'exactly two original vertices survived');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hovering at the viewport edge scrolls mid-path', (tester) async {
    final (editing, viewer) = await pumpEditor(tester);
    // one mouse for the click and the hover that follows it
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: view(100, 700));
    await mouse.down(view(100, 700));
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(editing.hasPlacementDraft, isTrue);
    final before = viewer.visiblePageRegion(0)!;

    await mouse.moveTo(const Offset(400, 300));
    await mouse.moveTo(const Offset(400, 595)); // the bottom edge band
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final scrolled = viewer.visiblePageRegion(0)!;
    expect(scrolled.top, greaterThan(before.top),
        reason: 'the document scrolls toward the edge the pointer rests on');

    // back in the middle the scrolling stops
    await mouse.moveTo(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 16));
    final settled = viewer.visiblePageRegion(0)!;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(viewer.visiblePageRegion(0)!.top, closeTo(settled.top, 1e-6));
    expect(editing.hasPlacementDraft, isTrue);
    await mouse.removePointer();
  });

  testWidgets('with no path in progress, hovering the edge does not scroll',
      (tester) async {
    final (_, viewer) = await pumpEditor(tester);
    final before = viewer.visiblePageRegion(0)!;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 300));
    await mouse.moveTo(const Offset(400, 595));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(viewer.visiblePageRegion(0)!.top, closeTo(before.top, 1e-6));
    await mouse.removePointer();
  });
}
