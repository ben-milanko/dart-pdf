import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/thumbnail_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
