import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

(int r, int g, int b, int a) pixelAt(ByteData data, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return (
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
    data.getUint8(i + 3),
  );
}

/// Whether any pixel in the ±[radius] patch around ([x], [y]) satisfies
/// [test] — antialiased 1–3 px strokes don't land on exact coordinates.
bool patchHas(ByteData data, int width, int height, double x, double y,
    int radius, bool Function(int r, int g, int b, int a) test) {
  for (var dy = -radius; dy <= radius; dy++) {
    for (var dx = -radius; dx <= radius; dx++) {
      final px = x.round() + dx, py = y.round() + dy;
      if (px < 0 || py < 0 || px >= width || py >= height) continue;
      final (r, g, b, a) = pixelAt(data, width, px, py);
      if (test(r, g, b, a)) return true;
    }
  }
  return false;
}

bool strongBlue(int r, int g, int b, int a) => a > 150 && b > 150 && r < 120;
bool strongRed(int r, int g, int b, int a) => a > 150 && r > 180 && g < 120;

Future<ByteData> capture(WidgetTester tester, GlobalKey boundary) async {
  final image = await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return render.toImage();
  });
  return (await tester.runAsync(image!.toByteData))!;
}

void main() {
  setUp(() {
    // the mock store is process-global; stale prefs leak across tests
    SharedPreferences.setMockInitialValues({});
  });

  group('appearanceQuad', () {
    test('an unrotated appearance maps onto the rect corners', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 650, 250, 750));
      final quad = editing.document.page(0).annotations.single.appearanceQuad!;
      expect(quad[0].$1, closeTo(100, 1e-6));
      expect(quad[0].$2, closeTo(650, 1e-6));
      expect(quad[1].$1, closeTo(250, 1e-6));
      expect(quad[1].$2, closeTo(650, 1e-6));
      expect(quad[2].$1, closeTo(250, 1e-6));
      expect(quad[2].$2, closeTo(750, 1e-6));
      expect(quad[3].$1, closeTo(100, 1e-6));
      expect(quad[3].$2, closeTo(750, 1e-6));
    });

    test('rotation carries into the quad, and 45+45 lands exactly at 90', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..selectAnnotation(0, 0)
        ..rotateSelected(45)
        ..rotateSelected(45);
      // 90° CCW about (175, 700): ll (100, 650) → (225, 625),
      // lr (250, 650) → (225, 775)
      final quad = editing.document.page(0).annotations.single.appearanceQuad!;
      expect(quad[0].$1, closeTo(225, 1e-6));
      expect(quad[0].$2, closeTo(625, 1e-6));
      expect(quad[1].$1, closeTo(225, 1e-6));
      expect(quad[1].$2, closeTo(775, 1e-6));
      expect(quad[3].$1, closeTo(125, 1e-6));
      expect(quad[3].$2, closeTo(625, 1e-6));
    });
  });

  group('ink auto-commit', () {
    testWidgets('strokes commit on their own after the delay', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.addInkStroke(0, [(100, 500), (150, 520), (200, 500)]);
      expect(editing.hasPendingInk, isTrue);
      expect(editing.document.page(0).annotations, isEmpty);

      await tester.pump(const Duration(milliseconds: 900));
      expect(editing.hasPendingInk, isFalse);
      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(1));
      expect(annotations.single.subtype, 'Ink');
      // the afterimage source is live for the committing revision
      expect(editing.committedInkOn(0), isNotNull);
      expect(editing.committedInkOn(0)!.strokes, hasLength(1));
    });

    testWidgets('strokes within the window aggregate into one annotation',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.addInkStroke(0, [(100, 500), (150, 520)]);
      await tester.pump(const Duration(milliseconds: 500));
      expect(editing.document.page(0).annotations, isEmpty); // re-armed
      editing.addInkStroke(0, [(120, 480), (140, 485)]);
      await tester.pump(const Duration(milliseconds: 900));

      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(1));
      final ink = editing.document.cos
          .resolve(annotations.single.dict['InkList']) as CosArray;
      expect(ink.length, 2);
      expect(editing.canUndo, isTrue);
      editing.undo();
      expect(editing.document.page(0).annotations, isEmpty);
    });

    testWidgets('beginInkStroke holds the timer while drawing', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.addInkStroke(0, [(100, 500), (150, 520)]);
      await tester.pump(const Duration(milliseconds: 700));
      editing.beginInkStroke(); // pen down again just in time
      await tester.pump(const Duration(milliseconds: 700));
      expect(editing.hasPendingInk, isTrue); // no commit mid-stroke
      editing.addInkStroke(0, [(150, 520), (200, 500)]);
      await tester.pump(const Duration(milliseconds: 900));
      expect(editing.hasPendingInk, isFalse);
      expect(editing.document.page(0).annotations, hasLength(1));
    });

    testWidgets('manual mode (null delay) keeps the buffer', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..inkCommitDelay = null;
      addTearDown(editing.dispose);
      editing.addInkStroke(0, [(100, 500), (150, 520)]);
      await tester.pump(const Duration(seconds: 2));
      expect(editing.hasPendingInk, isTrue);
      expect(editing.document.page(0).annotations, isEmpty);
      editing.finishInk();
      expect(editing.document.page(0).annotations, hasLength(1));
    });

    testWidgets('toolbar confirm buttons appear only in manual mode',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body:
              PdfEditingToolbar(controller: editing, viewerController: viewer),
        ),
      ));
      // the confirm/discard buttons live in the Draw group's strip
      editing.tool = PdfEditTool.ink;
      editing.addInkStroke(0, [(100, 500), (150, 520)]);
      await tester.pump();
      expect(find.byTooltip('Add ink annotation'), findsNothing);
      editing.discardInk();
      await tester.pump();

      editing.inkCommitDelay = null;
      editing.addInkStroke(0, [(100, 500), (150, 520)]);
      await tester.pump();
      expect(find.byTooltip('Add ink annotation'), findsOneWidget);
      expect(find.byTooltip('Discard drawing'), findsOneWidget);
      editing.discardInk();
    });
  });

  group('in the viewer', () {
    // 800px viewport over a 612pt page
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<(PdfEditingController, GlobalKey)> pumpViewer(
        WidgetTester tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      final boundary = GlobalKey();
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
      return (editing, boundary);
    }

    testWidgets('the selection chrome hugs a rotated annotation',
        (tester) async {
      final (editing, boundary) = await pumpViewer(tester);
      editing
        ..color = const Color(0xFFFF0000)
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..selectAnnotation(0, 0)
        ..rotateSelected(45);
      await tester.pumpAndSettle(const Duration(milliseconds: 350));

      final data = await capture(tester, boundary);
      // chrome center (175, 700) in view space
      final c = view(175, 700);
      // the rotated box's top-edge midpoint: base half-height 65.36px
      // (+2 inflate), swung 45° counterclockwise on screen
      const half = 67.36 * 0.70711;
      expect(patchHas(data, 800, 600, c.dx - half, c.dy - half, 4, strongBlue),
          isTrue,
          reason: 'the chrome stroke should pass the rotated top edge');
      // the axis-aligned bounds box (the old chrome) had its top edge
      // ~117px above center — nothing should be drawn there now
      expect(
          patchHas(data, 800, 600, c.dx, c.dy - 117.5, 3, strongBlue), isFalse,
          reason: 'no chrome along the axis-aligned bounds');
    });

    testWidgets('the rotate knob rides the rotation', (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..selectAnnotation(0, 0)
        ..rotateSelected(90);
      await tester.pumpAndSettle(const Duration(milliseconds: 350));
      // resting at 90° the knob sits left of center: half-height 65.36px
      // plus the 22px float, swung from "above" to "beside"
      final c = view(175, 700);
      final knob = c - const Offset(65.36 + 22, 0);
      final gesture = await tester.startGesture(knob);
      // sweep from pointing-left to pointing-down: another quarter turn
      await gesture.moveTo(c + const Offset(-80, 80));
      await gesture.moveTo(c + const Offset(0, 110));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 350));

      // 90 + 90 = 180° in page space: matrix a = cos(180°) = -1
      final annotation = editing.selectedAnnotation!;
      final matrix = editing.document.cos
              .resolve(annotation.normalAppearance!.dictionary['Matrix'])
          as CosArray;
      final a = editing.document.cos.resolve(matrix[0]);
      expect((a as CosReal).value, closeTo(-1, 1e-9));
    });

    testWidgets('a moved annotation stays visible before the re-render',
        (tester) async {
      final (editing, boundary) = await pumpViewer(tester);
      editing
        ..color = const Color(0xFFFF0000)
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..tool = PdfEditTool.select;
      await tester.pump();
      await tester.tapAt(view(175, 700));
      // selection and the drag-preview ghost settle here
      await tester.pumpAndSettle(const Duration(milliseconds: 350));
      expect(editing.selectedAnnotation, isNotNull);

      final gesture = await tester.startGesture(view(175, 700));
      await gesture.moveTo(view(255, 550));
      await gesture.moveTo(view(335, 400));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // the move committed, but the new revision's raster can't land in
      // a widget test — the afterimage must keep the square visible at
      // its new place (its red left border, shifted by the drag delta)
      expect(editing.document.page(0).annotations.single.rect.left,
          closeTo(260, 1));
      // sample the square's left border off the edge midpoint — the
      // white resize-handle knob sits exactly there
      final delta = view(335, 400) - view(175, 700);
      final edge = view(100, 700) + delta - const Offset(0, 33);
      final data = await capture(tester, boundary);
      expect(patchHas(data, 800, 600, edge.dx, edge.dy, 4, strongRed), isTrue,
          reason: 'the moved annotation should stay painted post-commit');
      // a move no longer washes the old spot: the opaque paper wash there
      // would blank the page content under the previous location until the
      // re-render lands, then flash it back. Instead the (stale) raster is
      // left showing the square at its old place — continuous with the drag
      // and consistent with how undo/redo leave the previous raster up — so
      // its red border is still present here until the new raster lands.
      final oldEdge = view(100, 700) - const Offset(0, 33);
      expect(patchHas(data, 800, 600, oldEdge.dx, oldEdge.dy, 4, strongRed),
          isTrue,
          reason: 'the old position is left to the stale raster, not washed');
      // let the double-tap recognizer's timer expire
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('auto-committed ink stays painted before the re-render',
        (tester) async {
      final (editing, boundary) = await pumpViewer(tester);
      editing
        ..color = const Color(0xFFFF0000)
        ..tool = PdfEditTool.ink;
      await tester.pump();

      final start = view(150, 500);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(editing.hasPendingInk, isTrue);

      await tester.pump(const Duration(milliseconds: 900));
      expect(editing.hasPendingInk, isFalse);
      expect(editing.document.page(0).annotations, hasLength(1));

      // committed, raster pending: the stroke must not blink out
      final data = await capture(tester, boundary);
      expect(patchHas(data, 800, 600, start.dx + 40, start.dy, 4, strongRed),
          isTrue,
          reason: 'committed ink should stay painted until the raster lands');

      // undo: the committing revision is gone, and so is the afterimage
      // source (pixels can't prove it — the page view deliberately keeps
      // the previous raster up until the re-render lands)
      editing.undo();
      expect(editing.committedInkOn(0), isNull);
    });

    testWidgets('signature hover previews without committing, click places',
        (tester) async {
      final (editing, boundary) = await pumpViewer(tester);
      editing.signature = PdfInkSignature(
        strokes: [
          [(0, 0.5), (0.5, 0.5), (1, 0.5)]
        ],
        pressures: [null],
        color: 0xFF0000,
        aspect: 2,
      );
      editing.tool = PdfEditTool.signature;
      await tester.pump();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: view(290, 510));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(view(300, 500));
      await tester.pump();

      // the preview rides the hover — nothing committed yet
      expect(editing.document.page(0).annotations, isEmpty);
      final data = await capture(tester, boundary);
      final p = view(300, 500);
      expect(
          patchHas(data, 800, 600, p.dx, p.dy, 4,
              (r, g, b, a) => a > 80 && r > 150 && g < 160),
          isTrue,
          reason: 'the signature preview should ride the pointer');

      await tester.tapAt(view(300, 500), kind: PointerDeviceKind.mouse);
      await tester.pump();
      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'Ink');
      // centered on the tap, 160pt wide (the ink rect hugs the strokes,
      // padded by the pen width)
      expect(annotation.rect.left, closeTo(220, 4));
      expect(annotation.rect.right, closeTo(380, 4));
    });

    testWidgets('touch press-drag-release places at the release point',
        (tester) async {
      final (editing, _) = await pumpViewer(tester);
      editing.signature = PdfInkSignature(
        strokes: [
          [(0, 0.5), (1, 0.5)]
        ],
        pressures: [null],
        color: 0xFF0000,
        aspect: 2,
      );
      editing.tool = PdfEditTool.signature;
      await tester.pump();

      final gesture = await tester.startGesture(view(250, 450));
      await gesture.moveTo(view(300, 480));
      await tester.pump();
      expect(editing.document.page(0).annotations, isEmpty); // mid-drag
      await gesture.moveTo(view(350, 500));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'Ink');
      // the ink rect hugs the flat stroke: 160pt wide around the release
      // point's x, vertically centered on its y
      expect(annotation.rect.left, closeTo(350 - 80, 4));
      expect(annotation.rect.right, closeTo(350 + 80, 4));
      expect((annotation.rect.top + annotation.rect.bottom) / 2,
          closeTo(500, 0.5));
      // let the double-tap recognizer's timer expire
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
