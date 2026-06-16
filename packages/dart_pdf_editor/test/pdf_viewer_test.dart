import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show PdfTextExtractor;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  Future<PdfViewerController> pumpViewer(WidgetTester tester,
      {int pages = 5, Uint8List? bytes, PdfActionHandler? onAction}) async {
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          document: PdfDocument.open(bytes ?? buildMultiPagePdf(pages)),
          controller: controller,
          onAction: onAction,
        ),
      ),
    ));
    await tester.pump();
    return controller;
  }

  // buildAnnotatedPdf link geometry, in view coordinates (800px viewport
  // over a 612pt page): centers of the annotation rects on page 1
  const annotScale = 800 / 612;
  Offset annotView(double x, double y) =>
      Offset(x * annotScale, (792 - y) * annotScale);

  testWidgets('reports the page count and renders page widgets',
      (tester) async {
    final controller = await pumpViewer(tester);
    expect(controller.pageCount, 5);
    expect(controller.currentPage, 0);
    expect(find.byType(PdfPageView), findsWidgets);
  });

  testWidgets('opens fitted to the whole page by default', (tester) async {
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: PdfDocument.open(buildMultiPagePdf(2)),
          controller: controller,
        ),
      ),
    ));
    await tester.pump();

    // 800×600 viewport, 612×792 pages: fit-page = 600 / (800 · 792/612)
    expect(controller.zoom, closeTo(600 / (800 * 792 / 612), 0.001));
    final region = controller.visiblePageRegion(0)!;
    expect(region.left, closeTo(0, 0.001));
    expect(region.top, closeTo(0, 0.001));
    expect(region.right, closeTo(1, 0.001));
    expect(region.bottom, closeTo(1, 0.001));
    expect(controller.visiblePageRegion(1), isNull,
        reason: 'the next page starts below the viewport');
  });

  testWidgets('scrolling updates the current page', (tester) async {
    final controller = await pumpViewer(tester);
    await tester.drag(find.byType(PdfViewer), const Offset(0, -2500));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(controller.currentPage, greaterThan(0));
  });

  testWidgets('resizing a side panel preserves the reading position',
      (tester) async {
    // Page heights scale with the viewer width, so a panel resize that
    // shrinks the viewport used to slide the document under the reader.
    final controller = PdfViewerController();
    // one document instance: rebuilding with a fresh PdfDocument would look
    // like a swap and reset the viewport, masking the resize behavior.
    final document = PdfDocument.open(buildMultiPagePdf(8));
    Widget build(double panelWidth) => MaterialApp(
          home: Scaffold(
            body: Row(children: [
              SizedBox(width: panelWidth, height: double.infinity),
              Expanded(
                child: PdfViewer(
                  key: const ValueKey('viewer'),
                  initialFit: PdfViewerFit.width,
                  document: document,
                  controller: controller,
                ),
              ),
            ]),
          ),
        );

    await tester.pumpWidget(build(100));
    await tester.pump();

    // park a middle page near the top, a little into it so the anchor
    // fraction is non-trivial
    controller.jumpToPage(3); // async; fire-and-pump (no fake-async await)
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.drag(find.byType(PdfViewer), const Offset(0, -120));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final beforeTop = controller.visiblePageRegion(3)!.top;
    expect(beforeTop, greaterThan(0));

    // widen the panel: the viewer shrinks and every page rescales
    await tester.pumpWidget(build(300));
    await tester.pump(); // lay out at the new width
    await tester.pump(); // run the post-frame re-anchor

    final region = controller.visiblePageRegion(3);
    expect(region, isNotNull,
        reason: 'page 3 should still sit at the viewport top');
    expect(region!.top, closeTo(beforeTop, 0.02),
        reason: 'the same point of the page stays at the viewport top');
  });

  testWidgets('search finds matches and tracks the current one',
      (tester) async {
    final controller = await pumpViewer(tester);
    await tester.runAsync(() => controller.search('Page 4'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(controller.matchCount, 1);
    expect(controller.currentMatch, 0);
    expect(controller.isSearching, isFalse);
    // jumped to the match's page
    expect(controller.currentPage, 3);
  });

  testWidgets('match navigation wraps around', (tester) async {
    final controller = await pumpViewer(tester);
    await tester.runAsync(() => controller.search('Page'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.matchCount, 5);

    controller.nextMatch();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.currentMatch, 1);

    controller.previousMatch();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.currentMatch, 0);

    controller.previousMatch();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.currentMatch, 4); // wrapped

    controller.clearSearch();
    expect(controller.matchCount, 0);
  });

  testWidgets(
      'mounting next to an already-built ListenableBuilder does not '
      'notify during build', (tester) async {
    // Regression: _loadPages runs in initState (mid-build) and used to
    // notifyListeners synchronously, dirtying a sibling page indicator that
    // had already built this frame.
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ListenableBuilder(
            listenable: controller,
            builder: (_, __) => Text('${controller.pageCount}'),
          ),
          Expanded(
            child: PdfViewer(
              initialFit: PdfViewerFit.width,
              document: PdfDocument.open(buildMultiPagePdf(3)),
              controller: controller,
            ),
          ),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    await tester.pump(); // deferred notification lands
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets(
      'swapping documents under a Material AppBar does not dispatch '
      'scroll notifications during build', (tester) async {
    // Regression: didUpdateWidget (mid-build) used to call jumpTo(0) on a
    // document swap; jumpTo synchronously dispatches a ScrollNotification,
    // and the AppBar's scrolled-under listener reacts with setState —
    // illegally dirtying an ancestor during build.
    Widget app(PdfDocument document) => MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('viewer')),
            body: PdfViewer(document: document, initialFit: PdfViewerFit.width),
          ),
        );
    await tester.pumpWidget(app(PdfDocument.open(buildMultiPagePdf(3))));
    await tester.pump();
    await tester.drag(find.byType(PdfViewer), const Offset(0, -300));
    await tester.pump();

    await tester.pumpWidget(app(PdfDocument.open(buildMultiPagePdf(2))));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse drag selects text and copy reaches the clipboard',
      (tester) async {
    final controller = await pumpViewer(tester);
    // fixture text 'Page 1' sits at 72,720..148,720 (24pt, Helvetica AFM
    // advances) on a 612-wide page filling the 800px viewport
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    // start just right of the run (inside the hit tolerance), drag left
    // past its start so the whole string is selected
    final pageViewState = tester.state(find.byType(PdfPageView).first);

    final gesture = await tester.startGesture(view(158, 720),
        kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(-20, 0)); // pass the drag slop
    await tester.pump();
    await gesture.moveTo(view(50, 720));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.selectedText, 'Page 1');
    expect(controller.hasSelection, isTrue);
    // selection painting must not reshape the tree and recreate the page
    // view (that drops its raster: a white flash)
    expect(tester.state(find.byType(PdfPageView).first), same(pageViewState));

    final copied = <String?>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String?);
      }
      return null;
    });
    await controller.copySelection();
    expect(copied, ['Page 1']);

    controller.clearSelection();
    await tester.pump();
    expect(controller.hasSelection, isFalse);
    // drain the double-tap recognizer's timeout timer
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('selection geometry is exposed in PDF page coordinates',
      (tester) async {
    final controller = await pumpViewer(tester);
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    expect(controller.selectionPages, isEmpty);
    expect(controller.selectionRectsOn(0), isEmpty);

    final gesture = await tester.startGesture(view(158, 720),
        kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveTo(view(50, 720));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.selectedText, 'Page 1');
    expect(controller.selectionPages, [0]);
    final rects = controller.selectionRectsOn(0);
    expect(rects, isNotEmpty);
    // 'Page 1' is drawn at 72,720 in 24pt — the quads must surround it,
    // in page space (y up), not view space
    final bounds = rects.reduce((a, b) => PdfRect(
          a.left < b.left ? a.left : b.left,
          a.bottom < b.bottom ? a.bottom : b.bottom,
          a.right > b.right ? a.right : b.right,
          a.top > b.top ? a.top : b.top,
        ));
    expect(bounds.left, moreOrLessEquals(72, epsilon: 3));
    expect(bounds.bottom, lessThan(721));
    expect(bounds.top, greaterThan(720));
    expect(controller.selectionRectsOn(1), isEmpty);
  });

  testWidgets('hovering text shows the text cursor', (tester) async {
    await pumpViewer(tester);
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    MouseRegion region() => tester.widget<MouseRegion>(find
        .descendant(
            of: find.byType(PdfViewer), matching: find.byType(MouseRegion))
        .first);

    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 7);
    await gesture.addPointer(location: view(300, 500)); // empty page area
    addTearDown(gesture.removePointer);
    await tester.pump();
    // onHover fires on moves, not on the pointer appearing
    await gesture.moveTo(view(301, 500));
    await tester.pump();
    // empty page area: a drag grab-pans, so the cursor advertises it
    expect(region().cursor, SystemMouseCursors.grab);

    await gesture.moveTo(view(100, 720)); // over 'Page 1'
    await tester.pump();
    expect(region().cursor, SystemMouseCursors.text);

    await gesture.moveTo(view(300, 500));
    await tester.pump();
    expect(region().cursor, SystemMouseCursors.grab);

    // leaving the viewer entirely must also reset the cursor
    await gesture.moveTo(view(100, 720));
    await tester.pump();
    expect(region().cursor, SystemMouseCursors.text);
    await gesture.moveTo(const Offset(400, 900)); // outside the window
    await tester.pump();
    expect(region().cursor, MouseCursor.defer);
  });

  testWidgets('double-click with a mouse selects the word under it',
      (tester) async {
    final controller = await pumpViewer(tester);
    const scale = 800 / 612;
    final overText = Offset(100 * scale, (792 - 720) * scale);

    await tester.tapAt(overText, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(overText, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(controller.selectedText, 'Page');
    // and the viewer did not zoom
    expect(controller.zoom, 1);
  });

  testWidgets('double-click and drag selects whole words', (tester) async {
    final controller = await pumpViewer(tester);
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);
    // 'Page 1' at 24pt: 'Page' spans x 72..120, '1' spans x 132..144

    // first click
    await tester.tapAt(view(100, 720), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 80));
    // second press, held and dragged: anchor word 'Page', extend over '1'
    final gesture = await tester.startGesture(view(100, 720),
        kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(25, 0)); // pass the drag slop
    await tester.pump();
    await gesture.moveTo(view(140, 720));
    await tester.pump();
    expect(controller.selectedText, 'Page 1');

    // dragging back to the anchor word shrinks to just that word
    await gesture.moveTo(view(100, 720));
    await tester.pump();
    expect(controller.selectedText, 'Page');

    await gesture.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(controller.selectedText, 'Page');
  });

  testWidgets('rapid mouse clicks on an overlay button all land',
      (tester) async {
    // Regression: a double-tap recognizer that accepted mice held every
    // click in the gesture arena for ~300ms and claimed the second of two
    // rapid clicks, so overlay buttons dropped taps.
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          document: PdfDocument.open(buildMultiPagePdf(2)),
          pageOverlayBuilder: (context, pageIndex, geometry) => [
            if (pageIndex == 0)
              Positioned.fromRect(
                rect: geometry.toViewRect(const PdfRect(72, 692, 172, 742)),
                child: TextButton(
                  key: const Key('overlay'),
                  onPressed: () => taps++,
                  child: const Text('go'),
                ),
              ),
          ],
        ),
      ),
    ));
    await tester.pump();

    final center = tester.getCenter(find.byKey(const Key('overlay')));
    for (var i = 0; i < 4; i++) {
      await tester.tapAt(center, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(taps, 4);
  });

  testWidgets('mouse clicks activate links without double-tap delay',
      (tester) async {
    final actions = <PdfAction>[];
    await pumpViewer(tester,
        bytes: buildAnnotatedPdf(), onAction: (a, _) => actions.add(a));

    await tester.tapAt(annotView(136, 652),
        kind: PointerDeviceKind.mouse); // URI link center
    await tester.pump(); // next frame — no disambiguation wait
    expect(actions, hasLength(1));
  });

  testWidgets('touch double-tap still toggles zoom', (tester) async {
    final controller = await pumpViewer(tester);
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, greaterThan(1));
  });

  testWidgets('trackpad scrolling still moves the document while zoomed',
      (tester) async {
    final controller = await pumpViewer(tester);

    // unzoomed: two-finger scroll moves the list
    final flat = await tester.createGesture(
        kind: PointerDeviceKind.trackpad, pointer: 20);
    await flat.panZoomStart(const Offset(400, 300));
    for (var i = 1; i <= 5; i++) {
      await flat.panZoomUpdate(const Offset(400, 300),
          pan: Offset(0, -400.0 * i));
      await tester.pump();
    }
    await flat.panZoomEnd();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.currentPage, greaterThan(0));
    // don't await: the animation only advances while the test pumps
    unawaited(controller.jumpToPage(0));
    await tester.pumpAndSettle();

    // zoom in with a touch double-tap
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, greaterThan(1));

    // zoomed: two-finger scroll must keep moving through the document
    // (regression: InteractiveViewer used to claim the gesture and pan
    // only within the zoom window)
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad, pointer: 21);
    await gesture.panZoomStart(const Offset(400, 300));
    for (var i = 1; i <= 10; i++) {
      await gesture.panZoomUpdate(const Offset(400, 300),
          pan: Offset(0, -600.0 * i));
      await tester.pump();
    }
    await gesture.panZoomEnd();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.currentPage, greaterThan(0));
    expect(controller.zoom, greaterThan(1)); // scrolling didn't unzoom

    // trackpad pinch-out keeps working — and may pass 100% (2.5 × 0.2)
    final pinch = await tester.createGesture(
        kind: PointerDeviceKind.trackpad, pointer: 22);
    await pinch.panZoomStart(const Offset(400, 300));
    await pinch.panZoomUpdate(const Offset(400, 300), scale: 0.2);
    await tester.pump();
    await pinch.panZoomEnd();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, moreOrLessEquals(0.5, epsilon: 0.01));
  });

  testWidgets('zooming out past 100% floors at minZoom and recenters',
      (tester) async {
    final controller = await pumpViewer(tester);
    final pointer = TestPointer(13, PointerDeviceKind.mouse);
    pointer.hover(const Offset(400, 300));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    // ctrl+wheel-down passes below fit-width...
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 150)));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, lessThan(1));
    expect(controller.zoom, greaterThan(0.4));

    // ...and floors at minZoom (default 0.25), page centered in the view
    for (var i = 0; i < 5; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 600)));
      await tester.pump();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, moreOrLessEquals(0.25, epsilon: 0.001));

    // pages lay out at a quarter width, centered — and MORE of the
    // document is on screen: several pages fit the viewport at once
    final pageRect = tester.getRect(find.byType(PdfPageView).first);
    expect(pageRect.left, moreOrLessEquals(800 * 0.75 / 2, epsilon: 1));
    expect(pageRect.width, moreOrLessEquals(200, epsilon: 1));
    final second = tester.getRect(find.byType(PdfPageView).at(1));
    expect(second.top, lessThan(600)); // page 2 visible in the viewport
    final third = tester.getRect(find.byType(PdfPageView).at(2));
    expect(third.top, lessThan(600)); // and page 3

    // double-tap from zoomed-out returns to exactly 100%
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, 1);
  });

  testWidgets('trackpad fling keeps scrolling after lift-off', (tester) async {
    await pumpViewer(tester);
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);

    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad, pointer: 23);
    await gesture.panZoomStart(const Offset(400, 300));
    // brisk swipe: ~50px every 16ms ≈ 3000 px/s
    for (var i = 1; i <= 6; i++) {
      await gesture.panZoomUpdate(const Offset(400, 300),
          pan: Offset(0, -50.0 * i), timeStamp: Duration(milliseconds: 16 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 112));
    await tester.pump();
    final atLiftOff = scrollable.position.pixels;

    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(scrollable.position.pixels, greaterThan(atLiftOff + 100));
  });

  testWidgets('trackpad fling keeps scrolling with an edit tool armed',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(5));
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (_, __) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            editing: editing,
          ),
        ),
      ),
    ));
    await tester.pump();
    editing.tool = PdfEditTool.ink;
    await tester.pumpAndSettle();

    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad, pointer: 32);
    await gesture.panZoomStart(const Offset(400, 300));
    for (var i = 1; i <= 6; i++) {
      await gesture.panZoomUpdate(const Offset(400, 300),
          pan: Offset(0, -50.0 * i), timeStamp: Duration(milliseconds: 16 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 112));
    await tester.pump();
    final atLiftOff = scrollable.position.pixels;

    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(scrollable.position.pixels, greaterThan(atLiftOff + 100));
  });

  testWidgets('trackpad pinch zooms without scrolling the document',
      (tester) async {
    final controller = await pumpViewer(tester);
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);

    // macOS reports the fingers' drift as pan deltas during a magnify
    // gesture — the pinch must zoom only, never scroll
    final pinch = await tester.createGesture(
        kind: PointerDeviceKind.trackpad, pointer: 30);
    await pinch.panZoomStart(const Offset(400, 300));
    for (var i = 1; i <= 6; i++) {
      await pinch.panZoomUpdate(const Offset(400, 300),
          pan: Offset(0, -30.0 * i), scale: 1 + 0.2 * i);
      await tester.pump();
    }
    await pinch.panZoomEnd();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(controller.zoom, greaterThan(1.5));
    expect(scrollable.position.pixels, 0);
    expect(controller.currentPage, 0);
  });

  testWidgets('horizontal trackpad fling keeps panning while zoomed',
      (tester) async {
    final controller = await pumpViewer(tester);

    // zoom in with a touch double-tap (2.5×)
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, greaterThan(1));

    // brisk sideways swipe: ~40px every 16ms ≈ 2500 px/s
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad, pointer: 31);
    await gesture.panZoomStart(const Offset(400, 300));
    for (var i = 1; i <= 6; i++) {
      await gesture.panZoomUpdate(const Offset(400, 300),
          pan: Offset(-40.0 * i, 0), timeStamp: Duration(milliseconds: 16 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 112));
    await tester.pump();
    final atLiftOff = controller.visiblePageRegion(0)!.left;

    // momentum carries the zoom window on after lift-off
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(
        controller.visiblePageRegion(0)!.left, greaterThan(atLiftOff + 0.02));
    expect(controller.zoom, greaterThan(1)); // flinging didn't unzoom
  });

  testWidgets('search lands on the match in a long mixed-size document',
      (tester) async {
    final bytes = buildVariedHeightPdf(48);
    final controller = await pumpViewer(tester, bytes: bytes);

    await tester.runAsync(() => controller.search('Page 45'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.matchCount, 1);

    // exact target: heights cycle 792/396/1008 pt at 612 wide, laid out
    // fit-width in an 800px viewport with 12px spacing; the match sits a
    // third of the way down the viewport (see _showMatch)
    const heights = [792.0, 396.0, 1008.0];
    double pageHeight(int i) => heights[i % 3] / 612 * 800;
    var offset = 0.0;
    for (var i = 0; i < 44; i++) {
      offset += pageHeight(i) + 12;
    }
    final doc = PdfDocument.open(bytes);
    final match = PdfTextExtractor.extract(doc, 44).findAll('Page 45').single;
    final box = doc.page(44).cropBox;
    final fractionDown = (box.top - match.rects.first.top) / box.height;
    final expected = offset + fractionDown * pageHeight(44) - 600 / 3;

    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, moreOrLessEquals(expected, epsilon: 1));
    expect(controller.currentPage, 44);
  });

  testWidgets('search jump accounts for the zoom window', (tester) async {
    final controller = await pumpViewer(tester);

    // zoom in 2.5× with a touch double-tap at (400,300): the screen
    // viewport now sees list space through the window (p − t)/s
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, moreOrLessEquals(2.5, epsilon: 0.01));

    await tester.runAsync(() => controller.search('Page 4'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.matchCount, 1);

    // the match must sit a third of the way down the SCREEN, not a third
    // down the unprojected list viewport: t_y = −300·1.5, s = 2.5
    const pageHeight = 792 / 612 * 800;
    final doc = PdfDocument.open(buildMultiPagePdf(5));
    final match = PdfTextExtractor.extract(doc, 3).findAll('Page 4').single;
    final box = doc.page(3).cropBox;
    final fractionDown = (box.top - match.rects.first.top) / box.height;
    final matchY = 3 * (pageHeight + 12) + fractionDown * pageHeight;
    final expected = matchY + (-300 * 1.5) / 2.5 - 600 / (3 * 2.5);

    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, moreOrLessEquals(expected, epsilon: 1));
    expect(controller.visiblePageRegion(3), isNotNull);
  });

  testWidgets('zoomed trackpad scrolling reaches the document ends',
      (tester) async {
    final controller = await pumpViewer(tester, pages: 2);

    // zoom in with a touch double-tap
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, greaterThan(1));

    // scroll well past everything: the list hits its extent and the
    // leftover pans the zoom window down to the true bottom
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad, pointer: 24);
    await gesture.panZoomStart(const Offset(400, 300));
    for (var i = 1; i <= 20; i++) {
      await gesture.panZoomUpdate(const Offset(400, 300),
          pan: Offset(0, -1000.0 * i));
      await tester.pump();
    }
    await gesture.panZoomEnd();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // the last page's bottom edge must be visible in the 800x600 viewport
    final bottom = tester.getRect(find.byType(PdfPageView).last).bottom;
    expect(bottom, lessThanOrEqualTo(600 + 1e-6));
    expect(controller.zoom, greaterThan(1)); // still zoomed
  });

  testWidgets('plain wheel at the scroll extents does not zoom',
      (tester) async {
    // Regression: at the top/bottom edge the scrollable declines wheel
    // events, which then fell through to InteractiveViewer's wheel-zoom.
    final controller = await pumpViewer(tester, pages: 1);
    final pointer = TestPointer(12, PointerDeviceKind.mouse);
    pointer.hover(const Offset(400, 300));
    for (var i = 0; i < 10; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 400)));
      await tester.pump();
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, 1); // wheeled past the end: no zoom

    for (var i = 0; i < 10; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -400)));
      await tester.pump();
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, 1); // and past the top: no zoom
  });

  testWidgets('ctrl+wheel zooms, plain wheel scrolls', (tester) async {
    final controller = await pumpViewer(tester);
    final pointer = TestPointer(11, PointerDeviceKind.mouse);
    pointer.hover(const Offset(400, 300));

    // plain wheel: scrolls the list, no zoom
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, 1);
    expect(controller.currentPage, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -300)));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(controller.zoom, greaterThan(1));
  });

  testWidgets('default max zoom supports deep inspection of long plots',
      (tester) async {
    final controller = await pumpViewer(tester);
    final pointer = TestPointer(12, PointerDeviceKind.mouse);
    pointer.hover(const Offset(400, 300));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -1000)));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(controller.zoom, greaterThan(6));
  });

  testWidgets('tapping a URI link surfaces the action', (tester) async {
    final actions = <PdfAction>[];
    final annotations = <PdfAnnotation>[];
    await pumpViewer(tester, bytes: buildAnnotatedPdf(), onAction: (a, an) {
      actions.add(a);
      annotations.add(an);
    });

    await tester.tapAt(annotView(136, 652)); // URI link center
    // the tap fires once the competing double-tap recognizer times out
    await tester.pump(const Duration(milliseconds: 400));

    expect(actions, hasLength(1));
    expect((actions.single as PdfUriAction).uri, 'app://invoice/42');
    expect(annotations.single, isA<PdfLinkAnnotation>());
  });

  testWidgets('tapping a GoTo link navigates instead of surfacing it',
      (tester) async {
    final actions = <PdfAction>[];
    final controller = await pumpViewer(tester,
        bytes: buildAnnotatedPdf(), onAction: (a, _) => actions.add(a));

    await tester.tapAt(annotView(136, 612)); // GoTo link center
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(controller.currentPage, 2);
    expect(actions, isEmpty);
  });

  testWidgets('standard named page actions navigate internally',
      (tester) async {
    final actions = <PdfAction>[];
    final controller = await pumpViewer(tester,
        bytes: buildAnnotatedPdf(), onAction: (a, _) => actions.add(a));

    await tester.tapAt(annotView(350, 652)); // /Named /NextPage link
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(controller.currentPage, 1);
    expect(actions, isEmpty);
  });

  testWidgets('hidden annotations neither fire nor change the cursor',
      (tester) async {
    final actions = <PdfAction>[];
    await pumpViewer(tester,
        bytes: buildAnnotatedPdf(), onAction: (a, _) => actions.add(a));

    await tester.tapAt(annotView(350, 612)); // hidden URI link center
    await tester.pump(const Duration(milliseconds: 400));
    expect(actions, isEmpty);
  });

  testWidgets('hovering a link shows the click cursor', (tester) async {
    await pumpViewer(tester, bytes: buildAnnotatedPdf());

    MouseRegion region() => tester.widget<MouseRegion>(find
        .descendant(
            of: find.byType(PdfViewer), matching: find.byType(MouseRegion))
        .first);

    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 9);
    // an empty area inside the 800x600 test viewport (y=300 sits below it)
    await gesture.addPointer(location: annotView(450, 690));
    addTearDown(gesture.removePointer);
    await tester.pump();
    // onHover fires on moves, not on the pointer appearing
    await gesture.moveTo(annotView(451, 690));
    await tester.pump();
    expect(region().cursor, SystemMouseCursors.grab);

    await gesture.moveTo(annotView(136, 652)); // over the URI link
    await tester.pump();
    expect(region().cursor, SystemMouseCursors.click);

    await gesture.moveTo(annotView(100, 725)); // over 'Page 1' text
    await tester.pump();
    expect(region().cursor, SystemMouseCursors.text);

    await gesture.moveTo(annotView(350, 612)); // hidden link: grab like
    // any other empty area
    await tester.pump();
    expect(region().cursor, SystemMouseCursors.grab);
  });

  testWidgets('jumpToPage scrolls to the requested page', (tester) async {
    final controller = await pumpViewer(tester);
    controller.jumpToPage(4);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.currentPage, 4);
  });

  testWidgets('page overlays sit at PDF coordinates and stay interactive',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          document: PdfDocument.open(buildMultiPagePdf(2)),
          pageOverlayBuilder: (context, pageIndex, geometry) => [
            if (pageIndex == 0)
              Positioned.fromRect(
                rect: geometry.toViewRect(const PdfRect(72, 692, 172, 742)),
                child: TextButton(
                  key: const Key('overlay'),
                  onPressed: () => taps++,
                  child: const Text('go'),
                ),
              ),
          ],
        ),
      ),
    ));
    await tester.pump();

    // page 0 starts at scroll offset 0, so view space == page view space
    const scale = 800 / 612;
    final rect = tester.getRect(find.byKey(const Key('overlay')));
    expect(rect.left, moreOrLessEquals(72 * scale, epsilon: 0.1));
    expect(rect.top, moreOrLessEquals((792 - 742) * scale, epsilon: 0.1));
    expect(rect.width, moreOrLessEquals(100 * scale, epsilon: 0.1));
    expect(rect.height, moreOrLessEquals(50 * scale, epsilon: 0.1));

    // the overlay's own recognizer beats the viewer's tap/selection handling
    await tester.tap(find.byKey(const Key('overlay')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);

    // only page 0 got an overlay
    expect(find.byType(TextButton), findsOneWidget);
  });

  testWidgets('controller survives the host recreating the viewer element',
      (tester) async {
    final controller = PdfViewerController();
    final document = PdfDocument.open(buildMultiPagePdf(3));
    Widget viewer() => Expanded(
          child: PdfViewer(
            initialFit: PdfViewerFit.width,
            document: document,
            controller: controller,
          ),
        );

    // panels closed: the viewer is the row's only child
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Row(children: [viewer()])),
    ));
    await tester.pump();
    expect(controller.visiblePageRegion(0), isNotNull);

    // panels opening on BOTH sides (the example app right after its async
    // preference load): both ends of the keyless child list mismatch, so
    // the framework discards the old viewer element and inflates a fresh
    // one. The new state attaches to the controller in initState; the old
    // state's dispose is deferred to tree finalization and must not
    // detach it again.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          const SizedBox(width: 60),
          viewer(),
          const SizedBox(width: 60),
        ]),
      ),
    ));
    await tester.pump();

    expect(controller.visiblePageRegion(0), isNotNull,
        reason: 'the replacement viewer must stay attached');
    unawaited(controller.jumpToPage(2));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.currentPage, 2,
        reason: 'jumpToPage must reach the replacement viewer');
  });
}
