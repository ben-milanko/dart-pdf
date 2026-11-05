// The background-work coordinator against a fake viewer, a fake scheduler
// and a fake clock: when each lane runs, what it picks first, and what stops
// or re-arms it. No widgets.

import 'dart:async';
import 'dart:ui' show Color;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/background_work.dart';
import 'package:dart_pdf_editor/src/page_set.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

class _FakeScheduler implements PdfBackgroundScheduler {
  @override
  bool holding = false;
  @override
  bool activeGesture = false;
  @override
  bool slowMotion = false;
  @override
  bool parked = false;
  int? focused;
  @override
  set focus(int index) => focused = index;
  @override
  bool busy = false;
  @override
  bool hasForegroundWork = false;
}

class _WarmUpBackend extends PdfCanvasTileRasterBackend {
  int warmUps = 0;
  @override
  bool get supportsWarmUp => true;
  @override
  Future<void> warmUp() async => warmUps++;
}

class _FakeHost implements PdfBackgroundHost {
  _FakeHost(this.pages);

  @override
  bool mounted = true;
  @override
  bool active = true;
  @override
  bool pagePreviews = true;
  @override
  PdfPageRasterWarmPolicy rasterWarmPolicy =
      const PdfPageRasterWarmPolicy.document();
  @override
  Duration previewIdleDelay = Duration.zero;
  @override
  bool directGesture = false;
  @override
  bool scrollSettling = false;
  @override
  bool zoomSettling = false;
  @override
  bool deepZoom = false;
  @override
  bool toolArmed = false;
  @override
  List<PdfPage> pages;
  @override
  int currentPage = 0;

  /// Pages in or around the build window.
  Set<int> near = {0, 1};
  Set<int> visible = {0};
  bool laidOut = true;

  @override
  bool Function(int index)? nearViewport() => laidOut ? near.contains : null;
  @override
  bool onScreen(int index) => visible.contains(index);

  @override
  PdfPagePreviewLodPolicy previewLodPolicy = const PdfPagePreviewLodPolicy();
  @override
  List<double> intermediateLongestSides = const [400];
  int window = 0;
  @override
  int previewWindow({required bool requireImages}) => window;
  final Set<int> fresh = {};
  final Set<int> anyPreview = {};
  @override
  bool previewFresh(int index,
          {required bool requireImages, double? targetLongestSide}) =>
      fresh.contains(index);
  @override
  bool hasPreview(int index) => anyPreview.contains(index);

  @override
  PdfRasterWarmTarget? rasterWarmTarget(int index) => (
        ratio: 1.0,
        signature: PdfPageRasterSignature(
          pageIndex: index,
          width: 100,
          height: 100,
          pageColor: const Color(0xFFFFFFFF),
          annotations: true,
          rotation: 0,
        ),
      );

  final Set<int> stored = {};
  @override
  bool hasFullRaster(int index, PdfPageRasterSignature signature) =>
      stored.contains(index);
  @override
  int maxFullRasterBytes = 1 << 30;
  @override
  int maxFullRasterEntryBytes = 1 << 26;

  /// Every warm request, in order, as (page, priority, accelerated).
  final warms = <(int, int, bool)>[];

  /// When set, a warm waits on this instead of completing at once.
  Completer<bool>? hold;
  bool Function()? lastShouldStop;

  @override
  Future<bool> warmFullRaster(
    int index,
    PdfRasterWarmTarget target, {
    required int priority,
    required bool Function() shouldStop,
    bool acceleratedOnly = false,
  }) async {
    warms.add((index, priority, acceleratedOnly));
    lastShouldStop = shouldStop;
    final pending = hold;
    final done = pending == null ? true : await pending.future;
    if (done) stored.add(index);
    return done;
  }

  @override
  bool slowScrollWarmCapable = true;

  int previewPasses = 0;
  @override
  void runPreviewPass() => previewPasses++;

  @override
  bool textWarmWanted = false;
  int textWarms = 0;
  @override
  Future<void>? runTextWarm() {
    textWarms++;
    return Future<void>.value();
  }

  @override
  PdfTileRasterBackend tileBackend = PdfCanvasTileRasterBackend();

  @override
  void postFrame(VoidCallback callback) => scheduleMicrotask(callback);
  @override
  Future<void> get endOfFrame => Future<void>.value();
}

void main() {
  final document = PdfDocument.open(buildMultiPagePdf(8));
  late _FakeHost host;
  late _FakeScheduler scheduler;
  late PdfBackgroundWork work;

  setUp(() {
    host = _FakeHost(document.pages);
    scheduler = _FakeScheduler();
    work = PdfBackgroundWork(host: host, scheduler: scheduler);
  });
  tearDown(() => work.dispose());

  List<int> warmedPages() => [for (final w in host.warms) w.$1];
  const idle = Duration(milliseconds: 750);

  group('idle', () {
    test('every clause of the raster-warm idle answer blocks it', () {
      expect(work.rasterWarmIdle, isTrue);
      void blocks(String what, void Function(bool) set) {
        set(true);
        expect(work.rasterWarmIdle, isFalse, reason: what);
        set(false);
        expect(work.rasterWarmIdle, isTrue, reason: what);
      }

      blocks('scheduler busy', (v) => scheduler.busy = v);
      blocks('direct gesture', (v) => host.directGesture = v);
      blocks('scroll settling', (v) => host.scrollSettling = v);
      blocks('zoom settling', (v) => host.zoomSettling = v);
      blocks('deep zoom', (v) => host.deepZoom = v);
      blocks('armed tool', (v) => host.toolArmed = v);
      blocks('parked', (v) => host.active = !v);
      blocks('no previews', (v) => host.pagePreviews = !v);
    });

    test('lanes share facts but answer for themselves', () {
      host.deepZoom = true;
      host.toolArmed = true;
      expect(work.rasterWarmIdle, isFalse);
      expect(work.textWarmIdle, isTrue,
          reason: 'text warm runs at any zoom and with a tool armed');
      expect(work.commandWarmUiIdle, isTrue);

      host.scrollSettling = true;
      expect(work.motionHold, isTrue);
      expect(work.previewUiMustDefer, isFalse,
          reason: 'a list scroll lets the vector preview through');
      host.directGesture = true;
      expect(work.previewUiMustDefer, isFalse);
      host.scrollSettling = false;
      expect(work.previewUiMustDefer, isTrue);
    });
  });

  group('raster warm', () {
    test('after settle plus idle, warms nearest pages first', () {
      fakeAsync((clock) {
        host.currentPage = 0;
        work.scheduleRasterWarm();
        clock.elapse(idle - const Duration(milliseconds: 1));
        expect(host.warms, isEmpty, reason: 'still inside the idle delay');
        clock.elapse(const Duration(milliseconds: 1));
        clock.flushMicrotasks();
        expect(warmedPages(), [2, 3, 4, 5, 6, 7],
            reason: 'near pages render on their own; page 3 before page 5');
        expect(host.warms.first.$2, PdfBackgroundWork.rasterWarmWorkerPriority);
        expect(work.warmingRasters, isFalse);
      });
    });

    test('nearby policy aims both ways from the current page', () {
      fakeAsync((clock) {
        host
          ..rasterWarmPolicy = const PdfPageRasterWarmPolicy.nearby(window: 2)
          ..currentPage = 4
          ..near = {4};
        work.scheduleRasterWarm();
        clock.elapse(idle);
        clock.flushMicrotasks();
        expect(warmedPages(), [3, 5, 2, 6],
            reason: 'nearest first; a tie goes to the earlier page');
      });
    });

    test('any activity restarts the idle countdown', () {
      fakeAsync((clock) {
        work.scheduleRasterWarm();
        clock.elapse(const Duration(milliseconds: 500));
        work.schedulerActivity();
        clock.elapse(const Duration(milliseconds: 500));
        expect(host.warms, isEmpty);
        clock.elapse(const Duration(milliseconds: 250));
        clock.flushMicrotasks();
        expect(host.warms, isNotEmpty);
      });
    });

    test('a scroll start cancels it and the page is retried after settle', () {
      fakeAsync((clock) {
        host.hold = Completer<bool>();
        work.scheduleRasterWarm();
        clock.elapse(idle);
        clock.flushMicrotasks();
        expect(warmedPages(), [2]);
        expect(work.warmingRasters, isTrue);

        // a scroll starts: the warm's mid-render abort sees it
        host.scrollSettling = true;
        work.beginMotion();
        expect(scheduler.holding, isTrue);
        expect(host.lastShouldStop!(), isTrue);
        host.hold!.complete(false);
        clock.flushMicrotasks();
        expect(work.warmingRasters, isFalse);
        expect(work.rasterWarmAttempts, isEmpty,
            reason: 'a preempted page is not written off');

        // settle: the scroll window closes and the countdown restarts
        host
          ..hold = null
          ..scrollSettling = false;
        work.settleAfterBuild();
        clock.flushMicrotasks();
        expect(scheduler.holding, isFalse);
        clock.elapse(idle);
        clock.flushMicrotasks();
        expect(warmedPages(), [2, 2, 3, 4, 5, 6, 7]);
      });
    });

    test('a page-colour invalidation re-arms everything', () {
      fakeAsync((clock) {
        work.scheduleRasterWarm();
        clock.elapse(idle);
        clock.flushMicrotasks();
        expect(warmedPages(), hasLength(6));
        work.commandWarmAttempts.add(host.pages[3]);
        work.previewAttempts.add(host.pages[4]);
        work.commandHeavyWarmStarted = true;
        final commandGeneration = work.commandWarmGeneration;

        // the new paper colour is a new raster signature for every page
        host.stored.clear();
        work.invalidate(PdfPageSet.load(document).repainted());
        expect(work.rasterWarmAttempts, isEmpty);
        expect(work.commandWarmAttempts, isEmpty);
        expect(work.previewAttempts, isEmpty);
        expect(work.commandHeavyWarmStarted, isFalse);
        expect(work.commandWarmGeneration, greaterThan(commandGeneration));
        clock.flushMicrotasks();
        expect(host.previewPasses, 1, reason: 'previews re-arm too');
        clock.elapse(idle);
        clock.flushMicrotasks();
        expect(warmedPages(), hasLength(12));
      });
    });

    test('an annotation edit re-arms only its page', () {
      fakeAsync((clock) {
        final editing = PdfEditingController(buildMultiPagePdf(8));
        addTearDown(editing.dispose);
        final set = PdfPageSet.load(editing.document);
        host.pages = set.pages;
        work.scheduleRasterWarm();
        clock.elapse(idle);
        clock.flushMicrotasks();
        expect(work.rasterWarmAttempts, hasLength(6));

        editing.addRectangle(5, const PdfRect(10, 10, 20, 20));
        final change = set.reconcile(editing.document,
            sameLineage: true, impact: editing.lastRevisionImpact);
        work.invalidate(change);
        host
          ..pages = change.next.pages
          ..stored.remove(5);
        expect(work.rasterWarmAttempts, hasLength(5));
        expect(work.rasterWarmAttempts.contains(set.pages[5]), isFalse);
        clock.elapse(idle);
        clock.flushMicrotasks();
        expect(warmedPages().skip(6), [5]);
      });
    });

    test('a disabled policy warms nothing, even asked directly', () {
      fakeAsync((clock) {
        host.rasterWarmPolicy = const PdfPageRasterWarmPolicy.disabled();
        work.scheduleRasterWarm();
        clock.elapse(const Duration(seconds: 5));
        unawaited(work.warmFullRasters());
        clock.flushMicrotasks();
        expect(host.warms, isEmpty);
        expect(work.warmingRasters, isFalse);
      });
    });

    test('a warm policy change re-offers every page', () {
      fakeAsync((clock) {
        work.scheduleRasterWarm();
        clock.elapse(idle);
        clock.flushMicrotasks();
        expect(work.rasterWarmAttempts, hasLength(6));
        final generation = work.slowScrollGeneration;
        host
          ..rasterWarmPolicy = const PdfPageRasterWarmPolicy.nearby(window: 3)
          ..stored.clear();
        work.rasterWarmPolicyChanged();
        expect(work.rasterWarmAttempts, isEmpty);
        expect(work.slowScrollGeneration, greaterThan(generation));
        clock.elapse(idle);
        clock.flushMicrotasks();
        expect(warmedPages().skip(6), [2, 3]);
      });
    });

    test('a lowered cache budget does not re-offer the document', () {
      fakeAsync((clock) {
        work.scheduleRasterWarm();
        clock.elapse(idle);
        clock.flushMicrotasks();
        work.rasterCachePolicyChanged(raised: false);
        expect(work.rasterWarmAttempts, hasLength(6));
        work.rasterCachePolicyChanged(raised: true);
        expect(work.rasterWarmAttempts, isEmpty);
      });
    });

    test('nothing warms before layout or while parked', () {
      fakeAsync((clock) {
        host.laidOut = false;
        work.scheduleRasterWarm();
        clock.elapse(idle);
        clock.flushMicrotasks();
        expect(host.warms, isEmpty);

        host
          ..laidOut = true
          ..active = false;
        work.activeChanged();
        expect(scheduler.parked, isTrue);
        expect(scheduler.holding, isTrue);
        clock.elapse(idle);
        clock.flushMicrotasks();
        expect(host.warms, isEmpty);

        host.active = true;
        work.activeChanged();
        expect(scheduler.parked, isFalse);
        expect(scheduler.holding, isFalse);
        clock.elapse(idle);
        clock.flushMicrotasks();
        expect(host.warms, isNotEmpty);
      });
    });
  });

  group('preview pass', () {
    test('picks the nearest page off the build window, once', () {
      host
        ..currentPage = 3
        ..near = {2, 3, 4}
        ..fresh.add(5);
      int? next() =>
          work.nextPreviewPage(requireImages: true, allowNearViewport: false);
      expect(next(), 1, reason: 'page 5 is fresh, so page 1 is nearest');
      work.previewAttempts.add(host.pages[1]);
      expect(next(), 0, reason: 'a tie goes to the earlier page');
      host.window = 2;
      expect(next(), isNull, reason: 'outside the preview window');
      expect(work.nextPreviewPage(requireImages: true, allowNearViewport: true),
          3);
    });

    test('a motion preview only fills a blank neighbour', () {
      host
        ..near = {0}
        ..anyPreview.add(1);
      expect(
          work.nextPreviewPage(
              requireImages: false,
              allowNearViewport: false,
              maxDistance: 1,
              blankOnly: true),
          isNull,
          reason: 'page 1 has a stale preview to paint');
      host.anyPreview.clear();
      expect(
          work.nextPreviewPage(
              requireImages: false,
              allowNearViewport: false,
              maxDistance: 1,
              blankOnly: true),
          1);
    });

    test('before layout every page counts as near', () {
      host.laidOut = false;
      expect(
          work.nextPreviewPage(requireImages: true, allowNearViewport: false),
          isNull);
    });

    test('an intermediate rung needs the LoD window', () {
      host.near = {0};
      expect(
          work.nextPreviewPage(
              requireImages: true,
              allowNearViewport: false,
              targetLongestSide: 999),
          isNull,
          reason: 'not a rung of this ladder');
    });
  });

  group('command warm', () {
    test('plans neighbours, forward first, and the heavy tail once', () {
      host.currentPage = 3;
      final first = work.planCommandWarm(3, radius: 2, heavyCount: 1);
      expect(work.commandWarmAnchor, 3);
      expect(first.indices.toSet().containsAll([4, 5, 2, 1]), isTrue);
      expect(first.indices.indexOf(4), lessThan(first.indices.indexOf(2)));
      expect(first.indices, hasLength(5),
          reason: 'one heavy page joins the four neighbours');
      expect(work.commandHeavyWarmStarted, isTrue);
      final second = work.planCommandWarm(3, radius: 2, heavyCount: 1);
      expect(second.generation, greaterThan(first.generation));
      expect(second.indices, [4, 5, 2, 1],
          reason: 'the heavy tail is offered once per document');
      work.invalidate(PdfPageSet.load(document).repainted());
      expect(work.commandHeavyWarmStarted, isFalse);
    });
  });

  group('slow-scroll warm', () {
    test('warms ahead in the scroll direction, skipping on-screen pages', () {
      fakeAsync((clock) {
        host
          ..currentPage = 2
          ..visible = {2, 3};
        work.slowScroll(true, direction: 1);
        expect(scheduler.slowMotion, isTrue);
        work.startSlowScrollWarm();
        clock.flushMicrotasks();
        expect(host.warms, [(4, 2, true), (5, 2, true)],
            reason: 'slowScrollWindow 3 from page 2, page 3 on screen');
      });
    });

    test('a reversal or settle closes the lane', () {
      fakeAsync((clock) {
        host.hold = Completer<bool>();
        work.slowScroll(true, direction: 1);
        work.startSlowScrollWarm();
        clock.flushMicrotasks();
        expect(work.warmingSlowScrollRasters, isTrue);
        final generation = work.slowScrollGeneration;
        work.slowScroll(true, direction: -1);
        expect(work.slowScrollGeneration, greaterThan(generation));
        expect(host.lastShouldStop!(), isTrue);
        host.hold!.complete(false);
        clock.flushMicrotasks();
        expect(work.warmingSlowScrollRasters, isFalse);
        expect(work.slowScrollRasterWarmAttempts, isEmpty);

        work.scrollSettled();
        expect(scheduler.slowMotion, isFalse);
        expect(work.slowScrollDirection, 0);
      });
    });

    test('needs spare accelerated capacity', () {
      fakeAsync((clock) {
        host.slowScrollWarmCapable = false;
        work.slowScroll(true, direction: 1);
        work.startSlowScrollWarm();
        clock.flushMicrotasks();
        expect(host.warms, isEmpty);
      });
    });
  });

  group('motion hold', () {
    test('a direct gesture holds through its release window', () {
      fakeAsync((clock) {
        host.directGesture = true;
        work.beginMotion();
        expect(scheduler.holding, isTrue);
        host.directGesture = false;
        work.endMotionSoon();
        expect(work.directMotion, isTrue, reason: 'release window open');
        clock.elapse(const Duration(milliseconds: 249));
        expect(scheduler.holding, isTrue);
        clock.elapse(const Duration(milliseconds: 1));
        expect(work.directMotion, isFalse);
        expect(scheduler.holding, isFalse);
        clock.flushMicrotasks();
        expect(host.previewPasses, 1, reason: 'released: previews resume');
      });
    });

    test('scroll input is a gesture until it has been quiet two frames', () {
      fakeAsync((clock) {
        work.markScrollGesture();
        expect(scheduler.activeGesture, isTrue);
        clock.elapse(const Duration(milliseconds: 100));
        work.markScrollGesture();
        clock.elapse(const Duration(milliseconds: 100));
        expect(scheduler.activeGesture, isTrue);
        clock.elapse(const Duration(milliseconds: 20));
        expect(scheduler.activeGesture, isFalse);
      });
    });

    test('a paused viewer holds whatever the scroll says', () {
      host.active = false;
      work.holdForScroll(false);
      expect(scheduler.holding, isTrue);
      host.active = true;
      work.holdForScroll(false);
      expect(scheduler.holding, isFalse);
    });

    test('motion cancels a pending preview pass', () {
      fakeAsync((clock) {
        host.previewIdleDelay = const Duration(seconds: 1);
        work.schedulePreviews();
        clock.flushMicrotasks();
        work.beginMotion();
        clock.elapse(const Duration(seconds: 2));
        expect(host.previewPasses, 0);
      });
    });
  });

  group('text and tile lanes', () {
    test('text warm waits out a quiet viewport', () {
      fakeAsync((clock) {
        host.textWarmWanted = true;
        work.scheduleTextWarm();
        clock.elapse(const Duration(milliseconds: 400));
        work.beginMotion();
        clock.elapse(const Duration(seconds: 1));
        expect(host.textWarms, 0, reason: 'motion cancelled it');
        work.scheduleTextWarm();
        clock.elapse(PdfBackgroundWork.textWarmIdleDelay);
        clock.flushMicrotasks();
        expect(host.textWarms, 1);
      });
    });

    test('tile warm-up waits for an idle scheduler', () {
      fakeAsync((clock) {
        final backend = _WarmUpBackend();
        host.tileBackend = backend;
        scheduler.busy = true;
        work.scheduleTileWarmUp();
        clock.flushMicrotasks();
        clock.elapse(PdfBackgroundWork.tileWarmUpIdleDelay);
        expect(backend.warmUps, 0);
        scheduler.busy = false;
        work.schedulerActivity();
        clock.flushMicrotasks();
        clock.elapse(PdfBackgroundWork.tileWarmUpIdleDelay);
        clock.flushMicrotasks();
        expect(backend.warmUps, 1);
        expect(work.tileWarmUpPending, isFalse);
      });
    });
  });
}
