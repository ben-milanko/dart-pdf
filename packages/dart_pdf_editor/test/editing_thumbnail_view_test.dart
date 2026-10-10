import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kLongPressTimeout;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
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

  group('movePageToSlot', () {
    PdfEditingController editingOf(int pages) {
      final editing = PdfEditingController(buildMultiPagePdf(pages));
      addTearDown(editing.dispose);
      return editing;
    }

    test('a slot names the same gap in either direction', () {
      final editing = editingOf(4);
      // the order a drop would produce, for a panel to animate
      expect(editing.pageSlotOrder(0, 3), [1, 2, 0, 3]);
      expect(editing.pageSlotOrder(3, 0), [3, 0, 1, 2]);
      expect(editing.pageSlotOrder(1, 2), isNull);
      // forward: into the gap before page 4
      expect(editing.movePageToSlot(0, 3), isTrue);
      expect(
          labelsOf(editing.document), ['Page 2', 'Page 3', 'Page 1', 'Page 4']);
      // backward: into the gap before the first page
      expect(editing.movePageToSlot(3, 0), isTrue);
      expect(
          labelsOf(editing.document), ['Page 4', 'Page 2', 'Page 3', 'Page 1']);
      // past the end
      expect(editing.movePageToSlot(0, 4), isTrue);
      expect(
          labelsOf(editing.document), ['Page 2', 'Page 3', 'Page 1', 'Page 4']);
    });

    test('the gaps beside the moving page are no-ops', () {
      final editing = editingOf(4);
      final before = editing.document;
      expect(editing.pageSlotMoves(1, 1), isFalse);
      expect(editing.pageSlotMoves(1, 2), isFalse);
      expect(editing.pageSlotMoves(1, 0), isTrue);
      expect(editing.movePageToSlot(1, 2), isFalse);
      expect(identical(editing.document, before), isTrue);
    });

    test('a selection moves as a block into the gap', () {
      final editing = editingOf(5);
      editing
        ..selectPage(1)
        ..selectPageRange(2);
      expect(editing.selectedPages, [1, 2]);
      // the gap before page 5 - a destination index movePage would refuse
      // because it falls inside the selection
      expect(editing.movePageToSlot(1, 4), isTrue);
      expect(labelsOf(editing.document),
          ['Page 1', 'Page 4', 'Page 2', 'Page 3', 'Page 5']);
      expect(editing.selectedPages, [2, 3]);
      // a contiguous selection's own gaps change nothing
      expect(editing.pageSlotMoves(2, 2), isFalse);
      expect(editing.pageSlotMoves(3, 4), isFalse);
      expect(editing.pageSlotMoves(3, 3), isFalse);
    });

    test('a scattered selection gathers even beside itself', () {
      final editing = editingOf(5);
      editing
        ..selectPage(0)
        ..togglePageSelection(2);
      expect(editing.selectedPages, [0, 2]);
      expect(editing.pageSlotMoves(0, 0), isTrue);
      expect(editing.movePageToSlot(0, 0), isTrue);
      expect(labelsOf(editing.document),
          ['Page 1', 'Page 3', 'Page 2', 'Page 4', 'Page 5']);
    });
  });

  // a roomy surface so every grid cell lays out and is hit-testable (the
  // grid builds every child eagerly, but they still need to fit to tap)
  void wideScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<({PdfEditingController editing, PdfViewerController viewer})> pumpGrid(
    WidgetTester tester, {
    int pages = 4,
    bool allowPageEditing = true,
    void Function(Uint8List bytes)? onExportPages,
    void Function(int pageIndex)? onOpenPage,
    PdfEditingController? controller,
  }) async {
    final editing =
        controller ?? PdfEditingController(buildMultiPagePdf(pages));
    final viewer = PdfViewerController();
    if (controller == null) addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfThumbnailView(
          controller: editing,
          viewerController: viewer,
          allowPageEditing: allowPageEditing,
          onExportPages: onExportPages,
          onOpenPage: onOpenPage,
        ),
      ),
    ));
    await tester.pump();
    return (editing: editing, viewer: viewer);
  }

  // thumbnails rasterize on a serialized async queue; let it settle so no
  // work outlives the test
  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 2));

  group('PdfThumbnailView', () {
    testWidgets('lays out one cell per page', (tester) async {
      wideScreen(tester);
      await pumpGrid(tester, pages: 5);
      for (var i = 0; i < 5; i++) {
        expect(
            find.byKey(ValueKey('pdf-thumbnail-grid-cell-$i')), findsOneWidget);
      }
      await drain(tester);
    });

    testWidgets('the Add page footer appends a blank page', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 2);
      expect(refs.editing.document.pageCount, 2);
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-view-add-page')));
      await tester.pump();
      expect(refs.editing.document.pageCount, 3);
      expect(labelOf(refs.editing.document, 2), '');
      await drain(tester);
    });

    testWidgets('a click selects and a double-click opens the page',
        (tester) async {
      wideScreen(tester);
      int? opened;
      final refs = await pumpGrid(
        tester,
        pages: 4,
        onOpenPage: (i) => opened = i,
      );
      await tester.tap(find.text('Page 3'));
      await tester.pump();
      expect(refs.editing.selectedPages, [2]);
      expect(opened, isNull);

      await tester.tap(find.text('Page 3'));
      await tester.pump();
      expect(opened, 2);
      await drain(tester);
    });

    testWidgets('arrow keys move the grid page selection', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 5);

      await tester.tap(find.text('Page 2'));
      await tester.pump();
      expect(refs.editing.selectedPages, [1]);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(refs.editing.selectedPages, [2]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(refs.editing.selectedPages, [2, 3]);
      await drain(tester);
    });

    testWidgets('Ctrl+A selects every page in the grid', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 5);

      await tester.tap(find.text('Page 2'));
      await tester.pump();
      expect(refs.editing.selectedPages, [1]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(refs.editing.selectedPages, [0, 1, 2, 3, 4]);
      await drain(tester);
    });

    testWidgets('the size slider changes the tile-width preference',
        (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 3);
      final prefs = refs.editing.preferences;
      expect(prefs.thumbnailViewTileWidth, isNull);

      // drag the slider toward "larger"
      await tester.drag(find.byKey(const ValueKey('pdf-thumbnail-view-size')),
          const Offset(40, 0));
      await tester.pump();

      final width = prefs.thumbnailViewTileWidth;
      expect(width, isNotNull);
      expect(width, greaterThan(96));
      expect(width, lessThanOrEqualTo(360));
      await drain(tester);
    });

    testWidgets('the tile width follows the preference', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 3);
      refs.editing.preferences.thumbnailViewTileWidth = 300;
      await tester.pump();
      final size = tester
          .getSize(find.byKey(const ValueKey('pdf-thumbnail-grid-cell-0')));
      expect(size.width, moreOrLessEquals(300, epsilon: 0.5));
      await drain(tester);
    });

    testWidgets('shift-click builds a selection the bar deletes',
        (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 5);

      await tester.tap(find.text('Page 2'));
      await tester.pump();
      expect(refs.editing.selectedPages, [1]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 4'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(refs.editing.selectedPages, [1, 2, 3]);

      expect(find.byKey(const ValueKey('pdf-thumbnail-delete-selected')),
          findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-delete-selected')));
      await tester.pump();
      expect(labelsOf(refs.editing.document), ['Page 1', 'Page 5']);
      expect(refs.editing.hasPageSelection, isFalse);
      await drain(tester);
    });

    testWidgets('holding shift previews the hovered grid range',
        (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 5);

      BoxDecoration chip(int i) => tester
          .widget<Container>(find.byKey(ValueKey('pdf-thumbnail-tile-chip-$i')))
          .decoration as BoxDecoration;

      await tester.tap(find.text('Page 2'));
      await tester.pump();
      expect(refs.editing.selectedPages, [1]);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Page 4')));
      await tester.pump();
      expect(chip(3).color, isNull);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(chip(1).color, isNotNull);
      expect(chip(2).color, isNotNull);
      expect(chip(3).color, isNotNull);
      expect(chip(0).color, isNull);
      expect(chip(4).color, isNull);
      expect(refs.editing.selectedPages, [1]);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(chip(2).color, isNull);
      expect(chip(3).color, isNull);
      expect(chip(1).color, isNotNull);
      await drain(tester);
    });

    testWidgets('a per-tile rotate button turns one page', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 3);
      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-rotate-1')));
      await tester.pump();
      expect(refs.editing.document.page(0).rotation, 0);
      expect(refs.editing.document.page(1).rotation, 90);
      await drain(tester);
    });

    testWidgets('a long-press drag reorders pages', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 4);
      expect(labelsOf(refs.editing.document),
          ['Page 1', 'Page 2', 'Page 3', 'Page 4']);

      // touch is the default test pointer, so the cell waits for a long
      // press before dragging - pick up page 1, drop it on the trailing
      // half of page 3's cell (the gap after it)
      final from = tester
          .getCenter(find.byKey(const ValueKey('pdf-thumbnail-grid-cell-0')));
      final cell2 = tester
          .getRect(find.byKey(const ValueKey('pdf-thumbnail-grid-cell-2')));
      final to = cell2.center + Offset(cell2.width / 4, 0);
      final gesture = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveTo(to);
      await tester.pump();
      // the insertion bar marks the gap the page will land in (painted from
      // the page after it)
      expect(find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-3-left')),
          findsOneWidget);
      await gesture.up();
      await tester.pump();

      // page 1 lands in the gap after page 3
      expect(labelsOf(refs.editing.document),
          ['Page 2', 'Page 3', 'Page 1', 'Page 4']);
      expect(find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-3-left')),
          findsNothing);
      await drain(tester);
    });

    testWidgets('a reorder drag marks the gap and drops into it',
        (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 4);
      final cell = [
        for (var i = 0; i < 4; i++)
          tester.getRect(find.byKey(ValueKey('pdf-thumbnail-grid-cell-$i'))),
      ];
      // the cells share a row on the wide screen
      expect(cell[3].top, cell[0].top);
      Finder marker(int page, String edge) =>
          find.byKey(ValueKey('pdf-thumbnail-drop-indicator-$page-$edge'));
      final markers = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>)
              .value
              .startsWith('pdf-thumbnail-drop-indicator-'));

      final gesture = await tester.startGesture(cell[3].center);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));

      // hovering the dragged page's own gaps would move nothing - no bar
      await gesture.moveTo(cell[3].center + const Offset(1, 0));
      await tester.pump();
      expect(markers, findsNothing);

      // anywhere around the gap between pages 1 and 2 - page 1's trailing
      // half, the gap itself, page 2's leading half - is the same single
      // drop point, painted in the middle of the gap
      final gap = Offset((cell[0].right + cell[1].left) / 2, cell[0].center.dy);
      for (final at in [
        cell[0].center + Offset(cell[0].width / 4, 0),
        gap - const Offset(2, 0),
        gap + const Offset(2, 0),
        cell[1].center - Offset(cell[1].width / 4, 0),
      ]) {
        await gesture.moveTo(at);
        await tester.pump();
        expect(marker(1, 'left'), findsOneWidget);
        expect(markers, findsOneWidget);
        expect(tester.getRect(marker(1, 'left')).center.dx,
            moreOrLessEquals(gap.dx, epsilon: 0.5));
      }

      await gesture.up();
      await tester.pump();
      expect(labelsOf(refs.editing.document),
          ['Page 1', 'Page 4', 'Page 2', 'Page 3']);
      expect(markers, findsNothing);
      await drain(tester);
    });

    testWidgets('where a row wraps, the bar goes on the nearer end',
        (tester) async {
      wideScreen(tester);
      await pumpGrid(tester, pages: 12);
      final cell = [
        for (var i = 0; i < 12; i++)
          tester.getRect(find.byKey(ValueKey('pdf-thumbnail-grid-cell-$i'))),
      ];
      final wrapAt = cell.indexWhere((r) => r.top > cell[0].top);
      expect(wrapAt, greaterThan(1), reason: 'the grid needs two rows');
      Finder marker(int page, String edge) =>
          find.byKey(ValueKey('pdf-thumbnail-drop-indicator-$page-$edge'));

      final gesture = await tester.startGesture(cell[0].center);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      // past the end of the first row: the bar trails its last page
      await gesture.moveTo(cell[wrapAt - 1].centerRight + const Offset(8, 0));
      await tester.pump();
      expect(marker(wrapAt - 1, 'right'), findsOneWidget);
      // the start of the next row: the same gap, marked before its first page
      await gesture.moveTo(cell[wrapAt].centerLeft + const Offset(4, 0));
      await tester.pump();
      expect(marker(wrapAt, 'left'), findsOneWidget);
      expect(marker(wrapAt - 1, 'right'), findsNothing);
      await gesture.up();
      await drain(tester);
    });

    testWidgets('a reorder drop slides each page from where it was',
        (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 12);
      Rect cellRect(int i) =>
          tester.getRect(find.byKey(ValueKey('pdf-thumbnail-grid-cell-$i')));
      final before = [for (var i = 0; i < 12; i++) cellRect(i)];
      final wrapAt = before.indexWhere((r) => r.top > before[0].top);
      expect(wrapAt, greaterThan(1), reason: 'the grid needs two rows');

      // carry page 1 into the second row, before its second page
      final slot = wrapAt + 1;
      final drop = before[slot].centerLeft + const Offset(4, 0);
      final gesture = await tester.startGesture(before[0].center);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveTo(drop);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final order = [
        for (var i = 1; i < slot; i++) i,
        0,
        for (var i = slot; i < 12; i++) i,
      ];
      expect(labelsOf(refs.editing.document),
          [for (final o in order) 'Page ${o + 1}']);
      // the first frame of the new order paints every page where it was -
      // across the row wrap too - and the carried one at the drop point
      for (var i = 0; i < 12; i++) {
        final at = cellRect(i);
        final from = order[i] == 0
            ? drop - before[0].size.center(Offset.zero)
            : before[order[i]].topLeft;
        expect(at.left, moreOrLessEquals(from.dx, epsilon: 0.5),
            reason: 'cell $i');
        expect(at.top, moreOrLessEquals(from.dy, epsilon: 0.5),
            reason: 'cell $i');
      }
      // ...then every cell settles into its own place
      await tester.pumpAndSettle();
      for (var i = 0; i < 12; i++) {
        expect(cellRect(i).topLeft, before[i].topLeft, reason: 'cell $i');
      }
      await drain(tester);
    });

    testWidgets('a reorder drag near the bottom edge scrolls the grid',
        (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 40);
      final viewport = tester.getRect(find.descendant(
          of: find.byType(PdfThumbnailView),
          matching: find.byType(SingleChildScrollView)));
      final first = tester
          .getRect(find.byKey(const ValueKey('pdf-thumbnail-grid-cell-0')));

      final gesture = await tester.startGesture(first.center);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveTo(Offset(first.center.dx, viewport.bottom - 8));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final scrolled = tester
          .getRect(find.byKey(const ValueKey('pdf-thumbnail-grid-cell-0')));
      expect(scrolled.top, lessThan(first.top - 100));

      // moving away from the edge stops it
      await gesture.moveTo(viewport.center);
      await tester.pump(const Duration(milliseconds: 50));
      final held = tester
          .getRect(find.byKey(const ValueKey('pdf-thumbnail-grid-cell-0')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          tester
              .getRect(find.byKey(const ValueKey('pdf-thumbnail-grid-cell-0')))
              .top,
          held.top);
      await gesture.up();
      await tester.pumpAndSettle();
      // the drop still lands - page 1 left the first slot
      expect(labelOf(refs.editing.document, 0), isNot('Page 1'));
      await drain(tester);
    });

    testWidgets('the selection bar exports the selection', (tester) async {
      wideScreen(tester);
      Uint8List? exported;
      final refs = await pumpGrid(
        tester,
        pages: 4,
        onExportPages: (bytes) => exported = bytes,
      );
      await tester.tap(find.text('Page 1'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 2'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(refs.editing.selectedPages, [0, 1]);

      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-export-selected')));
      await tester.pump();
      expect(exported, isNotNull);
      expect(labelsOf(PdfDocument.open(exported!)), ['Page 1', 'Page 2']);
      await drain(tester);
    });

    testWidgets('a read-only grid drops the editing controls', (tester) async {
      wideScreen(tester);
      await pumpGrid(tester, pages: 3, allowPageEditing: false);
      // no footer, no per-tile rotate/delete, and no draggable cells
      expect(find.byKey(const ValueKey('pdf-thumbnail-view-add-page')),
          findsNothing);
      expect(
          find.byKey(const ValueKey('pdf-thumbnail-rotate-0')), findsNothing);
      expect(find.byType(LongPressDraggable<int>), findsNothing);
      expect(find.byType(Draggable<int>), findsNothing);
      await drain(tester);
    });
  });
}
