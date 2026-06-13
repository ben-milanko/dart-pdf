import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_overlay.dart';
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

Future<ByteData> capture(WidgetTester tester, GlobalKey boundary) async {
  final image = await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return render.toImage();
  });
  return (await tester.runAsync(image!.toByteData))!;
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('constant-size chrome under zoom', () {
    /// Mounts a bare overlay over a 306×396 view of the 612×792 page
    /// (0.5 px/pt) with the viewer's transform zoom simulated by [zoom].
    Future<PdfEditingController> pumpOverlay(WidgetTester tester,
        {required double zoom}) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..color = const Color(0xFFFF0000)
        ..addRectangle(0, const PdfRect(100, 550, 300, 650))
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0);
      addTearDown(editing.dispose);
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
              zoom: zoom,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('the painter divides chrome sizes by the zoom', (tester) async {
      await pumpOverlay(tester, zoom: 2.5);
      expect(overlayPainter(tester).chromeScale, closeTo(1 / 2.5, 1e-9));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the rotate knob rides at its on-screen distance',
        (tester) async {
      final editing = await pumpOverlay(tester, zoom: 2.5);
      final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
      // selection (100,550)-(300,650) → view (50,71)-(150,121), and the
      // knob floats 22 *screen* px above the top: 22/2.5 = 8.8 local px
      final knob = origin + const Offset(100, 71 - 8.8);
      final center = origin + const Offset(100, 96);

      final gesture = await tester.startGesture(knob);
      await gesture.moveTo(center + const Offset(60, -60));
      await gesture.moveTo(center + const Offset(84, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 400));

      // a quarter turn clockwise on screen: the 200×100 rect is 100×200
      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.rect.width, closeTo(100, 1e-6));
      expect(annotation.rect.height, closeTo(200, 1e-6));
    });

    testWidgets('the unscaled knob position no longer hits while zoomed',
        (tester) async {
      final editing = await pumpOverlay(tester, zoom: 2.5);
      final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
      // where the knob would sit at zoom 1 (22 local px above the top) —
      // 13.2 px from the scaled knob, past the 12/2.5 = 4.8 px hit radius
      final stale = origin + const Offset(100, 71 - 22);
      final center = origin + const Offset(100, 96);
      final before = editing.document;

      final gesture = await tester.startGesture(stale);
      await gesture.moveTo(center + const Offset(60, -60));
      await gesture.moveTo(center + const Offset(84, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 400));

      // the drag missed the knob — nothing committed
      expect(identical(editing.document, before), isTrue);
      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.rect.width, closeTo(200, 1e-6));
    });

    testWidgets('the viewer threads its transform zoom into the overlay',
        (tester) async {
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
      editing
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0);
      await tester.pump();
      expect(overlayPainter(tester).chromeScale, 1.0);

      // pinch in: the chrome scale must follow the transform zoom
      final pinch = await tester.createGesture(
          kind: PointerDeviceKind.trackpad, pointer: 9);
      await pinch.panZoomStart(const Offset(400, 300));
      for (var i = 1; i <= 5; i++) {
        await pinch.panZoomUpdate(const Offset(400, 300), scale: 1 + 0.2 * i);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await pinch.panZoomEnd();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      final zoom = viewer.zoom;
      expect(zoom, greaterThan(1.5));
      expect(overlayPainter(tester).chromeScale, closeTo(1 / zoom, 1e-6));
    });
  });

  group('rotate knob connector', () {
    testWidgets('the line stays under the top-center resize handle',
        (tester) async {
      final boundary = GlobalKey();
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
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
        ..addRectangle(0, const PdfRect(100, 650, 250, 750))
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0);
      await tester.pump();

      const scale = 800 / 612;
      final data = await capture(tester, boundary);
      // selection view rect: top = (792-750)·scale, the chrome box sits
      // 2px outside it, the top-center handle is an 8px box on box.top
      const boxTop = (792 - 750) * scale - 2;
      const centerX = 175 * scale;

      // inside the handle box, on the line's path: must be the handle's
      // white fill, not the connector crossing it out
      final (r, g, b, a) =
          pixelAt(data, 800, centerX.round(), (boxTop - 2).round());
      expect(a, greaterThan(200));
      expect(r, greaterThan(200));
      expect(g, greaterThan(200));
      expect(b, greaterThan(200));

      // between the handle and the knob the connector still shows — scan
      // a small patch: the 1.5px line lands between pixel columns
      var lineSeen = false;
      for (var dx = -2; dx <= 2 && !lineSeen; dx++) {
        final (r2, _, b2, a2) =
            pixelAt(data, 800, centerX.round() + dx, (boxTop - 8).round());
        lineSeen = a2 > 150 && b2 > 150 && r2 < 120;
      }
      expect(lineSeen, isTrue);
    });
  });

  group('inline text editor under a relayout zoom', () {
    const editorKey = ValueKey('pdf-freetext-editor');
    const box = PdfRect(100, 600, 300, 660);

    testWidgets('an open editor rides the page when the layout zoom changes',
        (tester) async {
      // zooming below fit-width re-lays-out the page (the _layoutZoom
      // regime changes geometry.scale): an editor that cached its view
      // rect at open would drift off the page. It must track the box.
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addFreeText(0, box, 'Steady')
        ..tool = PdfEditTool.select;
      addTearDown(editing.dispose);
      expect(editing.selectAnnotation(0, 0), isTrue);

      final cropBox = editing.document.page(0).cropBox;
      PdfPageGeometry geom(double pxpt) => PdfPageGeometry(
            cropBox: cropBox,
            rotation: 0,
            viewSize: Size(cropBox.width * pxpt, cropBox.height * pxpt),
          );
      Widget tree(double pxpt) => MaterialApp(
            home: Material(
              child: Center(
                child: SizedBox(
                  width: cropBox.width * pxpt,
                  height: cropBox.height * pxpt,
                  child: EditingPageOverlay(
                    controller: editing,
                    pageIndex: 0,
                    geometry: geom(pxpt),
                    textPrompt: showPdfTextPrompt,
                    zoom: 1,
                  ),
                ),
              ),
            ),
          );

      // lay out at 0.5 px/pt and open the editor by tapping the box
      await tester.pumpWidget(tree(0.5));
      await tester.pump();
      var origin = tester.getTopLeft(find.byType(EditingPageOverlay));
      await tester.tapAt(origin + geom(0.5).toViewRect(box).center);
      await tester.pump();
      expect(find.byKey(editorKey), findsOneWidget);

      // a zoom that re-lays-out the page larger (0.5 → 0.7 px/pt): the
      // editor's top-left must follow the box's new view position, not
      // stay pinned where it opened
      await tester.pumpWidget(tree(0.7));
      await tester.pump();
      origin = tester.getTopLeft(find.byType(EditingPageOverlay));
      expect(tester.getTopLeft(find.byKey(editorKey)) - origin,
          offsetMoreOrLessEquals(geom(0.7).toViewRect(box).topLeft,
              epsilon: 0.5));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
