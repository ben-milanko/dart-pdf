import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // the mock store is process-global: start every test from defaults
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpThemedViewer(
    WidgetTester tester, {
    PdfViewerThemeData data = const PdfViewerThemeData(),
    Color? backgroundColor,
    PdfEditingController? editing,
    int pages = 5,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewerTheme(
          data: data,
          child: PdfViewer(
            initialFit: PdfViewerFit.width,
            document:
                editing?.document ?? PdfDocument.open(buildMultiPagePdf(pages)),
            backgroundColor: backgroundColor,
            editing: editing,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  group('PdfViewerTheme', () {
    testWidgets('canvasColor recolors the canvas', (tester) async {
      const canvas = Color(0xFF123456);
      await pumpThemedViewer(tester,
          data: const PdfViewerThemeData(canvasColor: canvas));
      expect(
        find.byWidgetPredicate((w) => w is ColoredBox && w.color == canvas),
        findsWidgets,
      );
    });

    testWidgets('the widget-level backgroundColor wins over the theme',
        (tester) async {
      const themed = Color(0xFF123456);
      const widgetLevel = Color(0xFF654321);
      await pumpThemedViewer(tester,
          data: const PdfViewerThemeData(canvasColor: themed),
          backgroundColor: widgetLevel);
      expect(
        find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == widgetLevel),
        findsWidgets,
      );
      expect(
        find.byWidgetPredicate((w) => w is ColoredBox && w.color == themed),
        findsNothing,
      );
    });

    testWidgets('scrollbar colors restyle the viewer thumb', (tester) async {
      const thumbColor = Color(0xFF112233);
      const outline = Color(0xFF445566);
      await pumpThemedViewer(tester,
          data: const PdfViewerThemeData(
            scrollbar: PdfScrollbarThemeData(
              thumbColor: thumbColor,
              outlineColor: outline,
            ),
          ));
      final container = tester
          .widget<Container>(find.byKey(const ValueKey('pdf-scrollbar-thumb')));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, thumbColor);
      expect((decoration.border! as Border).top.color, outline);
    });

    testWidgets('the highlight painter carries the theme', (tester) async {
      const data = PdfViewerThemeData(
        selectionColor: Color(0x40FF0000),
        searchMatchColor: Color(0x4000FF00),
        currentSearchMatchColor: Color(0x400000FF),
      );
      await pumpThemedViewer(tester, data: data, pages: 1);
      final paint = tester.widget<CustomPaint>(find.byWidgetPredicate((w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_HighlightPainter'));
      expect((paint.painter as dynamic).theme, data);
    });

    testWidgets('the editing overlay chrome carries the theme', (tester) async {
      const data = PdfViewerThemeData(
        annotationChromeColor: Color(0xFF00AA88),
        elementChromeColor: Color(0xFF8800AA),
        flashColor: Color(0xFFAA0088),
      );
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.tool = PdfEditTool.select;
      await pumpThemedViewer(tester, data: data, editing: editing);
      final paint = tester.widget<CustomPaint>(find.byWidgetPredicate((w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_EditingPreviewPainter'));
      expect((paint.painter as dynamic).theme, data);
    });
  });

  group('sidebar scrollbars', () {
    const thumbnailThumb = ValueKey('pdf-thumbnail-scrollbar-thumb');
    const annotationThumb = ValueKey('pdf-annotation-scrollbar-thumb');

    Future<PdfEditingController> pumpThumbnailStrip(WidgetTester tester,
        {int pages = 8}) async {
      final editing = PdfEditingController(buildMultiPagePdf(pages));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(controller: editing, viewerController: viewer),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets(
        'the thumbnail strip shows the viewer-style bar when it '
        'overflows', (tester) async {
      await pumpThumbnailStrip(tester);
      expect(find.byKey(thumbnailThumb), findsOneWidget);
    });

    testWidgets('the thumbnail strip hides the bar when everything fits',
        (tester) async {
      await pumpThumbnailStrip(tester, pages: 2);
      expect(find.byKey(thumbnailThumb), findsNothing);
    });

    testWidgets('dragging the thumbnail bar scrolls the strip', (tester) async {
      await pumpThumbnailStrip(tester);
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(position.pixels, 0);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(thumbnailThumb)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 150));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(position.pixels, greaterThan(0));
    });

    testWidgets('the annotation sidebar bar appears and scrolls the list',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      for (var page = 0; page < 3; page++) {
        for (var i = 0; i < 5; i++) {
          editing.addRectangle(
              page, PdfRect(100, 100.0 + 60 * i, 200, 140.0 + 60 * i));
        }
      }
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            const Expanded(child: SizedBox()),
            PdfAnnotationSidebar(controller: editing, viewerController: viewer),
          ]),
        ),
      ));
      await tester.pump();
      expect(find.byKey(annotationThumb), findsOneWidget);

      // the search field hosts its own Scrollable - scope to the list
      final position = tester
          .state<ScrollableState>(find.descendant(
              of: find.byKey(const ValueKey('pdf-annotation-list')),
              matching: find.byType(Scrollable)))
          .position;
      expect(position.pixels, 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(annotationThumb)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 150));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(position.pixels, greaterThan(0));
    });

    testWidgets('sidebar bars follow the scrollbar theme', (tester) async {
      const thumbColor = Color(0xFF221133);
      final editing = PdfEditingController(buildMultiPagePdf(8));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewerTheme(
            data: const PdfViewerThemeData(
              scrollbar: PdfScrollbarThemeData(thumbColor: thumbColor),
            ),
            child: Row(children: [
              PdfThumbnailSidebar(
                  controller: editing, viewerController: viewer),
              const Expanded(child: SizedBox()),
            ]),
          ),
        ),
      ));
      await tester.pump();
      final container = tester.widget<Container>(find.byKey(thumbnailThumb));
      expect((container.decoration! as BoxDecoration).color, thumbColor);
    });
  });
}
