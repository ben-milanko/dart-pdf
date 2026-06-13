import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_overlay.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// A two-page PDF whose pages are [height] pt tall (612 wide) — short
/// enough that both pages sit inside an 800×600 viewport at fit-width, so
/// a move drag can cross the page boundary on screen.
Uint8List buildShortTwoPagePdf(int height) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
  ];
  for (var i = 0; i < 2; i++) {
    objects.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 $height] '
        '/Contents ${4 + i * 2} 0 R >>');
    objects.add('<< /Length 0 >>\nstream\n\nendstream');
  }
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

/// The editing overlay's preview painter, read through a dynamic cast
/// (the painter class is private to the library).
dynamic overlayPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(find
        .descendant(
            of: find.byType(EditingPageOverlay),
            matching: find.byType(CustomPaint))
        .first)
    .painter;

(int r, int g, int b, int a) pixelAt(ByteData data, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return (
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
    data.getUint8(i + 3),
  );
}

void main() {
  test(
      'renderAnnotationPicture draws just the appearance, transparent '
      'elsewhere', () async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..color = const Color(0xFFFF0000)
      ..addRectangle(0, const PdfRect(100, 650, 250, 750));
    final page = editing.document.page(0);
    final annotation = page.annotations.single;

    final picture =
        await PdfPageRenderer.renderAnnotationPicture(page, annotation);
    expect(picture, isNotNull);
    final image = await PdfPageRenderer.rasterize(
        picture!, PdfPageRenderer.pageSize(page), 1);
    final data = (await image.toByteData())!;

    // page raster space is y-down: page (100, 700) → raster (100, 92).
    // the square's left border is stroked in the annotation color
    final (r, g, b, a) = pixelAt(data, image.width, 100, 92);
    expect(a, greaterThan(200));
    expect(r, greaterThan(200));
    expect(g, lessThan(80));
    expect(b, lessThan(80));

    // outside the annotation the picture stays fully transparent
    final (_, _, _, a2) = pixelAt(data, image.width, 400, 92);
    expect(a2, 0);
    image.dispose();
    picture.dispose();
  });

  test('paintAnnotationDragPreview maps the picture onto the target rect',
      () async {
    // a "page-space" appearance: a solid red square at points 10..20
    final appearance = ui.PictureRecorder();
    Canvas(appearance).drawRect(const Rect.fromLTRB(10, 10, 20, 20),
        Paint()..color = const Color(0xFFFF0000));
    final picture = appearance.endRecording();

    // at 2 px/pt the square rests at view rect 20..40; the drag both
    // moves it and doubles its size
    const from = Rect.fromLTRB(20, 20, 40, 40);
    const to = Rect.fromLTRB(120, 60, 160, 100);
    final recorder = ui.PictureRecorder();
    paintAnnotationDragPreview(Canvas(recorder),
        picture: picture, from: from, to: to, scale: 2);
    final image = await recorder.endRecording().toImage(200, 150);
    final data = (await image.toByteData())!;

    // the center of `to` carries the square at ~75% opacity
    // (premultiplied, so the red channel rides at ~alpha)
    final (r, _, _, a) = pixelAt(data, image.width, 140, 80);
    expect(a, closeTo(191, 25));
    expect(r, closeTo(191, 25));

    // the resting position is untouched — the preview moved, the
    // original spot stays for the page below to show through
    final (_, _, _, a2) = pixelAt(data, image.width, 30, 30);
    expect(a2, 0);
    image.dispose();
    picture.dispose();
  });

  group('live preview in the viewer', () {
    // 800px viewport over a 612pt page
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    testWidgets('a move drag shows the annotation at the dragged position',
        (tester) async {
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

      editing
        ..color = const Color(0xFFFF0000)
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..tool = PdfEditTool.select;
      await tester.pump();
      await tester.tapAt(view(175, 700));
      // double-tap hold, selection, and the ghost render all settle here
      await tester.pumpAndSettle(const Duration(milliseconds: 350));
      expect(editing.selectedAnnotation, isNotNull);

      // drag the annotation toward the lower right and hold mid-drag
      final gesture = await tester.startGesture(view(175, 700));
      await gesture.moveTo(view(255, 550));
      await gesture.moveTo(view(335, 400));
      await tester.pump();

      final image = await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        return render.toImage();
      });
      final data = (await tester.runAsync(image!.toByteData))!;

      // the square's red left border previews at the dragged position:
      // original edge midpoint (100, 700) shifted by the drag delta
      final delta = view(335, 400) - view(175, 700);
      final edge = view(100, 700) + delta;
      var sawRed = false;
      for (var dx = -2; dx <= 2 && !sawRed; dx++) {
        final (r, g, b, _) =
            pixelAt(data, image.width, edge.dx.round() + dx, edge.dy.round());
        sawRed = r > 180 && g < 140 && b < 140;
      }
      expect(sawRed, isTrue,
          reason: 'the dragged annotation should preview its appearance');
      image.dispose();

      // releasing commits the move where the preview showed it
      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 350));
      final rect = editing.selectedAnnotation!.rect;
      expect(rect.left, closeTo(260, 2));
      expect(rect.top, closeTo(450, 2));
    });
  });

  group('move ghost floats above the page', () {
    testWidgets(
        'a move dragged past the page edge reports a floating preview to '
        'the viewer', (tester) async {
      // A move dragged onto the page below would be clipped behind it if
      // only the per-page overlay painted the ghost (sibling list items
      // paint over its overflow). The overlay keeps its own ghost AND,
      // once the drag leaves the page, hands a copy up to the viewer to
      // paint above every page.
      PdfMoveDragPreview? reported;
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..color = const Color(0xFFFF0000)
        ..addRectangle(0, const PdfRect(100, 550, 300, 650))
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0);
      addTearDown(editing.dispose);
      // a bare overlay over a 306×396 view of the 612×792 page: 0.5 px/pt
      final geometry = PdfPageGeometry(
        cropBox: editing.document.page(0).cropBox,
        rotation: 0,
        viewSize: const Size(306, 396),
      );
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 306,
            height: 396,
            child: EditingPageOverlay(
              controller: editing,
              pageIndex: 0,
              geometry: geometry,
              textPrompt: showPdfTextPrompt,
              onMoveDragPreview: (preview) => reported = preview,
            ),
          ),
        ),
      ));
      // the move ghost renders here
      await tester.pumpAndSettle(const Duration(milliseconds: 350));

      final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
      // selection (100,550)-(300,650) → view (50,71)-(150,121); grab its
      // center and drag it well down past the page's bottom edge
      const grab = Offset(100, 96);
      const target = Offset(160, 420);
      final gesture =
          await tester.startGesture(origin + grab, kind: PointerDeviceKind.mouse);
      await gesture.moveTo(origin + target);
      await tester.pump();

      expect(reported, isNotNull,
          reason: 'a move drag should float its ghost to the viewer');
      expect(reported!.pageIndex, 0);
      // the resting view rect (50,71,150,121), shifted by the drag delta
      final delta = target - grab;
      expect(reported!.from.left, closeTo(50, 0.5));
      expect(reported!.from.top, closeTo(71, 0.5));
      expect(reported!.to.left, closeTo(50 + delta.dx, 0.5));
      expect(reported!.to.top, closeTo(71 + delta.dy, 0.5));
      // the overlay still paints its own ghost (the floating copy is an
      // addition for the overflow, not a replacement — so an in-page drag
      // never goes blank even if the floating layer can't paint)
      expect(overlayPainter(tester).ghost, isNotNull);

      // releasing clears the floating preview (the commit's afterimage or
      // the new raster takes over)
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(reported, isNull);
    });

    testWidgets(
        'a move dragged onto the page below paints the ghost over that page',
        (tester) async {
      // 300pt pages at fit-width (800/612 px/pt) are ~392px tall, so page 1
      // and the top of page 2 both fit in the 800×600 viewport. Dragging an
      // annotation from page 1 into page 2's area must still show the ghost
      // — before the fix the per-page overlay clipped it behind page 2.
      const pageHeight = 300;
      const scale = 800 / 612;
      // page-0 view coordinates (y up in page space)
      Offset view(double x, double y) =>
          Offset(x * scale, (pageHeight - y) * scale);

      final editing = PdfEditingController(buildShortTwoPagePdf(pageHeight));
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

      // a red rectangle near the bottom of page 1 (page y 30..70)
      editing
        ..color = const Color(0xFFFF0000)
        ..strokeWidth = 3
        ..addRectangle(0, const PdfRect(250, 30, 400, 70))
        ..tool = PdfEditTool.select;
      await tester.pump();
      final grab = view(325, 50); // the rectangle's centre, ~(425, 327)
      await tester.tapAt(grab);
      await tester.pumpAndSettle(const Duration(milliseconds: 350));
      expect(editing.selectedAnnotation, isNotNull);

      // drag it straight down into page 2's on-screen region and hold
      final target = grab + const Offset(20, 185); // ~viewport y 512
      final gesture = await tester.startGesture(grab);
      await gesture.moveTo(grab + const Offset(10, 90));
      await gesture.moveTo(target);
      await tester.pump();

      final image = await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        return render.toImage();
      });
      final data = (await tester.runAsync(image!.toByteData))!;

      // page 2 starts at viewport y ≈ 404; the dragged ghost's red border
      // must appear in that band (it sat behind page 2 before the fix)
      final delta = target - grab;
      final searchCenter = view(250, 50) + delta; // left border, shifted
      var sawRed = false;
      for (var dy = -30; dy <= 30 && !sawRed; dy++) {
        for (var dx = -6; dx <= 6 && !sawRed; dx++) {
          final x = searchCenter.dx.round() + dx;
          final y = searchCenter.dy.round() + dy;
          if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
            continue;
          }
          final (r, g, b, _) = pixelAt(data, image.width, x, y);
          sawRed = r > 180 && g < 140 && b < 140;
        }
      }
      expect(searchCenter.dy, greaterThan(404),
          reason: 'the sample band should be over page 2');
      expect(sawRed, isTrue,
          reason: 'the ghost must paint over the page below, not behind it');
      image.dispose();

      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 350));
    });
  });
}
