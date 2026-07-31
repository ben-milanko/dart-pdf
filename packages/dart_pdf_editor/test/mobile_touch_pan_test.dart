// Touch panning on a phone, where the two things that made it fail live:
//
//  1. the platform's real touch slop. Recognizers built in a
//     [RawGestureDetector] (the viewer's) are NOT given the ambient
//     `gestureSettings`, so they used the framework's 36px pan slop while
//     InteractiveViewer's own scale recognizer - a [GestureDetector], so
//     platform-configured - accepted at ~16px, won the arena, and dropped
//     the drag (`panEnabled: false`). Every test passed because the test
//     view reports no touch slop and both sides fell back to 36.
//  2. the canvas beside a page. With a tool armed the list's own drag
//     recognizer is stood down and only the per-page editing overlay pans -
//     so at fit scale a drag starting off-page moved nothing at all, and
//     PdfViewerFit.page (the phone default) leaves canvas down both sides.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A phone's touch slop: Android's 8dp (iOS is the same order), which the
  /// engine reports as `physicalTouchSlop` and MediaQuery hands to
  /// recognizers as `touchSlop` - half the framework's 18px default, so
  /// `panSlop` is 16 instead of 36.
  const phone = DeviceGestureSettings(touchSlop: 8);

  Future<(PdfEditingController, PdfViewerController)> pumpViewer(
    WidgetTester tester, {
    PdfViewerFit fit = PdfViewerFit.width,
    int pages = 3,
  }) async {
    final editing = PdfEditingController(buildMultiPagePdf(pages));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          // the viewer and InteractiveViewer both read their slop from here
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(gestureSettings: phone),
            child: ListenableBuilder(
              listenable: editing,
              builder: (context, _) => PdfViewer(
                initialFit: fit,
                document: editing.document,
                controller: viewer,
                editing: editing,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return (editing, viewer);
  }

  /// One ordinary swipe, in 16ms steps so the velocity tracker sees a drag.
  Future<void> swipe(WidgetTester tester, Offset from, Offset step,
      {int steps = 8}) async {
    final gesture =
        await tester.startGesture(from, kind: PointerDeviceKind.touch);
    var stamp = Duration.zero;
    for (var i = 0; i < steps; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(step, timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up(timeStamp: stamp);
    await tester.pumpAndSettle();
  }

  /// Double-tap zoom, then settle the disambiguation timer.
  Future<void> zoomIn(WidgetTester tester, PdfViewerController viewer) async {
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(viewer.zoom, greaterThan(1), reason: 'double tap should zoom in');
  }

  group('at the platform touch slop', () {
    testWidgets('a zoomed one-finger pan moves the page, not nothing',
        (tester) async {
      final (_, viewer) = await pumpViewer(tester);
      await zoomIn(tester, viewer);
      final before = viewer.visiblePageRegion(0)!;

      // Drag left: the visible window travels right across the page. With the
      // viewer's pan recognizer on the framework's 36px slop, IV's scale
      // recognizer accepted this at 16px and swallowed it - the window never
      // moved.
      await swipe(tester, const Offset(400, 300), const Offset(-20, 0));

      expect(viewer.visiblePageRegion(0)!.left, greaterThan(before.left),
          reason: 'a zoomed touch pan must reach the viewer, not '
              "InteractiveViewer's no-op scale handler");
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a zoomed one-finger pan moves vertically too', (tester) async {
      final (_, viewer) = await pumpViewer(tester);
      await zoomIn(tester, viewer);
      final before = viewer.visiblePageRegion(0)!;

      await swipe(tester, const Offset(400, 300), const Offset(0, -20));

      expect(viewer.visiblePageRegion(0)!.top, greaterThan(before.top),
          reason: 'the vertical half of the same drag path');
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('every recognizer the viewer builds takes the platform slop',
        (tester) async {
      // The regression itself: whatever slop IV's recognizer uses, the
      // viewer's must match it, or IV wins every one-finger drag on a device.
      // [RawGestureDetector] will not do this for us - Scrollable and
      // GestureDetector both assign `gestureSettings` by hand for the same
      // reason, so the viewer has to as well.
      await pumpViewer(tester);
      var checked = 0;
      for (final detector in tester
          .widgetList<RawGestureDetector>(find.byType(RawGestureDetector))) {
        detector.gestures.forEach((type, factory) {
          if (!_viewerRecognizers.contains(type.toString())) return;
          final recognizer = factory.constructor();
          addTearDown(recognizer.dispose);
          factory.initializer(recognizer);
          checked++;
          expect(recognizer.gestureSettings, phone,
              reason: '$type kept the framework slop; InteractiveViewer will '
                  'outrace it on a device');
        });
      }
      expect(checked, _viewerRecognizers.length,
          reason: 'every viewer-owned recognizer should have been mounted and '
              'checked - update _viewerRecognizers if one was renamed');
    });
  });

  group('with a tool armed at fit scale', () {
    testWidgets('a drag on the canvas beside the page still scrolls',
        (tester) async {
      // PdfViewerFit.page is the phone default: a portrait page leaves canvas
      // down both sides, and the list's own drag recognizer is stood down
      // because a tool is armed, so this drag used to move nothing.
      final (editing, viewer) =
          await pumpViewer(tester, fit: PdfViewerFit.page, pages: 5);
      editing.tool = PdfEditTool.select;
      await tester.pump();
      expect(viewer.currentPage, 0);

      await swipe(tester, const Offset(16, 300), const Offset(0, -25));

      expect(viewer.currentPage, greaterThan(0),
          reason: 'a thumb in the canvas margin must scroll the document');
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a drag over the page still belongs to the overlay',
        (tester) async {
      // The other half of the gate: the page itself stays the overlay's, so
      // arming ink still draws instead of panning.
      final (editing, viewer) =
          await pumpViewer(tester, fit: PdfViewerFit.page, pages: 5);
      editing.tool = PdfEditTool.ink;
      await tester.pump();

      await swipe(tester, const Offset(400, 300), const Offset(6, 6));
      // the stroke's commit debounce
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));

      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(1), reason: 'the stroke should have drawn');
      expect(annotations.single.subtype, 'Ink');
      expect(viewer.currentPage, 0, reason: 'and must not have panned');
    });

    testWidgets("reader mode keeps the list's own physics", (tester) async {
      // No tool, not zoomed: the list scrolls natively (platform fling), and
      // the viewer's pan recognizer must stay out of the arena.
      final (_, viewer) = await pumpViewer(tester, fit: PdfViewerFit.page);
      expect(tester.widget<Scrollable>(find.byType(Scrollable).first).physics,
          isNull);

      await swipe(tester, const Offset(400, 300), const Offset(0, -25));
      expect(viewer.currentPage, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}

/// The recognizers `PdfViewer` mounts with itself, by type name - the ones
/// that have to be handed the platform's `gestureSettings` because
/// [RawGestureDetector] won't. Everything else in the tree (Scrollable's
/// drags, the editing overlay's [GestureDetector]) is the framework's to
/// configure. Handle-drag recognizers, mounted only with a live text
/// selection, aren't listed: they accept on pointer-down, so no slop applies.
const _viewerRecognizers = {
  'DoubleTapGestureRecognizer',
  '_TrackpadPanRecognizer',
  '_EagerPinchRecognizer',
  '_ZoomedTouchPanRecognizer',
  'PanGestureRecognizer',
  '_SelectionLongPressRecognizer',
};
