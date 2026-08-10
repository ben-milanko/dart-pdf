import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// Holding Shift constrains the straight-line drawing tools: the line family
/// and each polyline/polygon edge snap to the nearest 45° axis, and a freehand
/// ink stroke collapses to a ruler-straight segment from where it began.
void main() {
  // 800px viewport over a 612x792pt page (matches editing_test.dart).
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  Future<void> holdShift(WidgetTester tester) async {
    await simulateKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    addTearDown(() => simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft));
  }

  Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
    final gesture = await tester.startGesture(from);
    await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
    await gesture.moveTo(to);
    await gesture.up();
    await tester.pump();
  }

  /// Flushes the commit afterimage's debounced timers.
  Future<void> settle(WidgetTester tester) =>
      tester.pumpAndSettle(const Duration(milliseconds: 400));

  Future<PdfEditingController> pumpEditor(WidgetTester tester,
      {PdfViewerController? viewerController}) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = viewerController ?? PdfViewerController();
    addTearDown(editing.dispose);
    if (viewerController == null) addTearDown(viewer.dispose);
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

  testWidgets('Shift snaps a line drag to the nearest 45° axis',
      (tester) async {
    final editing = await pumpEditor(tester);
    editing.tool = PdfEditTool.line;
    await tester.pump();
    await holdShift(tester);

    // a nearly-horizontal drag (10pt of rise over 150pt of run) snaps flat
    await drag(tester, view(100, 700), view(250, 690));

    final line = editing.document.page(0).annotations.single.line;
    expect(line, isNotNull);
    final ((x1, y1), (x2, y2)) = line!;
    expect(x1, closeTo(100, 1));
    expect(y1, closeTo(700, 1));
    expect(x2, closeTo(250, 1));
    expect(y2, closeTo(700, 1), reason: 'the endpoint is pulled onto y = y1');
    await settle(tester);
  });

  testWidgets('Shift snaps a line drag to the diagonal', (tester) async {
    final editing = await pumpEditor(tester);
    editing.tool = PdfEditTool.line;
    await tester.pump();
    await holdShift(tester);

    // a ~40° drag lands nearest the 45° diagonal
    await drag(tester, view(100, 700), view(200, 780));

    final ((x1, y1), (x2, y2)) =
        editing.document.page(0).annotations.single.line!;
    expect((x2 - x1).abs(), closeTo((y2 - y1).abs(), 1),
        reason: 'equal run and rise is a 45° segment');
    await settle(tester);
  });

  testWidgets('Shift snaps each polyline edge to a straight axis',
      (tester) async {
    final editing = await pumpEditor(tester);
    editing.tool = PdfEditTool.polyline;
    await tester.pump();
    await holdShift(tester);

    // three vertices, each tapped a little off-horizontal from the last
    await tester.tapAt(view(100, 700));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(view(180, 690));
    await tester.pump(const Duration(milliseconds: 400));
    // double-tap the third spot to place it and finish
    await tester.tapAt(view(240, 690));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(view(240, 690));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    final annotation = editing.document.page(0).annotations.single;
    expect(annotation.subtype, 'PolyLine');
    expect(annotation.vertices, hasLength(3));
    // every vertex snaps flat onto the first row
    for (final v in annotation.vertices!) {
      expect(v.$2, closeTo(700, 1));
    }
    expect(annotation.vertices![1].$1, closeTo(180, 1));
    expect(annotation.vertices![2].$1, closeTo(240, 1));
  });

  testWidgets('Shift only straightens the segment being drawn', (tester) async {
    final editing = await pumpEditor(tester);
    editing.tool = PdfEditTool.polyline;
    await tester.pump();

    // first two vertices placed WITHOUT Shift - an angled opening segment
    await tester.tapAt(view(100, 700));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(view(150, 660));
    await tester.pump(const Duration(milliseconds: 400));

    // now hold Shift and place the third: only this last edge snaps flat
    await holdShift(tester);
    await tester.tapAt(view(240, 650));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(view(240, 650));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    final v = editing.document.page(0).annotations.single.vertices!;
    expect(v, hasLength(3));
    // the opening segment kept its angle (not straightened retroactively)
    expect(v[0].$1, closeTo(100, 1));
    expect(v[0].$2, closeTo(700, 1));
    expect(v[1].$1, closeTo(150, 1));
    expect(v[1].$2, closeTo(660, 1));
    // only the last edge snapped: v2 sits on v1's row
    expect(v[2].$2, closeTo(660, 1),
        reason: 'the Shift-held edge is horizontal off v1');
    expect(v[2].$1, closeTo(240, 1));
  });

  testWidgets('Shift straightens a freehand ink stroke', (tester) async {
    final editing = await pumpEditor(tester);
    editing.tool = PdfEditTool.ink;
    await tester.pump();
    await holdShift(tester);

    // a zig-zag drag: without Shift this is three-plus points; with Shift it
    // collapses to a single segment from the origin to the release point
    final gesture = await tester.startGesture(view(100, 700));
    await gesture.moveTo(view(150, 680));
    await gesture.moveTo(view(120, 760));
    await gesture.moveTo(view(200, 730));
    await gesture.up();
    await tester.pump();

    final strokes = editing.strokesOn(0);
    expect(strokes, hasLength(1));
    final stroke = strokes.single;
    expect(stroke, hasLength(2), reason: 'origin and release only');
    expect(stroke.first.$1, closeTo(100, 1));
    expect(stroke.first.$2, closeTo(700, 1));
    expect(stroke.last.$1, closeTo(200, 1));
    expect(stroke.last.$2, closeTo(730, 1));
    editing.finishInk();
    expect(editing.document.page(0).annotations.single.subtype, 'Ink');
    await settle(tester);
  });

  testWidgets('Ctrl+wheel zooms after Shift-constrained ink', (tester) async {
    final viewer = PdfViewerController();
    addTearDown(viewer.dispose);
    final editing = await pumpEditor(tester, viewerController: viewer);
    editing.tool = PdfEditTool.ink;
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await drag(tester, view(100, 700), view(200, 730));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    final before = viewer.zoom;
    final pointer = TestPointer(23, PointerDeviceKind.mouse);
    pointer.hover(const Offset(400, 300));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -200)));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(viewer.zoom, greaterThan(before));
    editing.finishInk();
  });
}
