import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show PdfTextExtractor;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records the URLs the default [PdfViewer.onLaunchUrl] passes to
/// url_launcher, standing in for a real platform binding in tests.
class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  /// What [launchUrl] reports back - true means "opened".
  bool result = true;
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return result;
  }
}

/// A one-page PDF carrying a single /Link annotation whose /URI is [url],
/// at /Rect [72 640 200 664] - the same spot as buildAnnotatedPdf's first
/// link, so [annotView](136, 652) hits its center.
Uint8List buildUriLinkPdf(String url) {
  const content = 'BT /F1 24 Tf 72 720 Td (Link) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> '
        '/Annots [ << /Type /Annot /Subtype /Link /Rect [72 640 200 664] '
        '/A << /S /URI /URI ($url) >> >> ] >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
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
  return ascii(buffer.toString());
}

Uint8List buildPlainAnnotationPdf() {
  final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
    ..addNote(0, 100, 700, 'Host action');
  return editor.save();
}

void main() {
  Future<PdfViewerController> pumpViewer(WidgetTester tester,
      {int pages = 5,
      Uint8List? bytes,
      PdfActionHandler? onAction,
      PdfAnnotationTapHandler? onAnnotationTap,
      PdfUrlLauncher? onLaunchUrl}) async {
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          document: PdfDocument.open(bytes ?? buildMultiPagePdf(pages)),
          controller: controller,
          onAction: onAction,
          onAnnotationTap: onAnnotationTap,
          onLaunchUrl: onLaunchUrl,
        ),
      ),
    ));
    await tester.pump();
    return controller;
  }

  // buildAnnotatedPdf link geometry, in view coordinates (800px viewport
  // over a 612pt page): centers of the annotation rects on page 1
  const annotScale = 800 / 612;
  // The on-screen scale (px/pt) the viewer rests at with the 612pt-wide
  // fixture filling the 800px-wide viewport - i.e. controller.zoom at
  // fit-width. Public zoom is reported in px/pt (1.0 = actual size), so
  // fit-width is 800/612, not 1.
  const fitWidth = 800 / 612;
  Offset annotView(double x, double y) =>
      Offset(x * annotScale, (792 - y) * annotScale);

  testWidgets('reports the page count and renders page widgets',
      (tester) async {
    final controller = await pumpViewer(tester);
    expect(controller.pageCount, 5);
    expect(controller.currentPage, 0);
    expect(find.byType(PdfPageView), findsWidgets);
  });

  testWidgets('reports readiness for the mounted page raster', (tester) async {
    final controller = await pumpViewer(tester);
    for (var i = 0; i < 100 && !controller.isPageRasterReady(0); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(controller.isPageRasterReady(0), isTrue);
    expect(controller.isPageRasterReady(99), isFalse);
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

    // 800×600 viewport, 612×792 pages: fit-page fits the height, so the
    // scale is 600/792 px/pt (the whole page is 600px tall on screen)
    expect(controller.zoom, closeTo(600 / 792, 0.001));
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
    // and the AppBar's scrolled-under listener reacts with setState -
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
    // 'Page 1' is drawn at 72,720 in 24pt - the quads must surround it,
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
    // An ordinary (small) page still extracts synchronously on hover, so the
    // I-beam appears immediately. Only heavy pages defer (see
    // hover_text_warm_test).
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
    // and the viewer did not zoom (still resting at fit-width)
    expect(controller.zoom, closeTo(fitWidth, 0.001));
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
    await tester.pump(); // next frame - no disambiguation wait
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
    expect(controller.zoom, greaterThan(fitWidth));

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
    expect(controller.zoom, greaterThan(fitWidth)); // scrolling didn't unzoom

    // trackpad pinch-out keeps working - and crosses below fit-width
    // (2.5 × 0.2 = 0.5 of fit-width)
    final pinch = await tester.createGesture(
        kind: PointerDeviceKind.trackpad, pointer: 22);
    await pinch.panZoomStart(const Offset(400, 300));
    await pinch.panZoomUpdate(const Offset(400, 300), scale: 0.2);
    await tester.pump();
    await pinch.panZoomEnd();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, moreOrLessEquals(0.5 * fitWidth, epsilon: 0.02));
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
    // minZoom (0.25) is a fit-width multiple; in px/pt that is 0.25 × fit-width
    expect(controller.zoom, moreOrLessEquals(0.25 * fitWidth, epsilon: 0.002));

    // pages lay out at a quarter width, centered - and MORE of the
    // document is on screen: several pages fit the viewport at once
    final pageRect = tester.getRect(find.byType(PdfPageView).first);
    expect(pageRect.left, moreOrLessEquals(800 * 0.75 / 2, epsilon: 1));
    expect(pageRect.width, moreOrLessEquals(200, epsilon: 1));
    final second = tester.getRect(find.byType(PdfPageView).at(1));
    expect(second.top, lessThan(600)); // page 2 visible in the viewport
    final third = tester.getRect(find.byType(PdfPageView).at(2));
    expect(third.top, lessThan(600)); // and page 3

    // double-tap from zoomed-out returns to fit-width
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, closeTo(fitWidth, 0.001));
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
    // gesture - the pinch must zoom only, never scroll
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

  testWidgets('slow trackpad pinch-out does not latch as scrolling',
      (tester) async {
    final controller = await pumpViewer(tester);
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    final initialZoom = controller.zoom;

    final pinch = await tester.createGesture(
        kind: PointerDeviceKind.trackpad, pointer: 33);
    await pinch.panZoomStart(const Offset(400, 300));
    // The first, barely visible scale update already carries more than the
    // pan-intent threshold of finger drift. It is nevertheless a pinch and
    // must determine the intent for the complete gesture.
    await pinch.panZoomUpdate(const Offset(400, 300),
        pan: const Offset(0, -12), scale: 0.995);
    await tester.pump();
    await pinch.panZoomUpdate(const Offset(400, 300),
        pan: const Offset(0, -24), scale: 0.8);
    await tester.pump();
    await pinch.panZoomEnd();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(controller.zoom, lessThan(initialZoom));
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
    // double-tap zooms 2.5× fit-width; in px/pt that is 2.5 × fit-width
    expect(controller.zoom, moreOrLessEquals(2.5 * fitWidth, epsilon: 0.02));

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
    // wheeled past the end: no zoom (still resting at fit-width)
    expect(controller.zoom, closeTo(fitWidth, 0.001));

    for (var i = 0; i < 10; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -400)));
      await tester.pump();
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    // and past the top: no zoom
    expect(controller.zoom, closeTo(fitWidth, 0.001));
  });

  testWidgets('ctrl+wheel zooms, plain wheel scrolls', (tester) async {
    final controller = await pumpViewer(tester);
    final pointer = TestPointer(11, PointerDeviceKind.mouse);
    pointer.hover(const Offset(400, 300));

    // plain wheel: scrolls the list, no zoom
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, closeTo(fitWidth, 0.001));
    expect(controller.currentPage, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -300)));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(controller.zoom, greaterThan(fitWidth));
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

  testWidgets('default max zoom keeps 2400% available on phone-width views',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = await pumpViewer(tester, pages: 1);
    const phoneFitWidth = 360 / 612;
    expect(controller.zoom, closeTo(phoneFitWidth, 0.001));

    final interactiveViewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(interactiveViewer.maxScale, closeTo(24 / phoneFitWidth, 0.001));

    controller.setZoom(24);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, closeTo(24, 0.01));
  });

  testWidgets('controller zoom settles page rendering immediately',
      (tester) async {
    final controller = await pumpViewer(tester, pages: 1);
    controller.setZoom(2);
    await tester.pump();

    final page = tester.widget<PdfPageView>(find.byType(PdfPageView));
    expect(page.scale, greaterThan(1),
        reason: 'a discrete controller command must not wait for the '
            'gesture-only 200 ms quiet debounce');
  });

  testWidgets('controller layout zoom does not leave a delayed scroll settle',
      (tester) async {
    final controller = await pumpViewer(tester, pages: 3);
    unawaited(controller.jumpToPage(1));
    await tester.pumpAndSettle();

    controller.setZoom(1);
    await tester.pump();
    final settled = tester
        .widgetList<PdfPageView>(find.byType(PdfPageView))
        .map((page) => page.settleGeneration)
        .toList();

    await tester.pump(const Duration(milliseconds: 600));
    expect(
      tester
          .widgetList<PdfPageView>(find.byType(PdfPageView))
          .map((page) => page.settleGeneration),
      orderedEquals(settled),
      reason: 'a discrete zoom command must not repaint again after the '
          'gesture-only 500 ms scroll quiet window',
    );
  });

  testWidgets('tapping a URI link surfaces the action', (tester) async {
    // The default launcher only opens well-known external schemes, so the
    // fixture's app:// link falls through to onAction unchanged.
    final actions = <PdfAction>[];
    final annotations = <PdfAnnotation>[];
    final taps = <PdfAnnotationTapDetails>[];
    await pumpViewer(tester,
        bytes: buildAnnotatedPdf(),
        onAnnotationTap: taps.add, onAction: (a, an) {
      actions.add(a);
      annotations.add(an);
    });

    await tester.tapAt(annotView(136, 652)); // URI link center
    // the tap fires once the competing double-tap recognizer times out
    await tester.pump(const Duration(milliseconds: 400));

    expect(taps, hasLength(1));
    expect(taps.single.annotation, isA<PdfLinkAnnotation>());
    expect(taps.single.pageIndex, 0);
    expect(taps.single.pagePoint.dx, closeTo(136, 0.5));
    expect(taps.single.pagePoint.dy, closeTo(652, 0.5));
    expect(actions, hasLength(1));
    expect((actions.single as PdfUriAction).uri, 'app://invoice/42');
    expect(annotations.single, isA<PdfLinkAnnotation>());
  });

  testWidgets('onAnnotationTap fires for a plain annotation', (tester) async {
    final taps = <PdfAnnotationTapDetails>[];
    await pumpViewer(tester,
        bytes: buildPlainAnnotationPdf(), onAnnotationTap: taps.add);

    await tester.tapAt(annotView(110, 690)); // note icon center
    await tester.pump(const Duration(milliseconds: 400));

    expect(taps, hasLength(1));
    final tap = taps.single;
    expect(tap.pageIndex, 0);
    expect(tap.annotation.subtype, 'Text');
    expect(tap.pagePoint.dx, closeTo(110, 0.5));
    expect(tap.pagePoint.dy, closeTo(690, 0.5));
    expect(tap.pageViewPosition.dx, closeTo(annotView(110, 690).dx, 0.5));
    expect(tap.pageViewPosition.dy, closeTo(annotView(110, 690).dy, 0.5));
  });

  testWidgets('tapping an http link opens it via the default launcher',
      (tester) async {
    final fake = _FakeUrlLauncher();
    final previous = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = fake;
    addTearDown(() => UrlLauncherPlatform.instance = previous);

    final actions = <PdfAction>[];
    await pumpViewer(tester,
        bytes: buildUriLinkPdf('https://example.com/'),
        onAction: (a, _) => actions.add(a));

    await tester.tapAt(annotView(136, 652)); // the link center
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // it was launched, and a link the viewer follows itself never reaches
    // the onAction fallback
    expect(fake.launched, ['https://example.com/']);
    expect(actions, isEmpty);
  });

  testWidgets('onLaunchUrl takes over from the default and consumes the link',
      (tester) async {
    final opened = <Uri>[];
    final actions = <PdfAction>[];
    await pumpViewer(tester,
        bytes: buildAnnotatedPdf(),
        onLaunchUrl: (uri) async {
          opened.add(uri);
          return true;
        },
        onAction: (a, _) => actions.add(a));

    await tester.tapAt(annotView(136, 652)); // the app:// URI link center
    await tester.pump(const Duration(milliseconds: 400));

    // onLaunchUrl sees every parseable URI, custom scheme included, and a
    // link it opens does not fall through to onAction
    expect(opened, [Uri.parse('app://invoice/42')]);
    expect(actions, isEmpty);
  });

  testWidgets('a declined onLaunchUrl hands the link to onAction',
      (tester) async {
    final actions = <PdfAction>[];
    await pumpViewer(tester,
        bytes: buildAnnotatedPdf(),
        onLaunchUrl: (uri) async => false,
        onAction: (a, _) => actions.add(a));

    await tester.tapAt(annotView(136, 652));
    await tester.pump(const Duration(milliseconds: 400));

    expect(actions, hasLength(1));
    expect((actions.single as PdfUriAction).uri, 'app://invoice/42');
  });

  testWidgets('a throwing onLaunchUrl still falls back to onAction',
      (tester) async {
    final actions = <PdfAction>[];
    await pumpViewer(tester,
        bytes: buildAnnotatedPdf(),
        onLaunchUrl: (uri) async => throw StateError('no'),
        onAction: (a, _) => actions.add(a));

    await tester.tapAt(annotView(136, 652));
    await tester.pump(const Duration(milliseconds: 400));

    expect(actions, hasLength(1));
    expect((actions.single as PdfUriAction).uri, 'app://invoice/42');
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

  testWidgets('a JavaScript button action surfaces to onAction',
      (tester) async {
    // The viewer follows GoTo/Named/URI itself; JavaScript (and other
    // action types it has no handler for) are the host's call via onAction.
    final actions = <PdfAction>[];
    await pumpViewer(tester,
        bytes: buildAnnotatedPdf(), onAction: (a, _) => actions.add(a));

    await tester.tapAt(annotView(136, 532)); // the JavaScript push button
    await tester.pump(const Duration(milliseconds: 400));

    expect(actions, hasLength(1));
    expect((actions.single as PdfJavaScriptAction).script, 'app.alert(42)');
  });

  testWidgets('hidden annotations neither fire nor change the cursor',
      (tester) async {
    final actions = <PdfAction>[];
    final taps = <PdfAnnotationTapDetails>[];
    await pumpViewer(tester,
        bytes: buildAnnotatedPdf(),
        onAnnotationTap: taps.add,
        onAction: (a, _) => actions.add(a));

    await tester.tapAt(annotView(350, 612)); // hidden URI link center
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, isEmpty);
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

  testWidgets('disposing during an animated page jump is safe', (tester) async {
    final controller = await pumpViewer(tester);
    // Page 1 is close enough to use ScrollController.animateTo rather than
    // the far-jump shortcut. Remove the viewer before that future completes;
    // its ScrollController has no positions when the continuation resumes.
    unawaited(controller.jumpToPage(1));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
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

  testWidgets('touch horizontal pan rubber-bands and springs back',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(3));
    addTearDown(editing.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            editing: editing,
            controller: controller,
          ),
        ),
      ),
    ));
    await tester.pump();
    editing.tool = PdfEditTool.select;
    await tester.pump();

    // zoom in with a touch double-tap (2.5×)
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, greaterThan(1));

    // at 2.5×, the visible region is ~40% of the page width centered:
    // left ≈ 0.3, right ≈ 0.7
    final regionBefore = controller.visiblePageRegion(0)!;

    // touch drag to the right → the content slides right, visible region
    // slides left, pushing past the left edge (left < 0 in rubber-band)
    final gesture = await tester.startGesture(const Offset(400, 300),
        kind: PointerDeviceKind.touch);
    var stamp = Duration.zero;
    for (var i = 0; i < 12; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(60, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }

    // mid-drag: the visible region moved past the left edge
    final regionMidDrag = controller.visiblePageRegion(0)!;
    expect(regionMidDrag.left, lessThan(regionBefore.left),
        reason: 'the content should have shifted');

    await gesture.up(timeStamp: stamp + const Duration(milliseconds: 16));
    await tester.pump();

    // the spring-back animation brings the page back to the edge
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final regionAfter = controller.visiblePageRegion(0)!;
    expect(regionAfter.left, moreOrLessEquals(0, epsilon: 0.02));

    // clean up double-tap timer
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('touch horizontal pan moves the viewport within bounds',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(3));
    addTearDown(editing.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            editing: editing,
            controller: controller,
          ),
        ),
      ),
    ));
    await tester.pump();
    editing.tool = PdfEditTool.select;
    await tester.pump();

    // zoom in with a touch double-tap (2.5×)
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, greaterThan(1));

    final regionBefore = controller.visiblePageRegion(0)!;

    // touch drag to the LEFT → the content slides left, visible region
    // moves right (still within bounds, no edge hit)
    final gesture = await tester.startGesture(const Offset(400, 300),
        kind: PointerDeviceKind.touch);
    var stamp = Duration.zero;
    for (var i = 0; i < 6; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-30, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }

    final regionDragged = controller.visiblePageRegion(0)!;
    expect(regionDragged.left, greaterThan(regionBefore.left),
        reason: 'horizontal touch pan should move the viewport');

    await gesture.up(timeStamp: stamp + const Duration(milliseconds: 16));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('touch horizontal pan works without editing controller',
      (tester) async {
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          document: PdfDocument.open(buildMultiPagePdf(3)),
          controller: controller,
        ),
      ),
    ));
    await tester.pump();

    // zoom in with a touch double-tap (2.5×)
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(controller.zoom, greaterThan(1));

    final regionBefore = controller.visiblePageRegion(0)!;

    // touch drag to the LEFT → viewport moves right
    final gesture = await tester.startGesture(const Offset(400, 300),
        kind: PointerDeviceKind.touch);
    var stamp = Duration.zero;
    for (var i = 0; i < 6; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-30, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }

    final regionDragged = controller.visiblePageRegion(0)!;
    expect(regionDragged.left, greaterThan(regionBefore.left),
        reason: 'horizontal touch pan should work in reader mode');

    await gesture.up(timeStamp: stamp + const Duration(milliseconds: 16));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
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

  group('editing controller drives the document', () {
    testWidgets(
        'follows revisions with no host ListenableBuilder and no document',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      final controller = PdfViewerController();
      // deliberately no ListenableBuilder wrapping the viewer and no
      // `document:` - the viewer reads editing.document and subscribes to the
      // controller itself, so the host no longer owns that invariant.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            initialFit: PdfViewerFit.width,
            editing: editing,
            controller: controller,
          ),
        ),
      ));
      await tester.pump();
      expect(controller.pageCount, 3);

      // a structural edit advances the revision; the viewer must pick it up
      // on its own, without the host rebuilding it with a fresh document
      editing.removePage(2);
      await tester.pump();
      expect(controller.pageCount, 2,
          reason: 'the viewer tracks the controller revision by itself');
    });

    testWidgets('a stale standalone document never desyncs the viewer',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      // a document that does NOT match editing.document - the old debug
      // invariant would have asserted; now the viewer ignores it and follows
      // the controller instead.
      final stale = PdfDocument.open(buildMultiPagePdf(5));
      final controller = PdfViewerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            initialFit: PdfViewerFit.width,
            document: stale,
            editing: editing,
            controller: controller,
          ),
        ),
      ));
      await tester.pump();
      expect(controller.pageCount, 3,
          reason: 'editing.document wins over the standalone document');
    });

    test('a formController ignored by interactiveForms: false is not a source',
        () {
      // formController is ignored when interactiveForms is false, so it can't
      // stand in for the document - the assert must reject this rather than
      // let _document dereference a null document later.
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      expect(
        () => PdfViewer(formController: editing, interactiveForms: false),
        throwsAssertionError,
      );
      // with interactiveForms on (the default) it IS a source
      expect(PdfViewer(formController: editing), isNotNull);
    });

    testWidgets('a form fill revision reaches the viewer without a rebuild',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      final controller = PdfViewerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            initialFit: PdfViewerFit.width,
            formController: editing,
            controller: controller,
          ),
        ),
      ));
      await tester.pump();
      expect(controller.pageCount, 3);

      // formController owns the revisions too: a page removal must land
      // without the host wrapping the viewer in a ListenableBuilder.
      editing.removePage(2);
      await tester.pump();
      expect(controller.pageCount, 2,
          reason: 'the viewer subscribes to the form controller as well');
    });
  });

  // The viewer routes desktop right-click / touch secondary-tap to the
  // text menu via GestureDetector.onSecondaryTapUp → `_onSecondaryTapUp`.
  // When the host sets `contextMenuEnabled: false`, the menu must be
  // suppressed; the recognizer still runs so text selection, links, etc.
  // are unaffected.
  group('contextMenuEnabled', () {
    test('defaults to true', () {
      expect(
          PdfViewer(document: PdfDocument.open(buildMultiPagePdf(1)))
              .contextMenuEnabled,
          isTrue);
    });

    testWidgets('right-click on plain page text opens the text menu by default',
        (tester) async {
      final controller = await pumpViewer(tester, pages: 2);
      // 'Page 1' baseline at (72, 720), 24pt - mid-word of "Page"
      await tester.tapAt(annotView(100, 720), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-text-menu-copy')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-text-menu-select-all')),
          findsOneWidget);
      // dismiss the menu so the teardown of the viewer does not race it
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(controller.selectedText, isNotNull,
          reason: 'selection survives menu dismissal');
    });

    testWidgets(
        'right-click on plain page text is suppressed when '
        'contextMenuEnabled is false', (tester) async {
      final controller = PdfViewerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            initialFit: PdfViewerFit.width,
            document: PdfDocument.open(buildMultiPagePdf(2)),
            controller: controller,
            contextMenuEnabled: false,
          ),
        ),
      ));
      await tester.pump();

      await tester.tapAt(annotView(100, 720), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-text-menu-copy')), findsNothing);
      expect(
          find.byKey(const ValueKey('pdf-text-menu-select-all')), findsNothing);
    });

    testWidgets(
        'right-click hands the gesture to the host when '
        'onContextMenuRequested is set', (tester) async {
      final hostCalls = <PdfContextMenuRequest>[];
      final controller = PdfViewerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            initialFit: PdfViewerFit.width,
            document: PdfDocument.open(buildMultiPagePdf(2)),
            controller: controller,
            contextMenuEnabled: false,
            onContextMenuRequested: hostCalls.add,
          ),
        ),
      ));
      await tester.pump();

      await tester.tapAt(annotView(100, 720), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(hostCalls, hasLength(1),
          reason: 'host callback fires exactly once per right-click');
      expect(hostCalls.first.pageIndex, 0);
      // page coordinates land near (100, 720).
      final (x, y) = hostCalls.first.pagePoint;
      expect(x, closeTo(100, 0.001));
      expect(y, closeTo(720, 0.001));
      // The takeover prepares the same context the stock menu would have:
      // the word under the cursor is selected before the handoff, so the
      // host's own Copy has something to act on.
      expect(hostCalls.first.target, PdfContextMenuTarget.text);
      expect(hostCalls.first.selectedText, 'Page');
      expect(controller.selectedText, 'Page');
      expect(find.byKey(const ValueKey('pdf-text-menu-copy')), findsNothing);
    });

    testWidgets(
        'right-click does NOT hand off when contextMenuEnabled is true '
        '(default menu owns the gesture)', (tester) async {
      var hostCalls = 0;
      final controller = PdfViewerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            initialFit: PdfViewerFit.width,
            document: PdfDocument.open(buildMultiPagePdf(2)),
            controller: controller,
            // contextMenuEnabled defaults to true
            onContextMenuRequested: (request) {
              hostCalls++;
            },
          ),
        ),
      ));
      await tester.pump();

      await tester.tapAt(annotView(100, 720), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(hostCalls, 0,
          reason: 'host callback only fires when the default menu is off');
      expect(find.byKey(const ValueKey('pdf-text-menu-copy')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'touch long-press on plain page text hands the gesture to the host '
        'when contextMenuEnabled is false', (tester) async {
      // Covers _onLongPressStart's host-takeover branch (sets up text
      // selection, then hands the gesture to the host because the stock
      // menu is suppressed). Reader mode - no editing controller.
      final hostCalls = <PdfContextMenuRequest>[];
      final controller = PdfViewerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            initialFit: PdfViewerFit.width,
            document: PdfDocument.open(buildMultiPagePdf(2)),
            controller: controller,
            contextMenuEnabled: false,
            onContextMenuRequested: hostCalls.add,
          ),
        ),
      ));
      await tester.pump();

      // Hold a touch pointer past the long-press deadline on a word in
      // 'Page 1' (baseline (72, 720), 24pt - mid-word of "Page" lands at
      // ~view (100, 720)).
      final gesture = await tester.startGesture(annotView(100, 720),
          kind: PointerDeviceKind.touch);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(hostCalls, hasLength(1),
          reason: 'host callback fires exactly once per long-press');
      expect(hostCalls.first.pageIndex, 0);
      final (x, y) = hostCalls.first.pagePoint;
      expect(x, closeTo(100, 0.5));
      expect(y, closeTo(720, 0.5));
      expect(hostCalls.first.target, PdfContextMenuTarget.text);
      expect(hostCalls.first.selectedText, 'Page');
      // The stock text menu and selection chip must not appear; the host
      // owns the popup.
      expect(find.byKey(const ValueKey('pdf-text-menu-copy')), findsNothing);
      expect(
          find.byKey(const ValueKey('pdf-text-menu-select-all')), findsNothing);
    });

    // 🔴 regression: the desktop takeover used to fire before the stock
    // path resolved anything, so a right-click on a form widget / an
    // annotation reached the host as an anonymous position and left no
    // selection behind. Each target must now be named, and the same
    // selection the stock menu would have made must be in place.
    testWidgets(
        'right-click takeover names the annotation and selects it first',
        (tester) async {
      final hostCalls = <PdfContextMenuRequest>[];
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              editing: editing,
              contextMenuEnabled: false,
              onContextMenuRequested: hostCalls.add,
            ),
          ),
        ),
      ));
      await tester.pump();
      // clear of the 'Page 1' text, so only the annotation is under it
      editing.addRectangle(0, const PdfRect(300, 400, 400, 450));
      await tester.pump();

      await tester.tapAt(annotView(350, 425), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(hostCalls, hasLength(1));
      final request = hostCalls.single;
      expect(request.target, PdfContextMenuTarget.annotation);
      expect(request.annotation?.subtype, 'Square');
      expect(request.slot, 0);
      expect(request.controller, same(editing));
      expect(editing.selectedAnnotationSlots, [(0, 0)],
          reason: 'the takeover prepares the selection the stock menu '
              'would have had');
      expect(find.byKey(const ValueKey('pdf-annot-menu-delete')), findsNothing);
    });

    testWidgets('right-click takeover names a form widget target',
        (tester) async {
      final hostCalls = <PdfContextMenuRequest>[];
      final editing = PdfEditingController(buildAcroFormPdf());
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              editing: editing,
              contextMenuEnabled: false,
              onContextMenuRequested: hostCalls.add,
            ),
          ),
        ),
      ));
      await tester.pump();
      // the 'name' text widget sits at /Rect [72 700 300 724]
      await tester.tapAt(annotView(100, 712), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(hostCalls, hasLength(1));
      expect(hostCalls.single.target, PdfContextMenuTarget.formWidget);
    });
  });
}
