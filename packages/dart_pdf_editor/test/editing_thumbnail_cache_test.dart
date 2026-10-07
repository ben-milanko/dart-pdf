import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/thumbnail_cache.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // let the serialized async render queue flush its microtasks
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  group('PdfThumbnailCache scheduler', () {
    test('long web documents skip speculative whole-document warming', () {
      expect(pdfShouldWarmThumbnails(24, web: true), isTrue);
      expect(pdfShouldWarmThumbnails(25, web: true), isFalse);
      expect(pdfShouldWarmThumbnails(138, web: true), isFalse);
      expect(pdfShouldWarmThumbnails(138, web: false), isTrue);
    });

    testWidgets(
        'serves the pending task nearest the focus first, one per '
        'frame', (tester) async {
      final cache = PdfThumbnailCache();
      addTearDown(cache.dispose);
      final order = <int>[];
      cache.focus = 5;
      for (final page in [0, 5, 2]) {
        cache.request(Object(), page, () async => order.add(page));
      }
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      // A tile's interpret+raster is tens of milliseconds of platform thread,
      // so the queue yields a frame between them - that frame is what lets the
      // viewer queue the page a reader just scrolled onto, and the gate then
      // sees it and stands the whole queue down.
      expect(order.length, lessThan(3),
          reason: 'the queue no longer drains in one turn');
      expect(order.first, 5, reason: 'nearest the focus goes first');

      for (var i = 0; i < 6 && order.length < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      // distance from focus 5: page 5 (0) < page 2 (3) < page 0 (5)
      expect(order, [5, 2, 0]);
    });

    test('a cancelled request never runs', () async {
      final cache = PdfThumbnailCache();
      addTearDown(cache.dispose);
      final order = <int>[];
      final token = Object();
      cache.request(token, 0, () async => order.add(0));
      cache.request(Object(), 1, () async => order.add(1));
      // cancel before the microtask drain gets to it
      cache.cancel(token);
      await settle();
      expect(order, [1]);
    });

    test('re-requesting the same token refreshes rather than duplicating',
        () async {
      final cache = PdfThumbnailCache();
      addTearDown(cache.dispose);
      var runs = 0;
      final token = Object();
      cache.request(token, 0, () async => runs++);
      cache.request(token, 9, () async => runs++); // same token, new page
      await settle();
      expect(runs, 1);
    });
  });

  // #603: the warm already yields to on-screen TILES and renders at a lower
  // worker priority, but its replay and rasterize still run on the platform
  // thread - the one the visible page's build needs, and the one a worker
  // priority cannot reach. The gate is what makes it stand down for the viewer.
  group('PdfThumbnailCache foreground gate', () {
    testWidgets(
        'the warm stands down while the viewer renders, and resumes '
        'when it goes idle', (tester) async {
      final cache = PdfThumbnailCache(warmIdleDelay: Duration.zero);
      addTearDown(cache.dispose);
      final activity = _TestActivity();
      var viewerBusy = true;
      cache.bindForegroundGate(activity, () => viewerBusy);

      final warmed = <int>[];
      cache.setWarm(Object(), 3, 'k', (page) async => warmed.add(page));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(warmed, isEmpty, reason: 'the viewer is still rendering');

      // the viewer went idle: its activity ping re-kicks the loop - the warm
      // must not be waiting on a frame poll that never comes
      viewerBusy = false;
      activity.ping();
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(warmed, [0, 1, 2]);
    });

    testWidgets('visible tile renders also stand down for the viewer',
        (tester) async {
      final cache = PdfThumbnailCache();
      addTearDown(cache.dispose);
      final activity = _TestActivity();
      var viewerBusy = true;
      cache.bindForegroundGate(activity, () => viewerBusy);

      final rendered = <int>[];
      cache.request(Object(), 4, () async => rendered.add(4));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(rendered, isEmpty,
          reason: 'the soft viewer preview stays visible during motion');

      viewerBusy = false;
      activity.ping();
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(rendered, [4]);
    });

    // A tile's own render is held while the viewer is busy (above), so its
    // soft viewer preview is what a reader sees mid-scroll. The tile picks
    // that preview up in build - and a viewer tick no longer rebuilds the
    // tile (its viewport frame absorbs the tick), so a tile that mounted
    // before its page's preview existed has to be told the preview landed.
    // Hoisting the thumbnail out of the per-tick rebuild without that watch
    // left such a tile blank paper for the whole scroll.
    Future<({PdfEditingController editing, PdfViewerController viewer})>
        pumpStripBesideViewer(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      // tall enough that every tile of the 8-page strip is mounted
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final editing = PdfEditingController(buildMultiPagePdf(8));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(controller: editing, viewerController: viewer),
            Expanded(
              child: PdfViewer(
                initialFit: PdfViewerFit.width,
                controller: viewer,
                editing: editing,
              ),
            ),
          ]),
        ),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      return (editing: editing, viewer: viewer);
    }

    // The tile's own raster never lands under the fake clock (it needs real
    // async), so a RawImage in a tile can only be the viewer's preview.
    Finder tileImage(int page) => find.descendant(
        of: find.byKey(ValueKey('pdf-thumbnail-tile-chip-$page')),
        matching: find.byType(RawImage));

    Future<void> wheel(WidgetTester tester, int ticks) async {
      final center = tester.getRect(find.byType(PdfViewer)).center;
      for (var i = 0; i < ticks; i++) {
        await tester.sendEventToBinding(PointerScrollEvent(
            position: center, scrollDelta: const Offset(0, 40)));
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets(
        'a tile mounted before its viewer preview shows it once the '
        'viewer scrolls', (tester) async {
      final refs = await pumpStripBesideViewer(tester);
      const target = 7;
      expect(find.byKey(const ValueKey('pdf-thumbnail-tile-chip-$target')),
          findsOneWidget);
      expect(refs.viewer.pagePreviewCache!.has(target), isFalse);
      expect(tileImage(target), findsNothing);

      // the viewer renders that page mid-scroll and its preview lands
      await tester.runAsync(() => refs.viewer.pagePreviewCache!
          .renderPreview(target, refs.editing.pageAt(target)));
      await wheel(tester, 5);
      expect(tileImage(target), findsOneWidget,
          reason: 'the soft preview, not blank paper, while the viewer '
              'holds the tile\'s own render');
      await unmount(tester);
    });

    testWidgets(
        'a landing viewer preview reaches a blank tile without a scroll',
        (tester) async {
      final refs = await pumpStripBesideViewer(tester);
      const target = 6;
      expect(tileImage(target), findsNothing);
      // the preview cache notifies as the preview lands; nothing else moves
      await tester.runAsync(() => refs.viewer.pagePreviewCache!
          .renderPreview(target, refs.editing.pageAt(target)));
      await tester.pump();
      expect(tileImage(target), findsOneWidget);
      await unmount(tester);
    });

    testWidgets(
        'a viewer scroll rebuilds only the frames whose mark moved, never '
        'the thumbnails', (tester) async {
      final refs = await pumpStripBesideViewer(tester);
      // seed every tile, so no tile is still watching for its preview
      await tester.runAsync(() async {
        for (var i = 0; i < 8; i++) {
          await refs.viewer.pagePreviewCache!
              .renderPreview(i, refs.editing.pageAt(i));
        }
      });
      await tester.pump();
      await wheel(tester, 1); // settle the first tick's current-page flip

      final rebuilt = <String, int>{};
      debugOnRebuildDirtyWidget = (element, _) {
        final type = element.widget.runtimeType.toString();
        rebuilt[type] = (rebuilt[type] ?? 0) + 1;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      const ticks = 5;
      await wheel(tester, ticks);
      debugOnRebuildDirtyWidget = null;

      expect(rebuilt['_PageThumbnail'] ?? 0, 0,
          reason: 'a tick used to rebuild every mounted page thumbnail');
      final frames = rebuilt['_TileViewportFrame'] ?? 0;
      expect(frames, greaterThan(0), reason: 'the viewport mark still moves');
      expect(frames, lessThan(8 * ticks),
          reason: 'only the tiles whose region changed rebuild');

      // and the frames that sat the ticks out were right to: every tile's
      // mark and outline still agree with the viewer
      for (var i = 0; i < 8; i++) {
        final chip = find.byKey(ValueKey('pdf-thumbnail-tile-chip-$i'));
        final marks = tester.widgetList<CustomPaint>(find.descendant(
            of: chip,
            matching: find.byWidgetPredicate((w) =>
                w is CustomPaint &&
                w.painter.runtimeType.toString() == '_ViewportPainter')));
        final region = refs.viewer.visiblePageRegion(i);
        expect(
            // ignore: avoid_dynamic_calls
            [for (final mark in marks) (mark.painter as dynamic).region],
            [if (region != null) region],
            reason: 'page ${i + 1} viewport mark');
        // the 2px ring is the current page's; every other frame is 1px
        final outlined = find.descendant(
            of: chip,
            matching: find.byWidgetPredicate((w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                ((w.decoration! as BoxDecoration).border as Border?)
                        ?.top
                        .width ==
                    2));
        expect(outlined,
            refs.viewer.currentPage == i ? findsOneWidget : findsNothing,
            reason: 'page ${i + 1} current-page outline');
      }
      await unmount(tester);
    });

    testWidgets(
        'a granted visible tile defers its worker result and retries after '
        'scroll settle', (tester) async {
      // Regression for the 2026-08-11 trace: page 85 was granted while idle,
      // spent 414 ms recording in the worker, then replayed/rasterized on the
      // platform thread after the viewer's fast-scroll hold had begun.
      SharedPreferences.setMockInitialValues({});
      PdfThumbnailSidebar.debugRasterizations = 0;
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      final worker = _HeldFirstWorker();
      final activity = _TestActivity();
      var viewerBusy = false;
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      addTearDown(worker.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: Row(children: [
              PdfThumbnailSidebar(
                controller: editing,
                viewerController: viewer,
                renderWorker: worker,
              ),
              const Expanded(child: SizedBox()),
            ]),
          ),
        ),
      ));
      for (var i = 0; i < 10 && !worker.firstStarted.isCompleted; i++) {
        await tester.pump();
      }
      expect(worker.firstStarted.isCompleted, isTrue,
          reason: 'the tile should already be recording off-thread');

      // Replace the unmounted viewer controller's idle gate with the exact
      // busy transition from the trace, then release the worker reply.
      viewerBusy = true;
      editing.thumbnailCache.bindForegroundGate(activity, () => viewerBusy);
      worker.releaseFirst();
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(worker.calls, 1);
      expect(PdfThumbnailSidebar.debugRasterizations, 0,
          reason: 'no replay/raster should land during fast scrolling');

      viewerBusy = false;
      activity.ping();
      for (var i = 0;
          i < 100 && PdfThumbnailSidebar.debugRasterizations == 0;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(worker.calls, 2, reason: 'the deferred tile should retry once');
      expect(PdfThumbnailSidebar.debugRasterizations, 1);
    });

    testWidgets('a blocked warm logs once, not once per activity ping',
        (tester) async {
      // The render scheduler pings its activity Listenable on every grant,
      // settle, request and hold transition - most of them while it is still
      // busy. Each ping used to spin up a warm loop that immediately stood down
      // again, costing a microtask and a log line. The 2026-07-29 trace carries
      // ~90 `thumbnail warm yields` lines and not one `thumbnail warm page=`:
      // the repeats said nothing the first did not, and buried the lines that
      // mattered.
      final logs = <String>[];
      PdfPerfLog.sink = logs.add;
      PdfPerfLog.enabled = true;
      addTearDown(() {
        PdfPerfLog.enabled = false;
        PdfPerfLog.sink = null;
      });

      final cache = PdfThumbnailCache(warmIdleDelay: Duration.zero);
      addTearDown(cache.dispose);
      final activity = _TestActivity();
      var viewerBusy = true;
      cache.bindForegroundGate(activity, () => viewerBusy);

      final warmed = <int>[];
      cache.setWarm(Object(), 3, 'k', (page) async => warmed.add(page));
      for (var i = 0; i < 30; i++) {
        activity.ping();
        await tester.pump();
      }
      expect(warmed, isEmpty);
      expect(
        logs.where((line) => line.contains('thumbnail warm yields')).length,
        1,
        reason: 'one line per transition into yielding, not per ping',
      );

      // Going idle must still resume it - the quieter log must not have cost
      // the wake-up.
      viewerBusy = false;
      activity.ping();
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(warmed, [0, 1, 2]);

      // ...and a fresh block after real progress logs again, so a warm that
      // stalls a second time is still visible.
      viewerBusy = true;
      cache.setWarm(Object(), 3, 'k2', (page) async => warmed.add(page));
      activity.ping();
      await tester.pump();
      expect(
        logs.where((line) => line.contains('thumbnail warm yields')).length,
        2,
      );
    });

    testWidgets('an unbound cache warms exactly as before', (tester) async {
      final cache = PdfThumbnailCache(warmIdleDelay: Duration.zero);
      addTearDown(cache.dispose);
      final warmed = <int>[];
      cache.setWarm(Object(), 2, 'k', (page) async => warmed.add(page));
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(warmed, [0, 1]);
    });

    testWidgets('withdrawing the warm releases the gate', (tester) async {
      final cache = PdfThumbnailCache(warmIdleDelay: Duration.zero);
      addTearDown(cache.dispose);
      final activity = _TestActivity();
      final owner = Object();
      cache.bindForegroundGate(activity, () => true);
      cache.setWarm(owner, 2, 'k', (page) async {});
      expect(activity.listeners, 1);
      cache.clearWarm(owner);
      expect(activity.listeners, 0,
          reason: 'a disposed panel must not keep the viewer subscribed');
    });

    testWidgets('navigation focus restarts the thumbnail warm quiet period',
        (tester) async {
      final cache =
          PdfThumbnailCache(warmIdleDelay: const Duration(milliseconds: 750));
      addTearDown(cache.dispose);
      final warmed = <int>[];
      cache.setWarm(Object(), 3, 'k', (page) async => warmed.add(page));

      await tester.pump(const Duration(milliseconds: 500));
      cache.focus = 2;
      await tester.pump(const Duration(milliseconds: 500));
      expect(warmed, isEmpty,
          reason: 'the destination page still owns the platform thread');

      await tester.pump(const Duration(milliseconds: 251));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(warmed, [2, 1, 0]);
    });
  });

  group('PdfThumbnailCache raster store', () {
    Future<ui.Image> solid(int w, int h) {
      final px = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
      final c = Completer<ui.Image>();
      ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
      return c.future;
    }

    test('put/claim hands out clones; clear disposes the masters', () async {
      final cache = PdfThumbnailCache();
      addTearDown(cache.dispose);
      cache.put('a', await solid(4, 4));
      expect(cache.contains('a'), isTrue);
      final clone = cache.claim('a');
      expect(clone, isNotNull);
      clone!.dispose(); // disposing the clone must not affect the master
      expect(cache.claim('a'), isNotNull);
      cache.clear();
      expect(cache.contains('a'), isFalse);
    });

    test('a raster arriving after dispose is dropped, not cached', () async {
      final cache = PdfThumbnailCache();
      cache.dispose();
      // A warm render completing after the session went away: put disposes the
      // orphan raster and caches nothing.
      cache.put('late', await solid(4, 4));
      expect(cache.contains('late'), isFalse);
      expect(cache.claim('late'), isNull);
    });
  });

  group('background thumbnail warm', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PdfThumbnailSidebar.debugRasterizations = 0;
    });

    testWidgets('the strip warms off-screen pages into the shared cache',
        (tester) async {
      // a tall document in a short viewport: the lazy strip builds only the
      // first few tiles, so the rest can rasterize only via the warm pass
      final bytes = buildMultiPagePdf(12);
      final editing = PdfEditingController(bytes);
      final viewer = PdfViewerController();
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      addTearDown(worker.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: Row(children: [
              PdfThumbnailSidebar(
                  controller: editing,
                  viewerController: viewer,
                  renderWorker: worker),
              const Expanded(child: SizedBox()),
            ]),
          ),
        ),
      ));

      // far fewer than 12 tiles fit in 240px, so without the warm pass the
      // raster count would plateau well below the page count
      expect(
        tester
            .widgetList(
                find.byKey(const ValueKey('pdf-thumbnail-tile-chip-11')))
            .isEmpty,
        isTrue,
        reason: 'page 12 should be off-screen / unbuilt',
      );
      // drive the serialized async render queue (rasterization needs runAsync)
      // and advance fake time so the idle window starts after the foreground
      // tiles have drained, just as it does between frames in the real app.
      for (var i = 0;
          i < 300 && PdfThumbnailSidebar.debugRasterizations < 12;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
      // every page rendered exactly once, even the off-screen ones
      expect(PdfThumbnailSidebar.debugRasterizations, 12);
    });

    testWidgets('a second surface over the same session reuses the cache',
        (tester) async {
      // the cache lives on the controller, so a second strip at the same tile
      // resolution draws from the rasters the first already rendered - no
      // page is interpreted twice
      final editing = PdfEditingController(buildMultiPagePdf(3));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);

      Future<void> drainTo(int target) async {
        for (var i = 0;
            i < 300 && PdfThumbnailSidebar.debugRasterizations < target;
            i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump();
        }
      }

      PdfThumbnailSidebar strip() =>
          PdfThumbnailSidebar(controller: editing, viewerController: viewer);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [strip(), const Expanded(child: SizedBox())]),
        ),
      ));
      await drainTo(3);
      expect(PdfThumbnailSidebar.debugRasterizations, 3);

      // a fresh, identically-configured strip over the same session: its
      // tiles claim from the shared cache instead of re-rendering
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            strip(),
            strip(),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(PdfThumbnailSidebar.debugRasterizations, 3);
    });

    testWidgets('a parked viewer does not gate the warm', (tester) async {
      // The full-area page grid overlays the viewer and parks it
      // (PdfViewer.active false), which holds its renders forever. Gating the
      // warm on that hold would mean the grid never fills in - so a parked
      // viewer must read idle (#603).
      final bytes = buildMultiPagePdf(4);
      final editing = PdfEditingController(bytes);
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(controller: editing, viewerController: viewer),
            Expanded(
              child: PdfViewer(
                active: false,
                document: PdfDocument.open(bytes),
                controller: viewer,
              ),
            ),
          ]),
        ),
      ));
      expect(viewer.isPageRenderBusy, isFalse);
      for (var i = 0;
          i < 300 && PdfThumbnailSidebar.debugRasterizations < 4;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(PdfThumbnailSidebar.debugRasterizations, 4);
    });
  });

  group('retained scene reuse', () {
    testWidgets('web-size tile accepts the complete 200px viewer preview',
        (tester) async {
      // 2026-08-22 field trace: replaying the viewer's 39k-command retained
      // scene for a 256px tile blocked CanvasKit for 223ms. The complete 200px
      // preview was already on screen and is close enough for the sidebar.
      final controller = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(controller.dispose);
      controller.rotatePages([0], 90); // the field page was landscape
      final previews = PdfPagePreviewCache();
      addTearDown(previews.dispose);
      final page = controller.pageAt(0);
      await tester.runAsync(() => previews.renderPreview(0, page));

      ui.Image? rendered;
      late final int tileOps;
      await tester.runAsync(() async {
        PdfPerf.enabled = true;
        addTearDown(() => PdfPerf.enabled = false);
        PdfPerf.reset();
        rendered = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          pixelWidth: 256,
          worker: null,
          previews: previews,
          allowSoftPreview: true,
        );
        tileOps = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
      });

      expect(rendered, isNotNull);
      expect(math.max(rendered!.width, rendered!.height), 200);
      expect(tileOps, 0,
          reason: 'the tile claims complete cached pixels without replaying');
      rendered!.dispose();
    });

    testWidgets('a tile replays the viewer scene instead of re-interpreting',
        (tester) async {
      // #699: with no worker a 128px tile fell through to a full page
      // interpret - for a page the viewer had walked seconds earlier and
      // still holds a retained scene for.
      final controller = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(controller.dispose);
      final previews = PdfPagePreviewCache();
      addTearDown(previews.dispose);
      final page = controller.pageAt(0);
      final plan = PdfPageRenderPlan(
        pageColor: const Color(0xFFFFFFFF),
        annotations: true,
        rotation: page.rotation,
      );

      ui.Image? rendered;
      late final int tileOps;
      await tester.runAsync(() async {
        final scene = await PdfRetainedScene.record(page, plan: plan);
        previews
            .retainScene(0, page, scene,
                plan: plan, fromWorker: false, estimatedBytes: 1 << 20)
            .dispose(); // the cache keeps its own reference
        PdfPerf.enabled = true;
        addTearDown(() => PdfPerf.enabled = false);
        PdfPerf.reset();
        rendered = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          pixelWidth: 128,
          worker: null,
          previews: previews,
        );
        tileOps = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
      });

      expect(rendered, isNotNull);
      expect(rendered!.width, 128);
      expect(tileOps, 0,
          reason: 'the tile replays retained commands - no content walk');
      rendered!.dispose();
    });

    testWidgets('an editing session\'s annotation-free scene serves a tile',
        (tester) async {
      // The viewer bakes annotations into the page picture only when it is
      // not drawing them in an overlay layer - and an editing session, which
      // is when the strip exists, always uses the overlay. On a page that
      // carries no annotations those are the same pixels.
      final controller = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(controller.dispose);
      final previews = PdfPagePreviewCache();
      addTearDown(previews.dispose);
      final page = controller.pageAt(0);
      expect(page.annotations, isEmpty);
      final plan = PdfPageRenderPlan(
        pageColor: const Color(0xFFFFFFFF),
        annotations: false,
        rotation: page.rotation,
      );

      late final int tileOps;
      ui.Image? rendered;
      await tester.runAsync(() async {
        final scene = await PdfRetainedScene.record(page, plan: plan);
        previews
            .retainScene(0, page, scene,
                plan: plan, fromWorker: false, estimatedBytes: 1 << 20)
            .dispose();
        PdfPerf.enabled = true;
        addTearDown(() => PdfPerf.enabled = false);
        PdfPerf.reset();
        rendered = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          pixelWidth: 128,
          worker: null,
          previews: previews,
        );
        tileOps = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
      });

      expect(rendered, isNotNull);
      expect(tileOps, 0);
      rendered!.dispose();
    });

    testWidgets('an annotated page will not take an annotation-free scene',
        (tester) async {
      final controller = PdfEditingController(buildAnnotatedPdf());
      addTearDown(controller.dispose);
      final previews = PdfPagePreviewCache();
      addTearDown(previews.dispose);
      final page = controller.pageAt(0);
      expect(page.annotations, isNotEmpty);
      final plan = PdfPageRenderPlan(
        pageColor: const Color(0xFFFFFFFF),
        annotations: false,
        rotation: page.rotation,
      );

      late final int tileOps;
      ui.Image? rendered;
      await tester.runAsync(() async {
        final scene = await PdfRetainedScene.record(page, plan: plan);
        previews
            .retainScene(0, page, scene,
                plan: plan, fromWorker: false, estimatedBytes: 1 << 20)
            .dispose();
        PdfPerf.enabled = true;
        addTearDown(() => PdfPerf.enabled = false);
        PdfPerf.reset();
        rendered = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          pixelWidth: 128,
          worker: null,
          previews: previews,
        );
        tileOps = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
      });

      expect(rendered, isNotNull);
      expect(tileOps, greaterThan(0),
          reason: 'the tile must draw the annotations the scene omits');
      rendered!.dispose();
    });

    testWidgets('a scene recorded for another display is not reused',
        (tester) async {
      final controller = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(controller.dispose);
      final previews = PdfPagePreviewCache();
      addTearDown(previews.dispose);
      final page = controller.pageAt(0);
      // A grey-paper scene cannot stand in for a white-paper tile.
      final plan = PdfPageRenderPlan(
        pageColor: const Color(0xFF808080),
        annotations: true,
        rotation: page.rotation,
      );

      late final int tileOps;
      ui.Image? rendered;
      await tester.runAsync(() async {
        final scene = await PdfRetainedScene.record(page, plan: plan);
        previews
            .retainScene(0, page, scene,
                plan: plan, fromWorker: false, estimatedBytes: 1 << 20)
            .dispose();
        PdfPerf.enabled = true;
        addTearDown(() => PdfPerf.enabled = false);
        PdfPerf.reset();
        rendered = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          pixelWidth: 128,
          worker: null,
          previews: previews,
        );
        tileOps = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
      });

      expect(rendered, isNotNull);
      expect(tileOps, greaterThan(0),
          reason: 'the mismatched scene is declined and the tile renders '
              'the page itself');
      rendered!.dispose();
    });

    testWidgets('a plan spelling rotation as null still serves a tile',
        (tester) async {
      // Null means "the page's own /Rotate", so it is the same render as a
      // plan carrying that angle. The viewer always resolves an explicit
      // angle; a bare PdfPageView may not.
      final controller = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(controller.dispose);
      final previews = PdfPagePreviewCache();
      addTearDown(previews.dispose);
      final page = controller.pageAt(0);
      const plan = PdfPageRenderPlan(
        pageColor: Color(0xFFFFFFFF),
        annotations: true,
      );

      late final int tileOps;
      ui.Image? rendered;
      await tester.runAsync(() async {
        final scene = await PdfRetainedScene.record(page, plan: plan);
        previews
            .retainScene(0, page, scene,
                plan: plan, fromWorker: false, estimatedBytes: 1 << 20)
            .dispose();
        PdfPerf.enabled = true;
        addTearDown(() => PdfPerf.enabled = false);
        PdfPerf.reset();
        rendered = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          pixelWidth: 128,
          worker: null,
          previews: previews,
        );
        tileOps = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
      });

      expect(rendered, isNotNull);
      expect(tileOps, 0);
      rendered!.dispose();
    });

    testWidgets('a scene decoded below the tile ratio is declined',
        (tester) async {
      // Replaying it would draw the page's images softer than a fresh render
      // would. A tile ratio is a fraction of any display ratio, so this is a
      // guard rather than a case the viewer produces.
      final controller = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(controller.dispose);
      final previews = PdfPagePreviewCache();
      addTearDown(previews.dispose);
      final page = controller.pageAt(0);
      final plan = PdfPageRenderPlan(
        pageColor: const Color(0xFFFFFFFF),
        annotations: true,
        rotation: page.rotation,
      );

      late final int tileOps;
      ui.Image? rendered;
      await tester.runAsync(() async {
        final scene = await PdfRetainedScene.record(page, plan: plan);
        previews
            .retainScene(0, page, scene,
                plan: plan,
                fromWorker: false,
                imagePixelRatio: 0.001,
                estimatedBytes: 1 << 20)
            .dispose();
        PdfPerf.enabled = true;
        addTearDown(() => PdfPerf.enabled = false);
        PdfPerf.reset();
        rendered = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          pixelWidth: 128,
          worker: null,
          previews: previews,
        );
        tileOps = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
      });

      expect(rendered, isNotNull);
      expect(tileOps, greaterThan(0),
          reason: 'the tile renders the page rather than replaying a scene '
              'whose images are softer than it needs');
      rendered!.dispose();
    });

    testWidgets('the warm pass reuses a retained scene without a worker',
        (tester) async {
      final controller = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(controller.dispose);
      final previews = PdfPagePreviewCache();
      addTearDown(previews.dispose);
      final page = controller.pageAt(0);
      final plan = PdfPageRenderPlan(
        pageColor: const Color(0xFFFFFFFF),
        annotations: true,
        rotation: page.rotation,
      );

      ui.Image? rendered;
      await tester.runAsync(() async {
        final scene = await PdfRetainedScene.record(page, plan: plan);
        previews
            .retainScene(0, page, scene,
                plan: plan, fromWorker: false, estimatedBytes: 1 << 20)
            .dispose();
        rendered = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          pixelWidth: 128,
          worker: null,
          skipIfWorkerDeclines: true,
          reason: 'warm',
          previews: previews,
        );
      });

      expect(rendered, isNotNull,
          reason: 'skipping the local interpret does not mean skipping a '
              'scene that is already recorded');
      rendered!.dispose();
    });

    testWidgets('a retained scene is not replayed during motion',
        (tester) async {
      final controller = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(controller.dispose);
      final previews = PdfPagePreviewCache();
      addTearDown(previews.dispose);
      final page = controller.pageAt(0);
      final plan = PdfPageRenderPlan(
        pageColor: const Color(0xFFFFFFFF),
        annotations: true,
        rotation: page.rotation,
      );

      ui.Image? rendered;
      await tester.runAsync(() async {
        final scene = await PdfRetainedScene.record(page, plan: plan);
        previews
            .retainScene(0, page, scene,
                plan: plan, fromWorker: false, estimatedBytes: 1 << 20)
            .dispose();
        rendered = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          pixelWidth: 128,
          worker: null,
          deferUiWork: () => true,
          previews: previews,
        );
      });

      expect(rendered, isNull,
          reason: 'a replay is cheap but still platform-thread work; the '
              'tile waits for the scroll to settle');
    });
  });

  group('page reorder (#1025)', () {
    const white = Color(0xFFFFFFFF);
    String key(PdfEditingController c, int i) =>
        thumbnailKey(c, i, white, true, 128);

    test('a moved page carries its thumbnail key; its old slot does not', () {
      final controller = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(controller.dispose);
      final before = [for (var i = 0; i < 4; i++) key(controller, i)];
      expect(before.toSet(), hasLength(4),
          reason: 'every page has its own key');

      // the issue's gesture: page 3 dragged to position 2
      controller.movePage(2, 1);

      // a reorder bumps no render stamps - every page still renders the same -
      // so the key must follow the page, not the slot, or slot 1 keeps showing
      // the raster of the page that used to be there
      expect([for (var i = 0; i < 4; i++) key(controller, i)],
          [before[0], before[2], before[1], before[3]]);

      controller.undo();
      expect([for (var i = 0; i < 4; i++) key(controller, i)], before);
    });

    test('a reorder closes the index-keyed disk tier', () {
      final controller = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(controller.dispose);
      expect(controller.pageMatchesOpenedFile(0), isTrue);
      expect(controller.pageMatchesOpenedFile(2), isTrue);

      controller.movePage(0, 2);
      // the disk thumbnail for index 0 is the opened file's page 1, not the
      // page now there - even though no page's render stamp moved
      for (var i = 0; i < 3; i++) {
        expect(controller.pageRenderStamp(i), 0);
        expect(controller.pageMatchesOpenedFile(i), isFalse);
      }
    });
  });

  group('thumbnail disk persistence', () {
    testWidgets('warm render skips local fallback without an active worker',
        (tester) async {
      final controller = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(controller.dispose);

      ui.Image? rendered;
      await tester.runAsync(() async {
        rendered = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          pixelWidth: 128,
          worker: null,
          skipIfWorkerDeclines: true,
          reason: 'warm',
        );
      });

      expect(rendered, isNull);
    });

    testWidgets('a warm worker result defers its UI replay during motion',
        (tester) async {
      final bytes = buildMultiPagePdf(1);
      final controller = PdfEditingController(bytes);
      final worker = _ImmediateWorker();
      addTearDown(controller.dispose);
      addTearDown(worker.dispose);

      ui.Image? rendered;
      await tester.runAsync(() async {
        rendered = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          pixelWidth: 128,
          worker: worker,
          deferUiWork: () => true,
          reason: 'warm',
        );
      });

      expect(rendered, isNull,
          reason: 'a worker reply must not start CanvasKit replay/raster '
              'after the viewer begins scrolling');
    });

    testWidgets('a declined worker defers the local fallback during motion',
        (tester) async {
      final controller = PdfEditingController(buildMultiPagePdf(1));
      final worker = _DecliningWorker();
      addTearDown(controller.dispose);
      addTearDown(worker.dispose);

      ui.Image? rendered;
      await tester.runAsync(() async {
        rendered = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          pixelWidth: 128,
          worker: worker,
          deferUiWork: () => true,
        );
      });

      expect(rendered, isNull,
          reason: 'a declined worker must not trigger a UI-thread interpret '
              'while the viewer is moving');
    });

    testWidgets('a rendered thumbnail writes through to disk and reloads',
        (tester) async {
      final store = PdfMemoryCacheStore();
      final disk = PdfRasterCache(PdfDiskCache(store)).forDocument('doc-thumb');
      final controller = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(controller.dispose);
      const white = Color(0xFFFFFFFF);
      const blue = Color(0xFFBBD7FF);

      // render page 0 with a disk cache → writes the raster through
      ui.Image? rendered;
      await tester.runAsync(() async {
        rendered = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: white,
          annotations: true,
          pixelWidth: 128,
          worker: null,
          disk: disk,
        );
        // storeThumbnail is fire-and-forget - let the PNG encode + write land
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(rendered, isNotNull);
      rendered!.dispose();

      // the PNG is on disk, only at the bucket it rendered at
      await tester.runAsync(() async {
        final loaded = await disk.loadThumbnail(0, 128);
        expect(loaded, isNotNull);
        loaded!.dispose();
        expect(await disk.loadThumbnail(0, 256), isNull); // different size
        expect(await disk.loadThumbnail(1, 128), isNull); // never rendered
        expect(await disk.loadThumbnail(0, 128, pageColor: blue.toARGB32()),
            isNull,
            reason: 'paper color is part of the persisted thumbnail key');
        expect(await disk.loadThumbnail(0, 128, annotations: false), isNull,
            reason: 'annotation visibility is part of the persisted key');
      });
      expect(store.debugBytes, greaterThan(0));

      // a later render of the same page+size comes straight back from disk
      ui.Image? fromDisk;
      await tester.runAsync(() async {
        fromDisk = await rasterizeThumbnail(
          controller: controller,
          pageIndex: 0,
          pageColor: white,
          annotations: true,
          pixelWidth: 128,
          worker: null,
          disk: disk,
        );
      });
      expect(fromDisk, isNotNull);
      fromDisk!.dispose();
    });
  });
}

/// A [Listenable] whose subscriptions are observable - the gate must let go of
/// the viewer when its panel does, or a disposed strip keeps waking the warm.
class _TestActivity implements Listenable {
  final _callbacks = <VoidCallback>[];

  int get listeners => _callbacks.length;

  @override
  void addListener(VoidCallback listener) => _callbacks.add(listener);

  @override
  void removeListener(VoidCallback listener) => _callbacks.remove(listener);

  void ping() {
    for (final callback in List<VoidCallback>.of(_callbacks)) {
      callback();
    }
  }
}

/// Deterministic worker seam for the UI-deferral test: a non-null command
/// buffer proves rasterizeThumbnail reached the worker-result branch without
/// spawning an isolate whose lifetime can outlive flutter_test's fake clock.
class _ImmediateWorker extends PdfRenderWorker {
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  Future<List<PdfRenderCommand>?> record(
    int pageIndex, {
    bool annotations = true,
    Set<String> hiddenAnnotationSubtypes = const {},
    int priority = 0,
    double? imagePixelRatio,
    bool decodeImages = true,
    int? commandLimit,
    PdfRect? imageDecodeRegion,
    PdfPartialRecordSink? onPartial,
  }) async =>
      [PdfSaveCommand(), PdfRestoreCommand()];

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() => _active = false;
}

class _HeldFirstWorker extends PdfRenderWorker {
  bool _active = true;
  final firstStarted = Completer<void>();
  final _firstRelease = Completer<void>();
  int calls = 0;

  @override
  bool get isActive => _active;

  void releaseFirst() {
    if (!_firstRelease.isCompleted) _firstRelease.complete();
  }

  @override
  Future<List<PdfRenderCommand>?> record(
    int pageIndex, {
    bool annotations = true,
    Set<String> hiddenAnnotationSubtypes = const {},
    int priority = 0,
    double? imagePixelRatio,
    bool decodeImages = true,
    int? commandLimit,
    PdfRect? imageDecodeRegion,
    PdfPartialRecordSink? onPartial,
  }) async {
    calls++;
    if (calls == 1) {
      firstStarted.complete();
      await _firstRelease.future;
    }
    return [PdfSaveCommand(), PdfRestoreCommand()];
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {
    _active = false;
    releaseFirst();
  }
}

class _DecliningWorker extends PdfRenderWorker {
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  Future<List<PdfRenderCommand>?> record(
    int pageIndex, {
    bool annotations = true,
    Set<String> hiddenAnnotationSubtypes = const {},
    int priority = 0,
    double? imagePixelRatio,
    bool decodeImages = true,
    int? commandLimit,
    PdfRect? imageDecodeRegion,
    PdfPartialRecordSink? onPartial,
  }) async =>
      null;

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() => _active = false;
}
