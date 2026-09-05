import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holding Shift constrains the straight-line drawing tools: the line family
/// and each polyline/polygon edge snap to the nearest 45° axis. For freehand
/// ink, Shift constrains only the tail drawn after the modifier goes down.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
      {PdfViewerController? viewerController, GlobalKey? boundary}) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = viewerController ?? PdfViewerController();
    addTearDown(editing.dispose);
    if (viewerController == null) addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: boundary,
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

  testWidgets('Shift snaps a freehand ink stroke to a 45 degree line',
      (tester) async {
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
    expect(stroke.last.$2, closeTo(700, 1));
    editing.finishInk();
    expect(editing.document.page(0).annotations.single.subtype, 'Ink');
    await settle(tester);
  });

  for (final kind in [
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus
  ]) {
    testWidgets(
        '${kind.name}: early Shift release preserves the prefix and snap',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.ink;
      await tester.pump();

      final gesture = await tester.startGesture(view(100, 700), kind: kind);
      await gesture.moveTo(view(130, 675));
      await gesture.moveTo(view(160, 700));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await gesture.moveTo(view(200, 690));
      // Key-up can arrive before the last movement and pointer-up.
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await gesture.moveTo(view(250, 680));
      await gesture.up();
      await tester.pump();

      final strokes = editing.strokesOn(0);
      expect(strokes, hasLength(2),
          reason: 'separate paths preserve the corner at the Shift anchor');
      final prefix = strokes.first;
      final tail = strokes.last;
      expect(prefix, hasLength(3));
      expect(prefix[1].$1, closeTo(130, 1));
      expect(prefix[1].$2, closeTo(675, 1));
      expect(prefix.last.$1, closeTo(160, 1));
      expect(prefix.last.$2, closeTo(700, 1));
      expect(tail, hasLength(2));
      expect(tail.first, prefix.last);
      expect(tail.last.$1, closeTo(250, 1));
      expect(tail.last.$2, closeTo(700, 1),
          reason: 'the new tail snaps horizontally from the Shift anchor');
      editing.finishInk();
      await settle(tester);

      // A new pointer stroke must return to ordinary freehand drawing.
      final next = await tester.startGesture(view(300, 700), kind: kind);
      await next.moveTo(view(340, 650));
      await next.moveTo(view(380, 690));
      await next.up();
      final freehand = editing.strokesOn(0).single;
      expect(freehand, hasLength(3));
      expect(freehand[1].$2, closeTo(650, 1));
      expect(freehand.last.$2, closeTo(690, 1));
      editing.finishInk();
      await settle(tester);
    });
  }

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.stylus]) {
    testWidgets('${kind.name}: cancellation clears the Shift constraint',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.ink;
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final gesture = await tester.startGesture(view(100, 700), kind: kind);
      await gesture.moveTo(view(170, 680));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await gesture.cancel();
      await tester.pump();
      expect(editing.hasPendingInk, isFalse);
      final next = await tester.startGesture(view(300, 700), kind: kind);
      await next.moveTo(view(340, 650));
      await next.moveTo(view(380, 690));
      await next.up();
      final stroke = editing.strokesOn(0).single;
      expect(stroke, hasLength(3));
      expect(stroke[1].$2, closeTo(650, 1));
      expect(stroke.last.$2, closeTo(690, 1));
      editing.finishInk();
      await settle(tester);
    });
  }

  testWidgets('stylus pressure follows the freehand prefix and snapped tail',
      (tester) async {
    final editing = await pumpEditor(tester);
    editing.tool = PdfEditTool.ink;
    await tester.pump();
    const pointer = 71;
    var position = view(100, 700);
    tester.binding.handlePointerEvent(PointerDownEvent(
      pointer: pointer,
      kind: PointerDeviceKind.stylus,
      position: position,
      pressure: 0.2,
      pressureMin: 0,
      pressureMax: 1,
    ));
    void move(double x, double y, double pressure) {
      final next = view(x, y);
      tester.binding.handlePointerEvent(PointerMoveEvent(
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: next,
        delta: next - position,
        pressure: pressure,
        pressureMin: 0,
        pressureMax: 1,
      ));
      position = next;
    }

    move(130, 675, 0.4);
    move(160, 700, 0.6);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    move(200, 690, 0.8);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    move(250, 680, 1.0);
    tester.binding.handlePointerEvent(PointerUpEvent(
      pointer: pointer,
      kind: PointerDeviceKind.stylus,
      position: position,
    ));
    expect(editing.strokePressuresOn(0), [
      [0.2, 0.4, 0.6],
      [0.6, 1.0]
    ]);
    expect(editing.strokesOn(0).last.last.$2, closeTo(700, 1));
    editing.finishInk();
    expect(editing.document.page(0).annotations.single.inkList, hasLength(2));
    await settle(tester);
  });

  testWidgets('constrained ink stays straight in preview, buffer and saved PDF',
      (tester) async {
    final boundary = GlobalKey();
    final editing = await pumpEditor(tester, boundary: boundary);
    editing
      ..color = const Color(0xFFFF0000)
      ..tool = PdfEditTool.ink;
    editing.preferences.strokeWidth = 2;
    await tester.pump();

    final gesture = await tester.startGesture(view(100, 700),
        kind: PointerDeviceKind.mouse);
    await gesture.moveTo(view(130, 650));
    await gesture.moveTo(view(160, 700));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await gesture.moveTo(view(260, 690));
    await tester.pump();

    Future<void> expectStraight(ui.Image image, String phase) async {
      try {
        final pixels = (await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
        bool redAt(Offset point) {
          final i = (point.dy.round() * image.width + point.dx.round()) * 4;
          return pixels.getUint8(i) > 180 && pixels.getUint8(i + 1) < 140;
        }

        // Probe the rendered segment, including its bend-prone start.
        for (var x = 180.0; x <= 245; x += 5) {
          expect(redAt(view(x, 700)), isTrue,
              reason: '$phase: straight ink must pass through ($x, 700)');
          for (final y in [695.0, 705.0, 710.0]) {
            expect(redAt(view(x, y)), isFalse,
                reason: '$phase: smoothing must not bend the tail');
          }
        }
        expect(redAt(view(275, 700)), isFalse,
            reason: '$phase: prediction must not extend a constrained tail');
      } finally {
        image.dispose();
      }
    }

    Future<ui.Image> capture() async => (await tester.runAsync(() => tester
        .renderObject<RenderRepaintBoundary>(find.byKey(boundary))
        .toImage()))!;

    await expectStraight(await capture(), 'active preview');
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await expectStraight(await capture(), 'buffered preview');
    editing.finishInk();
    final reopened = PdfDocument.open(editing.bytes);
    final saved = (await tester.runAsync(() =>
        PdfPageRenderer.renderImage(reopened.page(0), pixelRatio: scale)))!;
    await expectStraight(saved, 'saved PDF');
    expect(reopened.page(0).annotations, hasLength(1));
    editing.undo();
    expect(editing.document.page(0).annotations, isEmpty,
        reason: 'one undo removes both the freehand prefix and straight tail');
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
