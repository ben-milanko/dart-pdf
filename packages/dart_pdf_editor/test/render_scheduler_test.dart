// The render scheduler paces every page's first (UI-thread) interpret so
// a settling fast scroll can't fire them all in one event-loop turn - the
// burst that froze fast scrolling on iPad. These tests pin the pacing,
// the priority order, and the hold gate.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

void main() {
  testWidgets('requests drain paced - never a synchronous burst',
      (tester) async {
    final scheduler = PdfPageRenderScheduler();
    addTearDown(scheduler.dispose);
    final order = <int>[];
    scheduler.focus = 5;
    for (final i in [0, 5, 6, 9]) {
      scheduler.request('t$i', i, () => order.add(i));
    }

    // nothing runs in the turn that registered them (the old fan-out ran
    // every held page's walk right here)
    expect(order, isEmpty);

    await tester.pump();
    // exactly one engine frame, exactly one grant
    expect(order, hasLength(1));

    // the nearest-the-viewport page drains first
    expect(order.first, 5);

    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    // every page interpreted, closest-to-focus order
    expect(order, [5, 6, 9, 0]);
  });

  testWidgets('render grants use distinct engine frames', (tester) async {
    final scheduler = PdfPageRenderScheduler();
    addTearDown(scheduler.dispose);
    final frames = <int>[];
    var frame = 0;
    for (var page = 0; page < 3; page++) {
      scheduler.request('p$page', page, () => frames.add(frame));
    }

    for (var i = 0; i < 5 && frames.length < 3; i++) {
      frame++;
      await tester.pump();
    }
    expect(frames, hasLength(3));
    expect(frames.toSet(), hasLength(3),
        reason: 'at most one page render may be started per frame');
  });

  testWidgets('holding blocks grants until released', (tester) async {
    final scheduler = PdfPageRenderScheduler()..holding = true;
    addTearDown(scheduler.dispose);
    var ran = false;
    scheduler.request('a', 0, () => ran = true);

    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(ran, isFalse, reason: 'held while a fast scroll is in flight');
    expect(scheduler.hasPending, isTrue);

    scheduler.holding = false;
    for (var i = 0; i < 2; i++) {
      await tester.pump();
    }
    expect(ran, isTrue);
    expect(scheduler.hasPending, isFalse);
  });

  // ---- the motion-safe lane -------------------------------------------
  //
  // A hold is priced for a page whose interpret walk is 100-400ms of UI
  // thread. Work the caller has judged motion-safe (an off-thread record, or
  // a small already-recorded buffer) renders through the hold instead of
  // waiting the scroll out - the ~600ms "the page takes a moment to appear"
  // on a long text document.

  testWidgets('motion-safe requests are granted through a hold',
      (tester) async {
    final scheduler = PdfPageRenderScheduler()..holding = true;
    addTearDown(scheduler.dispose);
    final ran = <String>[];
    scheduler.request('held', 0, () => ran.add('held'));
    scheduler.request('safe', 1, () => ran.add('safe'),
        motion: PdfRenderMotionClass.free);

    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(ran, ['safe'],
        reason: 'the motion-safe page renders during the scroll; the other '
            'keeps its preview until the scroll settles');
    expect(scheduler.hasPending, isTrue);

    scheduler.holding = false;
    for (var i = 0; i < 2; i++) {
      await tester.pump();
    }
    expect(ran, ['safe', 'held']);
  });

  testWidgets('a hold still paces motion-safe grants one per frame',
      (tester) async {
    final scheduler = PdfPageRenderScheduler()
      ..holding = true
      ..focus = 1;
    addTearDown(scheduler.dispose);
    final frames = <int>[];
    var frame = 0;
    for (var page = 0; page < 3; page++) {
      scheduler.request('p$page', page, () => frames.add(frame),
          motion: PdfRenderMotionClass.free);
    }
    for (var i = 0; i < 4 && frames.length < 3; i++) {
      frame++;
      await tester.pump();
    }
    expect(frames, hasLength(3));
    expect(frames.toSet(), hasLength(3),
        reason: 'a fling must not queue records faster than the UI gate '
            'releases them');
  });

  testWidgets('a hold grants only around the scroll destination',
      (tester) async {
    // Pages streaming past during a fling are not where the reader is going.
    final scheduler = PdfPageRenderScheduler()
      ..holding = true
      ..focus = 10;
    addTearDown(scheduler.dispose);
    final ran = <int>[];
    for (final page in [3, 9, 10, 11, 17]) {
      scheduler.request('p$page', page, () => ran.add(page),
          motion: PdfRenderMotionClass.free);
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(ran..sort(), [9, 10, 11],
        reason: 'the destination and its neighbours, not everything flown '
            'past');

    scheduler.holding = false;
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(ran..sort(), [3, 9, 10, 11, 17],
        reason: 'the rest still render once the scroll settles');
  });

  testWidgets('a settled viewer starts several motion-safe pages per frame',
      (tester) async {
    final scheduler = PdfPageRenderScheduler();
    addTearDown(scheduler.dispose);
    final frames = <int>[];
    var frame = 0;
    for (var page = 0; page < 3; page++) {
      scheduler.request('p$page', page, () => frames.add(frame),
          motion: PdfRenderMotionClass.free);
    }
    frame++;
    await tester.pump();
    expect(frames, hasLength(PdfPageRenderScheduler.motionSafeGrantsPerFrame),
        reason: 'their walks run in the worker, so filling the window costs '
            'this frame nothing');
  });

  testWidgets('a motion-safe focus render does not park its neighbours',
      (tester) async {
    final scheduler = PdfPageRenderScheduler()..focus = 0;
    addTearDown(scheduler.dispose);
    final ran = <int>[];
    final focusRender = Completer<void>();
    scheduler.request('focus', 0, () {
      ran.add(0);
      return focusRender.future;
    }, motion: PdfRenderMotionClass.free);
    scheduler.request('next', 1, () => ran.add(1),
        motion: PdfRenderMotionClass.free);

    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(ran, [0, 1],
        reason: 'the neighbour waits behind a heavy focus walk, not behind a '
            'worker round trip');
    focusRender.complete();
  });

  testWidgets('a held focus render still parks its neighbours', (tester) async {
    final scheduler = PdfPageRenderScheduler()..focus = 0;
    addTearDown(scheduler.dispose);
    final ran = <int>[];
    final focusRender = Completer<void>();
    scheduler.request('focus', 0, () {
      ran.add(0);
      return focusRender.future;
    });
    scheduler.request('next', 1, () => ran.add(1));

    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(ran, [0], reason: 'the focused page keeps the thread to itself');
    focusRender.complete();
    await tester.pump();
    await tester.pump();
    expect(ran, [0, 1]);
  });

  testWidgets('isQueued reports work already pending or in flight',
      (tester) async {
    // A visible page with nothing to paint re-asks on every rebuild; this is
    // what keeps that ask off a render already running for it.
    final scheduler = PdfPageRenderScheduler()..holding = true;
    addTearDown(scheduler.dispose);
    expect(scheduler.isQueued('a'), isFalse);

    final running = Completer<void>();
    scheduler.request('a', 0, () => running.future,
        motion: PdfRenderMotionClass.free);
    expect(scheduler.isQueued('a'), isTrue, reason: 'queued');

    await tester.pump();
    expect(scheduler.isQueued('a'), isTrue, reason: 'granted, still running');

    running.complete();
    await tester.pump();
    await tester.pump();
    expect(scheduler.isQueued('a'), isFalse);

    scheduler.request('b', 1, () {});
    scheduler.cancel('b');
    expect(scheduler.isQueued('b'), isFalse);
  });

  testWidgets('paceUiWork releases a motion-safe replay through a hold',
      (tester) async {
    final scheduler = PdfPageRenderScheduler()..holding = true;
    addTearDown(scheduler.dispose);
    var safeReleased = false;
    var heldReleased = false;
    unawaited(scheduler
        .paceUiWork('safe', 0, motion: PdfRenderMotionClass.free)
        .then((granted) => safeReleased = granted));
    unawaited(scheduler
        .paceUiWork('held', 1)
        .then((granted) => heldReleased = granted));

    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(safeReleased, isTrue);
    expect(heldReleased, isFalse);

    scheduler.holding = false;
    for (var i = 0; i < 2; i++) {
      await tester.pump();
    }
    expect(heldReleased, isTrue);
  });

  testWidgets('cancel withdraws a pending request', (tester) async {
    final scheduler = PdfPageRenderScheduler()..holding = true;
    addTearDown(scheduler.dispose);
    var ran = false;
    scheduler.request('a', 0, () => ran = true);
    scheduler.cancel('a');
    expect(scheduler.hasPending, isFalse);

    scheduler.holding = false;
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(ran, isFalse);
  });

  testWidgets('worker UI completions drain one per frame, nearest first',
      (tester) async {
    final scheduler = PdfPageRenderScheduler()..focus = 5;
    addTearDown(scheduler.dispose);
    final order = <int>[];
    for (final page in [0, 8, 5, 6]) {
      scheduler.paceUiWork('p$page', page).then((ready) {
        if (ready) order.add(page);
      });
    }

    expect(order, isEmpty);
    await tester.pump();
    expect(order, isNotEmpty);
    expect(order.length, lessThan(4),
        reason: 'worker replies must not all replay in one frame');
    expect(order.first, 5);

    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(order, [5, 6, 8, 0]);
  });

  testWidgets('worker UI grants use distinct engine frames', (tester) async {
    final scheduler = PdfPageRenderScheduler();
    addTearDown(scheduler.dispose);
    final frames = <int>[];
    var frame = 0;
    for (var page = 0; page < 3; page++) {
      scheduler.paceUiWork('p$page', page).then((ready) {
        if (ready) frames.add(frame);
      });
    }

    for (var i = 0; i < 5 && frames.length < 3; i++) {
      frame++;
      await tester.pump();
    }
    expect(frames, hasLength(3));
    expect(frames.toSet(), hasLength(3),
        reason: 'at most one worker replay may be released per frame');
  });

  testWidgets('replaceable worker UI work keeps only the latest per page',
      (tester) async {
    final scheduler = PdfPageRenderScheduler()..holding = true;
    addTearDown(scheduler.dispose);
    final token = Object();
    final first = scheduler.paceUiWork(token, 4, replacePending: true);
    final second = scheduler.paceUiWork(token, 4, replacePending: true);
    final finalResult = scheduler.paceUiWork(token, 4, replacePending: true);

    expect(await first, isFalse);
    expect(await second, isFalse);
    var finalReady = false;
    finalResult.then((ready) => finalReady = ready);
    expect(finalReady, isFalse);

    scheduler.holding = false;
    for (var i = 0; i < 3 && !finalReady; i++) {
      await tester.pump();
    }
    expect(finalReady, isTrue);
  });

  testWidgets('holding and cancellation gate worker UI completions',
      (tester) async {
    final scheduler = PdfPageRenderScheduler()..holding = true;
    addTearDown(scheduler.dispose);
    final cancelled = scheduler.paceUiWork('cancelled', 0);
    final kept = scheduler.paceUiWork('kept', 1);
    scheduler.cancel('cancelled');

    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(await cancelled, isFalse);
    var keptReady = false;
    kept.then((value) => keptReady = value);
    expect(keptReady, isFalse);

    scheduler.holding = false;
    for (var i = 0; i < 3 && !keptReady; i++) {
      await tester.pump();
    }
    expect(keptReady, isTrue);
  });

  testWidgets('re-requesting a token interprets it once', (tester) async {
    final scheduler = PdfPageRenderScheduler();
    addTearDown(scheduler.dispose);
    var count = 0;
    // a re-layout before the grant refreshes the same request
    scheduler.request('a', 0, () => count++);
    scheduler.request('a', 0, () => count++);
    expect(scheduler.hasPending, isTrue);

    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(count, 1);
  });

  group('in-flight renders (#451)', () {
    testWidgets('a token re-requested mid-render is not granted twice',
        (tester) async {
      final scheduler = PdfPageRenderScheduler();
      addTearDown(scheduler.dispose);
      final gate = Completer<void>();
      var grants = 0;
      Future<void> render() async {
        grants++;
        await gate.future;
      }

      scheduler.request('a', 0, render);
      await tester.pump();
      expect(grants, 1);

      // The grant removed 'a' from the pending list, but its render is
      // still in flight - the worker round trip takes hundreds of ms. A
      // rebuild in that window used to enqueue a second, concurrent pass.
      scheduler.request('a', 0, render);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(grants, 1, reason: 'the first pass has not finished yet');

      gate.complete();
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      // The re-request is honoured, just serialized behind the first pass -
      // which by now has its picture, so this one re-rasters instead of
      // recording the page a second time.
      expect(grants, 2);
      expect(scheduler.hasPending, isFalse);
    });

    testWidgets('the focused render lands before neighbouring work fans out',
        (tester) async {
      final scheduler = PdfPageRenderScheduler();
      addTearDown(scheduler.dispose);
      final gate = Completer<void>();
      final order = <int>[];
      scheduler
        ..focus = 0
        ..request('a', 0, () async {
          order.add(0);
          await gate.future;
        })
        ..request('b', 1, () => order.add(1))
        ..request('c', 2, () => order.add(2));

      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(order, [0],
          reason: 'neighbour replies must not compete with focused pixels');
      gate.complete();
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(order, [0, 1, 2]);
    });

    testWidgets('moving focus wakes a drain parked behind the old focus',
        (tester) async {
      final scheduler = PdfPageRenderScheduler();
      addTearDown(scheduler.dispose);
      final oldFocusGate = Completer<void>();
      final order = <int>[];
      scheduler
        ..focus = 0
        ..request('old-focus', 0, () async {
          order.add(0);
          await oldFocusGate.future;
        })
        ..request('new-focus', 4, () => order.add(4));

      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(order, [0],
          reason: 'the neighbour waits while page 0 remains the focus');

      scheduler.focus = 4;
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(order, [0, 4],
          reason: 'navigation must not wait for the abandoned focus to land');

      oldFocusGate.complete();
      await tester.pump();
    });

    testWidgets('a non-focused render still allows worker concurrency',
        (tester) async {
      final scheduler = PdfPageRenderScheduler();
      addTearDown(scheduler.dispose);
      final gate = Completer<void>();
      final order = <int>[];
      scheduler
        ..focus = 10
        ..request('a', 1, () => order.add(1))
        ..request('b', 2, () => order.add(2))
        ..request('c', 3, () async {
          order.add(3);
          await gate.future;
        });

      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(order, [3, 2, 1]);
      gate.complete();
      await tester.pump();
    });

    testWidgets('cancelling mid-render drops the queued re-request',
        (tester) async {
      final scheduler = PdfPageRenderScheduler();
      addTearDown(scheduler.dispose);
      final gate = Completer<void>();
      var grants = 0;
      Future<void> render() async {
        grants++;
        await gate.future;
      }

      scheduler.request('a', 0, render);
      await tester.pump();
      scheduler.request('a', 0, render);
      // the page was recycled onto another index before its pass finished
      scheduler.cancel('a');
      gate.complete();
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(grants, 1);
      expect(scheduler.hasPending, isFalse);
    });

    testWidgets('a render that throws mid-flight still clears in-flight',
        (tester) async {
      final scheduler = PdfPageRenderScheduler();
      addTearDown(scheduler.dispose);
      final gate = Completer<void>();
      var grants = 0;
      Future<void> render() async {
        grants++;
        await gate.future;
        throw StateError('boom');
      }

      scheduler.request('a', 0, render);
      await tester.pump();
      scheduler.request('a', 0, render);
      gate.complete();
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      // an asynchronous failure must not wedge the page out of the queue
      // forever - the re-request still runs
      expect(grants, 2);
    });
  });

  testWidgets('a render that throws does not strand the queue', (tester) async {
    final scheduler = PdfPageRenderScheduler();
    addTearDown(scheduler.dispose);
    var reached = false;
    scheduler
      ..request('bad', 0, () => throw StateError('boom'))
      ..request('good', 1, () => reached = true);

    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(reached, isTrue);
    expect(scheduler.hasPending, isFalse);
  });
  // #603: the thumbnail warm builds its pictures on the platform thread, so it
  // needs a signal for "the viewer still wants that thread". `busy` is it, and
  // `activity` is how a gated pass learns the answer changed without polling
  // frames.
  testWidgets('busy tracks the hold and the queue, and pings activity',
      (tester) async {
    final scheduler = PdfPageRenderScheduler();
    addTearDown(scheduler.dispose);
    var pings = 0;
    scheduler.activity.addListener(() => pings++);

    expect(scheduler.busy, isFalse);

    scheduler.holding = true;
    expect(scheduler.busy, isTrue);
    expect(pings, 1);

    scheduler.request('a', 0, () {});
    expect(pings, 2);
    scheduler.holding = false;
    expect(scheduler.busy, isTrue, reason: 'the request is still queued');

    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(scheduler.busy, isFalse);
    expect(pings, greaterThan(2), reason: 'the drain must announce going idle');

    // a request withdrawn before its turn also lands the scheduler idle
    scheduler.holding = true;
    scheduler.request('b', 0, () {});
    scheduler.cancel('b');
    scheduler.holding = false;
    expect(scheduler.busy, isFalse);
  });

  testWidgets('busy stays true through an async render replay/raster',
      (tester) async {
    final scheduler = PdfPageRenderScheduler();
    addTearDown(scheduler.dispose);
    final gate = Completer<void>();
    var pings = 0;
    scheduler.activity.addListener(() => pings++);

    scheduler.request('page', 0, () async {
      await gate.future;
    });
    await tester.pump();

    expect(scheduler.hasPending, isFalse,
        reason: 'the page has already been granted');
    expect(scheduler.busy, isTrue,
        reason: 'its async replay/raster is still in flight');

    gate.complete();
    await tester.pump();
    expect(scheduler.busy, isFalse);
    expect(pings, greaterThanOrEqualTo(3),
        reason: 'queued, granted/in-flight, and settled transitions notify');
  });

  testWidgets('a parked viewer reads idle however much it is holding',
      (tester) async {
    // PdfViewer.active false (the full-area page grid overlaid it) holds every
    // render forever. That is not competition for the platform thread - and
    // gating the grid's own thumbnails behind it would deadlock the warm.
    final scheduler = PdfPageRenderScheduler()..holding = true;
    addTearDown(scheduler.dispose);
    scheduler.request('a', 0, () {});
    expect(scheduler.busy, isTrue);

    var pings = 0;
    scheduler.activity.addListener(() => pings++);
    scheduler.parked = true;
    expect(scheduler.busy, isFalse);
    expect(pings, 1);

    scheduler.parked = false;
    expect(scheduler.busy, isTrue);
    expect(pings, 2);
  });
}
