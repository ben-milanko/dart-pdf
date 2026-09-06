import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
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

  group('addBlankPage', () {
    test('appends a blank page and bumps the count', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      editing.addBlankPage();
      expect(editing.document.pageCount, 3);
      expect(labelOf(editing.document, 2), '');
    });

    test('a blank page with no size given matches its neighbour', () {
      // buildVariedHeightPdf cycles heights 792, 396, 1008 (all 612 wide)
      final editing = PdfEditingController(buildVariedHeightPdf(3));
      addTearDown(editing.dispose);
      // insert after page index 1 (height 396) - the new page copies it
      editing.addBlankPage(at: 2);
      expect(editing.document.pageCount, 4);
      expect(editing.document.page(2).mediaBox, const PdfRect(0, 0, 612, 396));
    });

    test('an explicit size wins over the neighbour default', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.addBlankPage(width: 200, height: 300);
      expect(editing.document.page(1).mediaBox, const PdfRect(0, 0, 200, 300));
    });

    test('undo restores the page count', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      editing.addBlankPage();
      expect(editing.document.pageCount, 3);
      editing.undo();
      expect(editing.document.pageCount, 2);
    });
  });

  group('insertPagesFrom', () {
    test('insertPagesFromBytes merges another document at a position', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      editing.insertPagesFromBytes(buildMultiPagePdf(3), at: 1);
      expect(editing.document.pageCount, 5);
      expect(labelsOf(editing.document),
          ['Page 1', 'Page 1', 'Page 2', 'Page 3', 'Page 2']);
    });

    test('insertPagesFrom can pick a subset', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      final source = PdfDocument.open(buildMultiPagePdf(3));
      editing.insertPagesFrom(source, indices: [2]);
      expect(labelsOf(editing.document), ['Page 1', 'Page 3']);
    });
  });

  group('viewer position across page edits', () {
    Future<(PdfEditingController, PdfViewerController)> pumpViewer(
      WidgetTester tester,
    ) async {
      final editing = PdfEditingController(buildMultiPagePdf(5));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            editing: editing,
            controller: viewer,
            initialFit: PdfViewerFit.width,
            pagePreviews: false,
          ),
        ),
      ));
      await tester.pump();
      viewer.restoreViewport(
        const PdfViewport(page: 3, top: 0.18, left: 0.12, zoom: 1.5),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      return (editing, viewer);
    }

    void expectViewport(
      PdfEditingController editing,
      PdfViewerController viewer, {
      required int page,
      required String label,
    }) {
      final viewport = viewer.captureViewport();
      expect(viewport, isNotNull);
      expect(viewport!.page, page);
      expect(viewer.currentPage, page);
      expect(labelOf(editing.document, page), label);
      expect(viewport.top, closeTo(0.18, 0.02));
      expect(viewport.left, closeTo(0.12, 0.02));
      expect(viewport.zoom, closeTo(1.5, 0.02));
    }

    testWidgets('adding pages keeps the current page and zoom',
        (tester) async {
      final (editing, viewer) = await pumpViewer(tester);
      expectViewport(editing, viewer, page: 3, label: 'Page 4');

      editing.addBlankPage(at: 1);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expectViewport(editing, viewer, page: 4, label: 'Page 4');

      editing.addBlankPage();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expectViewport(editing, viewer, page: 4, label: 'Page 4');
    });

    testWidgets('deleting pages keeps the nearest surviving view',
        (tester) async {
      final (editing, viewer) = await pumpViewer(tester);
      expectViewport(editing, viewer, page: 3, label: 'Page 4');

      // A deletion before the viewport follows the same page to its new slot.
      editing.removePage(0);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expectViewport(editing, viewer, page: 2, label: 'Page 4');

      // Deleting the viewed page keeps its position and shows the page that
      // moved into that slot instead of returning to page 1.
      editing.removePage(2);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expectViewport(editing, viewer, page: 2, label: 'Page 5');

      // At the end of the document the previous page is the nearest survivor.
      editing.removePage(2);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expectViewport(editing, viewer, page: 1, label: 'Page 3');
    });

    testWidgets('reordering pages follows the viewed page by identity',
        (tester) async {
      final (editing, viewer) = await pumpViewer(tester);
      expectViewport(editing, viewer, page: 3, label: 'Page 4');

      editing.movePage(3, 0);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expectViewport(editing, viewer, page: 0, label: 'Page 4');

      editing.undo();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expectViewport(editing, viewer, page: 3, label: 'Page 4');
    });

    test('render stamps follow stable pages through reorder and undo', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      editing.addRectangle(0, const PdfRect(20, 20, 80, 80));
      final changedStamp = editing.pageRenderStamp(0);
      final cleanStamp = editing.pageRenderStamp(1);
      expect(changedStamp, greaterThan(cleanStamp));

      editing.movePage(0, 1);
      expect(editing.pageRenderStamp(1), changedStamp);
      expect(editing.pageRenderStamp(0), cleanStamp);

      editing.undo();
      expect(editing.pageRenderStamp(0), changedStamp);
      expect(editing.pageRenderStamp(1), cleanStamp);
    });
  });

  group('duplicatePages', () {
    test('copies one page right after itself', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      expect(editing.duplicatePages([1]), isTrue);
      expect(
          labelsOf(editing.document), ['Page 1', 'Page 2', 'Page 2', 'Page 3']);
    });

    test('copies several pages as one contiguous block after the last', () {
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      // pages 1 and 3 (Page 2, Page 4) copied after the higher of them
      expect(editing.duplicatePages([2, 0]), isTrue);
      expect(labelsOf(editing.document),
          ['Page 1', 'Page 2', 'Page 3', 'Page 1', 'Page 3', 'Page 4']);
    });

    test('preserves the page content (a real glyph survives the copy)', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      editing.duplicatePages([0]);
      expect(labelOf(editing.document, 1), 'Page 1');
    });

    test('is a no-op with nothing valid, and undo restores the count', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      expect(editing.duplicatePages(const []), isFalse);
      expect(editing.duplicatePages([5]), isFalse); // out of range
      expect(editing.document.pageCount, 2);

      editing.duplicatePages([0]);
      expect(editing.document.pageCount, 3);
      editing.undo();
      expect(editing.document.pageCount, 2);
    });
  });

  group('export', () {
    test('exportPages builds a standalone PDF and leaves this one alone', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      final out = PdfDocument.open(editing.exportPages([2, 0]));
      expect(labelsOf(out), ['Page 3', 'Page 1']);
      // the source document is unchanged
      expect(editing.document.pageCount, 3);
      expect(editing.isModified, isFalse);
    });

    test('exportPageRange exports a contiguous span', () {
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      final out = PdfDocument.open(editing.exportPageRange(1, 2));
      expect(labelsOf(out), ['Page 2', 'Page 3']);
    });
  });

  group('page selection', () {
    test('selectPage selects one page and sets the anchor', () {
      final editing = PdfEditingController(buildMultiPagePdf(5));
      addTearDown(editing.dispose);
      editing.selectPage(2);
      expect(editing.selectedPages, [2]);
      expect(editing.isPageSelected(2), isTrue);
      expect(editing.hasPageSelection, isTrue);
      expect(editing.selectedPageCount, 1);
    });

    test('selectPageRange extends a contiguous range from the anchor', () {
      final editing = PdfEditingController(buildMultiPagePdf(5));
      addTearDown(editing.dispose);
      editing.selectPage(1);
      editing.selectPageRange(3);
      expect(editing.selectedPages, [1, 2, 3]);
    });

    test('selectPageRange works backwards from the anchor', () {
      final editing = PdfEditingController(buildMultiPagePdf(5));
      addTearDown(editing.dispose);
      editing.selectPage(3);
      editing.selectPageRange(1);
      expect(editing.selectedPages, [1, 2, 3]);
    });

    test('a second shift-range re-extends from the same anchor', () {
      final editing = PdfEditingController(buildMultiPagePdf(6));
      addTearDown(editing.dispose);
      editing.selectPage(2);
      editing.selectPageRange(4);
      expect(editing.selectedPages, [2, 3, 4]);
      // anchor stays at 2 - extend the other way, replacing the range
      editing.selectPageRange(0);
      expect(editing.selectedPages, [0, 1, 2]);
    });

    test('pageRangePreviewTo mirrors the range a shift-click would select', () {
      final editing = PdfEditingController(buildMultiPagePdf(6));
      addTearDown(editing.dispose);
      editing.selectPage(1); // anchor at 1
      expect(editing.pageSelectionAnchor, 1);
      // a hover over 4 previews 1..4 without committing the selection
      expect(editing.pageRangePreviewTo(4), [1, 2, 3, 4]);
      expect(editing.pageRangePreviewTo(0), [0, 1]); // backwards too
      expect(editing.selectedPages, [1]); // preview never mutates
    });

    test('pageRangePreviewTo with no anchor previews just the page', () {
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      expect(editing.pageSelectionAnchor, isNull);
      expect(editing.pageRangePreviewTo(2), [2]);
    });

    test('togglePageSelection adds then removes individual pages', () {
      final editing = PdfEditingController(buildMultiPagePdf(5));
      addTearDown(editing.dispose);
      editing.selectPage(0);
      editing.togglePageSelection(2);
      editing.togglePageSelection(4);
      expect(editing.selectedPages, [0, 2, 4]);
      editing.togglePageSelection(2);
      expect(editing.selectedPages, [0, 4]);
    });

    test('selectAllPages then clearPageSelection', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      editing.selectAllPages();
      expect(editing.selectedPages, [0, 1, 2]);
      editing.clearPageSelection();
      expect(editing.hasPageSelection, isFalse);
    });

    test('removeSelectedPages deletes the selection in one undo', () {
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      editing.selectPage(0);
      editing.selectPageRange(1); // Page 1 and Page 2
      expect(editing.removeSelectedPages(), isTrue);
      expect(labelsOf(editing.document), ['Page 3', 'Page 4']);
      expect(editing.hasPageSelection, isFalse);
      editing.undo();
      expect(
          labelsOf(editing.document), ['Page 1', 'Page 2', 'Page 3', 'Page 4']);
    });

    test('removeSelectedPages refuses to empty the document', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      editing.selectAllPages();
      expect(editing.removeSelectedPages(), isFalse);
      expect(editing.document.pageCount, 3);
    });

    test('dragging a selected page reorders the whole selection', () {
      final editing = PdfEditingController(buildMultiPagePdf(6));
      addTearDown(editing.dispose);
      editing.selectPage(1);
      editing.togglePageSelection(3);

      editing.movePage(1, 4);

      expect(labelsOf(editing.document),
          ['Page 1', 'Page 3', 'Page 5', 'Page 6', 'Page 2', 'Page 4']);
      expect(editing.selectedPages, [4, 5]);
      expect(editing.pageSelectionAnchor, 4);
      editing.undo();
      expect(labelsOf(editing.document),
          ['Page 1', 'Page 2', 'Page 3', 'Page 4', 'Page 5', 'Page 6']);
    });

    test('a selected-page reorder preserves order and clamps at an edge', () {
      final editing = PdfEditingController(buildMultiPagePdf(6));
      addTearDown(editing.dispose);
      editing.selectPage(2);
      editing.togglePageSelection(4);

      // Page 5 is the dragged member, so it cannot itself land at zero while
      // Page 3 remains before it. Clamp the two-page block instead.
      editing.movePage(4, 0);

      expect(labelsOf(editing.document),
          ['Page 3', 'Page 5', 'Page 1', 'Page 2', 'Page 4', 'Page 6']);
      expect(editing.selectedPages, [0, 1]);
      expect(editing.pageSelectionAnchor, 1);
    });

    test('dropping a selected page on its selection is a no-op', () {
      final editing = PdfEditingController(buildMultiPagePdf(5));
      addTearDown(editing.dispose);
      editing.selectPage(1);
      editing.togglePageSelection(3);

      editing.movePage(1, 3);

      expect(labelsOf(editing.document),
          ['Page 1', 'Page 2', 'Page 3', 'Page 4', 'Page 5']);
      expect(editing.selectedPages, [1, 3]);
      expect(editing.isModified, isFalse);
    });

    test('a structural page edit clears the selection', () {
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      editing.selectPage(1);
      editing.selectPageRange(3);
      editing.addBlankPage();
      expect(editing.hasPageSelection, isFalse);
    });

    test('exportSelectedPages builds a standalone PDF in page order', () {
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      editing.selectPage(3);
      editing.togglePageSelection(1);
      final bytes = editing.exportSelectedPages();
      expect(bytes, isNotNull);
      expect(labelsOf(PdfDocument.open(bytes!)), ['Page 2', 'Page 4']);
      expect(editing.isModified, isFalse);
    });

    test('exportSelectedPages is null with nothing selected', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      expect(editing.exportSelectedPages(), isNull);
    });

    test('rotateSelectedPages turns the selection and keeps it', () {
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      editing.selectPage(0);
      editing.togglePageSelection(2);
      expect(editing.rotateSelectedPages(90), isTrue);
      expect(editing.document.page(0).rotation, 90);
      expect(editing.document.page(1).rotation, 0);
      expect(editing.document.page(2).rotation, 90);
      // a visual rotation does not shift indices, so the selection survives
      expect(editing.selectedPages, [0, 2]);
      editing.undo();
      expect(editing.document.page(0).rotation, 0);
    });

    test('rotateSelectedPages counterclockwise normalizes', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      editing.selectPage(1);
      expect(editing.rotateSelectedPages(-90), isTrue);
      expect(editing.document.page(1).rotation, 270);
    });

    test('rotateSelectedPages is a no-op with nothing selected', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      expect(editing.rotateSelectedPages(), isFalse);
      expect(editing.isModified, isFalse);
    });

    test('rotatePages targets explicit indices', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      expect(editing.rotatePages([1], 180), isTrue);
      expect(editing.document.page(1).rotation, 180);
      expect(editing.rotatePages([], 90), isFalse);
    });
  });

  group('page range dialog', () {
    testWidgets('returns the chosen 0-based inclusive range', (tester) async {
      ({int start, int end})? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPdfPageRangeDialog(context, pageCount: 10);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pdf-page-range-from')), '3');
      await tester.enterText(
          find.byKey(const ValueKey('pdf-page-range-to')), '7');
      await tester.tap(find.byKey(const ValueKey('pdf-page-range-confirm')));
      await tester.pumpAndSettle();
      expect(result, (start: 2, end: 6));
    });

    testWidgets('a reversed range is rejected and stays open', (tester) async {
      ({int start, int end})? result;
      var returned = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPdfPageRangeDialog(context, pageCount: 5);
                returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pdf-page-range-from')), '4');
      await tester.enterText(
          find.byKey(const ValueKey('pdf-page-range-to')), '2');
      await tester.tap(find.byKey(const ValueKey('pdf-page-range-confirm')));
      await tester.pumpAndSettle();
      // still open, nothing returned
      expect(returned, isFalse);
      expect(result, isNull);
      expect(
          find.byKey(const ValueKey('pdf-page-range-dialog')), findsOneWidget);
    });
  });

  group('thumbnail strip', () {
    testWidgets('the Add page footer appends a blank page', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(2));
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

      expect(editing.document.pageCount, 2);
      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-add-page')));
      await tester.pump();
      expect(editing.document.pageCount, 3);
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('holding shift previews the hovered range on the strip',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(5));
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

      BoxDecoration chip(int i) => tester
          .widget<Container>(find.byKey(ValueKey('pdf-thumbnail-tile-chip-$i')))
          .decoration as BoxDecoration;

      // anchor at Page 2 (index 1)
      await tester.tap(find.text('Page 2'));
      await tester.pump();
      expect(editing.selectedPages, [1]);

      // hover Page 4 (index 3) with a mouse
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Page 4')));
      await tester.pump();

      // no preview until shift goes down
      expect(chip(3).color, isNull);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      // 1..3 now read as filled chips (anchor + the previewed run); the
      // pages outside the range stay clear - and nothing is committed
      expect(chip(1).color, isNotNull);
      expect(chip(2).color, isNotNull);
      expect(chip(3).color, isNotNull);
      expect(chip(0).color, isNull);
      expect(chip(4).color, isNull);
      expect(editing.selectedPages, [1]);

      // releasing shift clears the preview (only the real selection remains)
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(chip(2).color, isNull);
      expect(chip(3).color, isNull);
      expect(chip(1).color, isNotNull); // still selected
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('the selection bar swaps in without shifting the tiles',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(5));
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

      final firstTile = find.byKey(const ValueKey('pdf-thumbnail-tile-chip-0'));
      final before = tester.getTopLeft(firstTile).dy;

      // multi-select so the bulk-action bar replaces the "Pages" header
      editing.selectPage(0);
      editing.selectPageRange(2);
      await tester.pump();
      expect(editing.selectedPageCount, 3);
      expect(find.byKey(const ValueKey('pdf-thumbnail-clear-selection')),
          findsOneWidget); // the bar is showing

      // the header slot is a fixed height, so the first tile hasn't moved
      expect(tester.getTopLeft(firstTile).dy, before);
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('hover page controls do not shift thumbnail strip tiles',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(5));
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

      final firstTile = find.byKey(const ValueKey('pdf-thumbnail-tile-chip-0'));
      final secondTile =
          find.byKey(const ValueKey('pdf-thumbnail-tile-chip-1'));
      final beforeFirstHeight = tester.getSize(firstTile).height;
      final beforeSecondTop = tester.getTopLeft(secondTile).dy;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(firstTile));
      await tester.pump();

      expect(
          find.byKey(const ValueKey('pdf-thumbnail-rotate-0')), findsOneWidget);
      expect(tester.getSize(firstTile).height, beforeFirstHeight);
      expect(tester.getTopLeft(secondTile).dy, beforeSecondTop);
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('arrow keys navigate the thumbnail strip selection',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(5));
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

      await tester.tap(find.text('Page 2'));
      await tester.pump();
      expect(editing.selectedPages, [1]);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(editing.selectedPages, [2]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(editing.selectedPages, [2, 3]);
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('shift-click selects a range, then deletes it', (tester) async {
      // a tall surface so every tile builds (the list is lazy)
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(5));
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

      // a plain tap selects one page (and anchors there)
      await tester.tap(find.text('Page 2'));
      await tester.pump();
      expect(editing.selectedPages, [1]);

      // shift-click extends the range from the anchor
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 4'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(editing.selectedPages, [1, 2, 3]);

      // the selection bar appears; its delete removes the whole selection
      // (the actions scroll horizontally on the narrow strip, so reveal it)
      final deleteSelected =
          find.byKey(const ValueKey('pdf-thumbnail-delete-selected'));
      expect(deleteSelected, findsOneWidget);
      await tester.ensureVisible(deleteSelected);
      await tester.tap(deleteSelected);
      await tester.pump();
      expect(labelsOf(editing.document), ['Page 1', 'Page 5']);
      expect(editing.hasPageSelection, isFalse);
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('Delete removes the strip selection', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(5));
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

      await tester.tap(find.text('Page 2'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 3'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(editing.selectedPages, [1, 2]);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(labelsOf(editing.document), ['Page 1', 'Page 4', 'Page 5']);
      expect(editing.hasPageSelection, isFalse);
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('Backspace deletes the keyboard page when nothing is selected',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(4));
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

      // land the keyboard cursor on page 2, then clear the selection so only
      // the navigation cursor remains
      await tester.tap(find.text('Page 2'));
      await tester.pump();
      editing.clearPageSelection();
      await tester.pump();
      expect(editing.hasPageSelection, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(labelsOf(editing.document), ['Page 1', 'Page 3', 'Page 4']);
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('ctrl-click toggles pages into the selection', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(4));
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

      await tester.tap(find.text('Page 1'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('Page 3'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(editing.selectedPages, [0, 2]);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the selection bar rotates, exports, and clears',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(4));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      Uint8List? exported;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(
              controller: editing,
              viewerController: viewer,
              onExportPages: (bytes) => exported = bytes,
            ),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Page 1'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 3'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(editing.selectedPages, [0, 1, 2]);

      // the single-row actions scroll horizontally on the narrow strip;
      // reveal each before tapping it
      Future<void> tapAction(String key) async {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pump();
      }

      // rotate right, then left: the two cancel back to no rotation
      await tapAction('pdf-thumbnail-rotate-selected-cw');
      expect(editing.document.page(0).rotation, 90);
      expect(editing.document.page(1).rotation, 90);
      expect(editing.document.page(2).rotation, 90);
      expect(editing.document.page(3).rotation, 0);
      // the selection survives a visual rotation
      expect(editing.selectedPages, [0, 1, 2]);

      await tapAction('pdf-thumbnail-rotate-selected-ccw');
      expect(editing.document.page(0).rotation, 0);
      expect(editing.selectedPages, [0, 1, 2]);

      // export hands the host the selected pages
      await tapAction('pdf-thumbnail-export-selected');
      expect(exported, isNotNull);
      expect(labelsOf(PdfDocument.open(exported!)),
          ['Page 1', 'Page 2', 'Page 3']);

      // clear empties the selection (and dismisses the bar)
      await tapAction('pdf-thumbnail-clear-selection');
      expect(editing.hasPageSelection, isFalse);
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('a per-tile rotate button turns one page', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(3));
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

      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-rotate-1')));
      await tester.pump();
      expect(editing.document.page(0).rotation, 0);
      expect(editing.document.page(1).rotation, 90);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a read-only strip has no Add page footer', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(
              controller: editing,
              viewerController: viewer,
              allowPageEditing: false,
            ),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('pdf-thumbnail-add-page')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('selected tiles use the chip frame without a check badge',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(3));
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

      BoxDecoration chipDecoration(int pageIndex) => tester
          .widget<Container>(
            find.byKey(ValueKey('pdf-thumbnail-tile-chip-$pageIndex')),
          )
          .decoration! as BoxDecoration;

      Color chipBorderColor(int pageIndex) =>
          (chipDecoration(pageIndex).border! as Border).top.color;

      final scheme = Theme.of(
        tester.element(find.byKey(const ValueKey('pdf-thumbnail-tile-chip-0'))),
      ).colorScheme;

      // nothing selected yet, so no tile carries a selected frame or badge
      expect(chipBorderColor(0), Colors.transparent);
      expect(chipBorderColor(1), Colors.transparent);
      expect(find.byIcon(Icons.check), findsNothing);

      // a plain tap selects exactly one page → the chip frame is the cue
      await tester.tap(find.text('Page 2'));
      await tester.pump();
      expect(editing.selectedPages, [1]);
      expect(chipBorderColor(0), Colors.transparent);
      expect(chipBorderColor(1), scheme.primary);
      expect(find.byIcon(Icons.check), findsNothing);

      // the frame tracks the whole selection, one per selected tile
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 3'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(editing.selectedPages, [1, 2]);
      expect(chipBorderColor(1), scheme.primary);
      expect(chipBorderColor(2), scheme.primary);
      expect(find.byIcon(Icons.check), findsNothing);

      // clearing the selection clears the selected frames
      editing.clearPageSelection();
      await tester.pump();
      expect(chipBorderColor(1), Colors.transparent);
      expect(chipBorderColor(2), Colors.transparent);
      expect(find.byIcon(Icons.check), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('multi-page reorder shows a count and dims companion pages',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(4));
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
      editing.selectPage(1);
      editing.selectPageRange(2);
      await tester.pump();

      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      list.onReorderStart!(1);
      await tester.pump();
      final companion = tester.widget<Opacity>(
        find.byKey(const ValueKey('pdf-thumbnail-reorder-companion-2')),
      );
      expect(companion.opacity, 0.35);

      final proxy = list.proxyDecorator!(
        const SizedBox(width: 100, height: 100),
        1,
        const AlwaysStoppedAnimation(1),
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: proxy)));
      expect(find.byKey(const ValueKey('pdf-thumbnail-reorder-count')),
          findsOneWidget);
      expect(find.text('2 pages'), findsOneWidget);
    });
  });

  group('thumbnail context menu', () {
    /// Pumps a sidebar over a [count]-page document.
    Future<PdfEditingController> pumpStrip(
      WidgetTester tester, {
      int count = 4,
      bool allowPageEditing = true,
      void Function(Uint8List bytes)? onExportPages,
    }) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(count));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(
              controller: editing,
              viewerController: viewer,
              allowPageEditing: allowPageEditing,
              onExportPages: onExportPages,
            ),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ));
      await tester.pump();
      return editing;
    }

    /// Right-clicks the tile labelled [label] and waits for the menu.
    Future<void> rightClickTile(WidgetTester tester, String label) async {
      await tester.tap(find.text(label),
          buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
    }

    testWidgets('right-clicking a tile opens the menu and rotates the page',
        (tester) async {
      final editing = await pumpStrip(tester);

      await rightClickTile(tester, 'Page 2');
      // the right-click selected just that page
      expect(editing.selectedPages, [1]);
      expect(find.byKey(const ValueKey('pdf-thumbnail-menu-rotate-right')),
          findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-menu-rotate-right')));
      await tester.pumpAndSettle();
      expect(editing.document.page(0).rotation, 0);
      expect(editing.document.page(1).rotation, 90);
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('the menu rotates left and a half turn', (tester) async {
      final editing = await pumpStrip(tester);

      await rightClickTile(tester, 'Page 1');
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-menu-rotate-left')));
      await tester.pumpAndSettle();
      expect(editing.document.page(0).rotation, 270);

      await rightClickTile(tester, 'Page 1');
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-menu-rotate-180')));
      await tester.pumpAndSettle();
      expect(editing.document.page(0).rotation, 90);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the menu deletes the right-clicked page', (tester) async {
      final editing = await pumpStrip(tester);

      await rightClickTile(tester, 'Page 2');
      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-menu-delete')));
      await tester.pumpAndSettle();
      expect(labelsOf(editing.document), ['Page 1', 'Page 3', 'Page 4']);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the menu duplicates the right-clicked page', (tester) async {
      final editing = await pumpStrip(tester, count: 2);

      await rightClickTile(tester, 'Page 1');
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-menu-duplicate')));
      await tester.pumpAndSettle();
      expect(labelsOf(editing.document), ['Page 1', 'Page 1', 'Page 2']);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the menu inserts a blank page before and after',
        (tester) async {
      final editing = await pumpStrip(tester, count: 2);

      await rightClickTile(tester, 'Page 2');
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-menu-insert-after')));
      await tester.pumpAndSettle();
      // a blank page lands after page 2 (index 2)
      expect(labelsOf(editing.document), ['Page 1', 'Page 2', '']);

      await rightClickTile(tester, 'Page 1');
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-menu-insert-before')));
      await tester.pumpAndSettle();
      expect(labelsOf(editing.document), ['', 'Page 1', 'Page 2', '']);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('inserting after navigates to the new page', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfEditorView(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      await tester.pump();

      await rightClickTile(tester, 'Page 2');
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-menu-insert-after')));
      await tester.pumpAndSettle();

      expect(editing.document.pageCount, 3);
      expect(viewer.currentPage, 2);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('⌘V paste reveals the new page instead of jumping to the top',
        (tester) async {
      // Structural edits preserve the existing view by default. Pasting from
      // the strip intentionally overrides that anchor and reveals the pages
      // that were just pasted.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(6));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfEditorView(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      await tester.pump();

      // copy page 1, then select a lower page as the paste anchor
      await tester.tap(find.text('Page 1'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      await tester.tap(find.text('Page 4'));
      await tester.pump();
      expect(editing.selectedPages, [3]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // pasted after page 4 (index 3) -> the copy lands at index 4
      expect(labelsOf(editing.document),
          ['Page 1', 'Page 2', 'Page 3', 'Page 4', 'Page 1', 'Page 5',
              'Page 6']);
      // the viewer (and the strip that follows it) lands on the pasted page,
      // not back at the top
      expect(viewer.currentPage, 4);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the menu exports the right-clicked page to the host',
        (tester) async {
      Uint8List? exported;
      final editing =
          await pumpStrip(tester, onExportPages: (bytes) => exported = bytes);

      await rightClickTile(tester, 'Page 3');
      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-menu-export')));
      await tester.pumpAndSettle();
      expect(exported, isNotNull);
      expect(labelsOf(PdfDocument.open(exported!)), ['Page 3']);
      // the document itself is untouched by an export
      expect(editing.document.pageCount, 4);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the menu is anchored in an offset navigator overlay',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            const SizedBox(width: 220),
            Expanded(
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: Row(children: [
                      PdfThumbnailSidebar(
                        controller: editing,
                        viewerController: viewer,
                        allowPageEditing: false,
                        onExportPages: (_) {},
                      ),
                      const Expanded(child: SizedBox()),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ));
      await tester.pump();

      final clickPosition = tester.getCenter(find.text('Page 1'));
      await tester.tapAt(
        clickPosition,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      final menuPosition = tester.getTopLeft(
        find.byKey(const ValueKey('pdf-thumbnail-menu-export')),
      );
      expect(
        (menuPosition.dx - clickPosition.dx).abs(),
        lessThan(100),
        reason: 'The nested overlay origin must not be added twice.',
      );

      await tester.tapAt(const Offset(900, 1200));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('right-clicking within a multi-selection spans the selection',
        (tester) async {
      final editing = await pumpStrip(tester, count: 5);

      // build a 3-page selection
      await tester.tap(find.text('Page 1'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 3'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(editing.selectedPages, [0, 1, 2]);

      // right-clicking a tile already in the selection keeps it whole, and
      // the menu's labels reflect the count
      await rightClickTile(tester, 'Page 2');
      expect(editing.selectedPages, [0, 1, 2]);
      expect(find.text('Delete 3 pages'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-menu-delete')));
      await tester.pumpAndSettle();
      expect(labelsOf(editing.document), ['Page 4', 'Page 5']);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('right-clicking outside the selection re-selects just it',
        (tester) async {
      final editing = await pumpStrip(tester, count: 5);

      await tester.tap(find.text('Page 1'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 3'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(editing.selectedPages, [0, 1, 2]);

      // a right-click on a tile that is NOT part of the selection drops it
      // and selects only the clicked page
      await rightClickTile(tester, 'Page 5');
      expect(editing.selectedPages, [4]);
      expect(find.text('Delete page'), findsOneWidget);
      // dismiss the menu without acting
      await tester.tapAt(const Offset(700, 700));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the delete entry is disabled on a single-page document',
        (tester) async {
      final editing = await pumpStrip(tester, count: 1);

      await rightClickTile(tester, 'Page 1');
      final delete =
          tester.widget(find.byKey(const ValueKey('pdf-thumbnail-menu-delete')))
              as PopupMenuItem;
      expect(delete.enabled, isFalse);
      expect(editing.document.pageCount, 1);
      // dismiss
      await tester.tapAt(const Offset(700, 700));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a read-only strip with no export handler shows no menu',
        (tester) async {
      final editing = await pumpStrip(tester, allowPageEditing: false);

      await rightClickTile(tester, 'Page 2');
      // no editing actions, no export handler → nothing opens
      expect(find.byKey(const ValueKey('pdf-thumbnail-menu-rotate-right')),
          findsNothing);
      expect(find.byKey(const ValueKey('pdf-thumbnail-menu-export')),
          findsNothing);
      expect(editing.document.pageCount, 4);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a read-only strip still offers export when given a handler',
        (tester) async {
      Uint8List? exported;
      await pumpStrip(tester,
          allowPageEditing: false, onExportPages: (bytes) => exported = bytes);

      await rightClickTile(tester, 'Page 2');
      // export is available, but the structural edits are not
      expect(find.byKey(const ValueKey('pdf-thumbnail-menu-export')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-thumbnail-menu-rotate-right')),
          findsNothing);
      expect(find.byKey(const ValueKey('pdf-thumbnail-menu-delete')),
          findsNothing);

      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-menu-export')));
      await tester.pumpAndSettle();
      expect(exported, isNotNull);
      expect(labelsOf(PdfDocument.open(exported!)), ['Page 2']);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
