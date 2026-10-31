import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The "Page N" label a page draws, or '' for a blank page.
String labelOf(PdfDocument doc, int index) {
  final content = String.fromCharCodes(doc.page(index).contentBytes());
  return RegExp(r'\((Page \d+)\)').firstMatch(content)?.group(1) ?? '';
}

List<String> labelsOf(PdfDocument doc) =>
    [for (var i = 0; i < doc.pageCount; i++) labelOf(doc, i)];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(PdfEditingController, PdfViewerController)> pumpStrip(
    WidgetTester tester, {
    int pages = 5,
    PdfPageLayout layout = const PdfPageLayout.facing(),
    PdfPanelDock dock = PdfPanelDock.left,
    double width = 240,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final editing = PdfEditingController(buildMultiPagePdf(pages));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    final strip = PdfThumbnailSidebar(
      controller: editing,
      viewerController: viewer,
      pageLayout: layout,
      dock: dock,
      width: width,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: dock == PdfPanelDock.bottom
            ? Column(children: [
                const Expanded(child: SizedBox()),
                SizedBox(height: 220, child: strip),
              ])
            : Row(children: [
                strip,
                const Expanded(child: SizedBox()),
              ]),
      ),
    ));
    await tester.pump();
    return (editing, viewer);
  }

  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 2));

  Rect cell(WidgetTester tester, int page) =>
      tester.getRect(find.byKey(ValueKey('pdf-thumbnail-spread-cell-$page')));

  testWidgets('a side strip pairs pages into spreads', (tester) async {
    await pumpStrip(tester);
    expect(find.byKey(const ValueKey('pdf-thumbnail-spread-list')),
        findsOneWidget);
    // pages 1-2 share a row, page 1 on the left
    expect(cell(tester, 0).top, cell(tester, 1).top);
    expect(cell(tester, 0).right, moreOrLessEquals(cell(tester, 1).left));
    // pages 3-4 form the next row
    expect(cell(tester, 2).top, greaterThan(cell(tester, 0).bottom - 1));
    expect(cell(tester, 2).left, cell(tester, 0).left);
    // the unpaired last page keeps the left side
    expect(cell(tester, 4).left, cell(tester, 0).left);
    await drain(tester);
  });

  testWidgets('a cover page stands alone on the right', (tester) async {
    await pumpStrip(tester,
        pages: 4, layout: const PdfPageLayout.facing(coverPage: true));
    // the cover sits where a right page does
    expect(cell(tester, 0).left, cell(tester, 2).left);
    // pages 2-3 pair below it
    expect(cell(tester, 1).top, cell(tester, 2).top);
    expect(cell(tester, 1).right, moreOrLessEquals(cell(tester, 2).left));
    expect(cell(tester, 1).top, greaterThan(cell(tester, 0).top));
    await drain(tester);
  });

  testWidgets('a continuous layout keeps the single-column strip',
      (tester) async {
    await pumpStrip(tester, layout: const PdfPageLayout.verticalContinuous());
    expect(
        find.byKey(const ValueKey('pdf-thumbnail-spread-list')), findsNothing);
    expect(find.byKey(const ValueKey('pdf-thumbnail-list')), findsOneWidget);
    await drain(tester);
  });

  testWidgets('tapping a spread tile jumps the viewer to that page',
      (tester) async {
    final (editing, viewer) = await pumpStrip(tester);
    await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-spread-cell-3')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(editing.isPageSelected(3), isTrue);
    await drain(tester);
  });

  testWidgets('dragging a page onto a tile half reorders by page',
      (tester) async {
    final (editing, _) = await pumpStrip(tester, pages: 4);
    expect(
        labelsOf(editing.document), ['Page 1', 'Page 2', 'Page 3', 'Page 4']);
    // pick up page 1 (touch: long press), drop on the right half of page 4
    final from = cell(tester, 0).center;
    final target = cell(tester, 3);
    final to = target.center + Offset(target.width / 4, 0);
    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(to);
    await tester.pump();
    expect(find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-3-right')),
        findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(
        labelsOf(editing.document), ['Page 2', 'Page 3', 'Page 4', 'Page 1']);
    await drain(tester);
  });

  testWidgets('dropping on the spine swaps the pages of a spread',
      (tester) async {
    final (editing, _) = await pumpStrip(tester, pages: 4);
    // page 4 dropped on the left half of page 3: the gap between 2 and 3
    final from = cell(tester, 3).center;
    final target = cell(tester, 2);
    final to = target.center - Offset(target.width / 4, 0);
    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(to);
    await tester.pump();
    expect(find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-2-left')),
        findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(
        labelsOf(editing.document), ['Page 1', 'Page 2', 'Page 4', 'Page 3']);
    await drain(tester);
  });

  testWidgets('a bottom strip groups spreads with a wider gap', (tester) async {
    await pumpStrip(tester, pages: 4, dock: PdfPanelDock.bottom);
    Rect chip(int page) =>
        tester.getRect(find.byKey(ValueKey('pdf-thumbnail-tile-chip-$page')));
    final within = chip(1).left - chip(0).right;
    final between = chip(2).left - chip(1).right;
    expect(between, moreOrLessEquals(within + 12, epsilon: 0.5));
    await drain(tester);
  });

  testWidgets('a reorder drag near the bottom edge scrolls the strip',
      (tester) async {
    await pumpStrip(tester, pages: 30);
    final list = find.byKey(const ValueKey('pdf-thumbnail-spread-list'));
    final scrollable =
        find.descendant(of: list, matching: find.byType(Scrollable)).first;
    double offset() =>
        tester.state<ScrollableState>(scrollable).position.pixels;
    expect(offset(), 0);
    final gesture = await tester.startGesture(cell(tester, 0).center);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    // hold the page just inside the strip's bottom edge
    final bottom = tester.getRect(list).bottomCenter - const Offset(0, 4);
    await gesture.moveTo(bottom - const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(bottom);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(offset(), greaterThan(0));
    await gesture.up();
    await drain(tester);
  });
}
