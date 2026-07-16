// Line-type (dash) styles, polygon fill, cross-page annotation moves, the
// select-tool toggle-off, and the stroke/opacity drag readout.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('line style (dash) on the controller', () {
    test('a non-solid line style stores a /BS /D dash array on new shapes', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..lineStyle = PdfLineStyle.dashed;
      addTearDown(editing.dispose);
      editing.addRectangle(0, const PdfRect(100, 100, 200, 200));
      final square = editing.document.page(0).annotations.single;
      expect(square.borderDash, isNotNull);
      expect(PdfLineStyle.ofDashArray(square.borderDash), PdfLineStyle.dashed);
    });

    test('solid leaves no dash array', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.addEllipse(0, const PdfRect(100, 100, 200, 200));
      expect(editing.document.page(0).annotations.single.borderDash, isNull);
    });

    test('restyleSelected changes the line style of a selected shape', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing
        ..addRectangle(0, const PdfRect(100, 100, 300, 200))
        ..selectAnnotation(0, 0);
      expect(editing.selectedLineStyle, PdfLineStyle.solid);
      expect(editing.canSetLineStyleSelected, isTrue);

      expect(editing.restyleSelected(lineStyle: PdfLineStyle.dotted), isTrue);
      final square = editing.document.page(0).annotations.single;
      expect(square.borderDash, isNotNull);
      expect(editing.selectedLineStyle, PdfLineStyle.dotted);
    });

    test('the line style classifier round-trips its own arrays', () {
      for (final style in PdfLineStyle.values) {
        expect(PdfLineStyle.ofDashArray(style.dashArray(3)), style);
      }
    });

    test('the pattern scale sizes the dash array apart from the pen width', () {
      // Same style, same pen width: a bigger scale means bigger dashes.
      final small = PdfLineStyle.dashed.dashArray(1, scale: 1)!;
      final big = PdfLineStyle.dashed.dashArray(1, scale: 2)!;
      expect(big.first, greaterThan(small.first));
      // Changing only the pen width leaves the pattern alone.
      final thin = PdfLineStyle.dashed.dashArray(1, scale: 1.5)!;
      final thick = PdfLineStyle.dashed.dashArray(1, scale: 1.5)!;
      expect(thick, thin);
    });

    test('the pattern scale drives new shapes and is independent of stroke',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..lineStyle = PdfLineStyle.dashed
        ..strokeWidth = 1
        ..lineScale = 1;
      addTearDown(editing.dispose);
      editing.addRectangle(0, const PdfRect(100, 100, 300, 200));
      final narrow =
          editing.document.page(0).annotations.single.borderDash!.first;

      editing
        ..lineScale = 3
        ..addRectangle(0, const PdfRect(100, 300, 300, 400));
      final wide = editing.document.page(0).annotations.last.borderDash!.first;
      expect(wide, greaterThan(narrow));
    });
  });

  group('pattern scale on clouds', () {
    test('a cloud drawn at a bigger scale stores it on /BE /I', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..lineScale = 2.5;
      addTearDown(editing.dispose);
      editing.addCloudPolygon(0, const PdfRect(100, 100, 300, 200));
      final cloud = editing.document.page(0).annotations.single;
      expect(cloud.hasCloudyBorder, isTrue);
      expect(cloud.cloudBorderScale, closeTo(2.5, 1e-9));
    });

    test('restyleSelected(scale:) rescales a selected cloud', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing
        ..addCloudPolygon(0, const PdfRect(100, 100, 300, 200))
        ..selectAnnotation(0, 0);
      expect(editing.selectedLineScale, closeTo(1, 1e-9));
      expect(editing.restyleSelected(scale: 3), isTrue);
      expect(editing.document.page(0).annotations.single.cloudBorderScale,
          closeTo(3, 1e-9));
      expect(editing.selectedLineScale, closeTo(3, 1e-9));
    });
  });

  group('polygon fill', () {
    test('a polygon drawn with a shape fill colour stores /IC', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..shapeFillColor = const Color(0xFF80C0FF);
      addTearDown(editing.dispose);
      editing.addPolygon(0, const [(100, 100), (200, 180), (160, 100)]);
      expect(
          editing.document.page(0).annotations.single.interiorColor, 0x80C0FF);
    });

    test('canFillSelected and restyleSelected fill cover polygons', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing
        ..addPolygon(0, const [(100, 100), (200, 180), (160, 100)])
        ..selectAnnotation(0, 0);
      expect(editing.canFillSelected, isTrue);
      expect(editing.restyleSelected(fill: (const Color(0xFF112233),)), isTrue);
      expect(
          editing.document.page(0).annotations.single.interiorColor, 0x112233);
    });
  });

  group('cross-page annotation move', () {
    test('moveSelectedToPage re-homes the annotation onto the target page', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      editing
        ..addRectangle(0, const PdfRect(100, 600, 200, 700))
        ..selectAnnotation(0, 0);

      expect(editing.moveSelectedToPage(1, 30, -40), isTrue);
      expect(editing.document.page(0).annotations, isEmpty);
      final moved = editing.document.page(1).annotations.single;
      expect(moved.subtype, 'Square');
      expect(moved.rect, const PdfRect(130, 560, 230, 660));
      // the re-homed annotation is selected on the new page
      expect(editing.selectedAnnotationSlots, [(1, 0)]);

      // one revision: a single undo brings it back to page 0
      editing.undo();
      expect(editing.document.page(0).annotations, hasLength(1));
      expect(editing.document.page(1).annotations, isEmpty);
    });

    test('a same-page target falls back to a plain move', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      editing
        ..addRectangle(0, const PdfRect(100, 600, 200, 700))
        ..selectAnnotation(0, 0);
      expect(editing.moveSelectedToPage(0, 10, 10), isTrue);
      expect(editing.document.page(0).annotations.single.rect,
          const PdfRect(110, 610, 210, 710));
    });
  });

  group('select tool toggle-off', () {
    testWidgets('tapping the armed Select chip disarms to reader mode',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar:
              PdfEditingToolbar(controller: editing, viewerController: viewer),
        ),
      ));

      editing.tool = PdfEditTool.select;
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-group-select')));
      await tester.pump();
      expect(editing.tool, isNull);

      // tapping it again re-arms Select
      await tester.tap(find.byKey(const ValueKey('pdf-group-select')));
      await tester.pump();
      expect(editing.tool, PdfEditTool.select);
    });
  });

  group('drag readout', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    testWidgets('a shape drag shows the stroke width and opacity',
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
        ..tool = PdfEditTool.rectangle
        ..strokeWidth = 4
        ..opacity = 0.5;
      await tester.pump();

      final gesture = await tester.startGesture(view(150, 600));
      await gesture.moveTo(view(300, 450));
      await tester.pump();

      expect(find.byKey(const ValueKey('pdf-style-readout')), findsOneWidget);
      expect(find.text('4 pt · 50%'), findsOneWidget);

      await gesture.up();
      // drain the viewer's double-tap recognizer timer (touch gesture)
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the drag readout stays screen-sized and offset under zoom',
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
        ..tool = PdfEditTool.rectangle
        ..strokeWidth = 4
        ..opacity = 0.5;
      await tester.pump();

      Future<Rect> dragAndRead(Offset start, Offset end) async {
        final gesture =
            await tester.startGesture(start, kind: PointerDeviceKind.mouse);
        await gesture.moveTo(end);
        await tester.pump();
        final rect =
            tester.getRect(find.byKey(const ValueKey('pdf-style-readout')));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 400));
        return rect;
      }

      const start = Offset(180, 220);
      const end = Offset(300, 340);
      final normal = await dragAndRead(start, end);
      expect(normal.left - end.dx, closeTo(16, 0.5));
      expect(normal.top - end.dy, closeTo(-36, 0.5));

      // Public zoom is px/pt; twice fit-width means a 2× transform zoom.
      viewer.setZoom(2 * scale);
      await tester.pump();
      final zoomed = await dragAndRead(start, end);

      expect(zoomed.size.width, closeTo(normal.size.width, 0.5));
      expect(zoomed.size.height, closeTo(normal.size.height, 0.5));
      expect(zoomed.left - end.dx, closeTo(16, 0.5));
      expect(zoomed.top - end.dy, closeTo(-36, 0.5));
    });
  });
}
