// The render scheduler paces every page's first (UI-thread) interpret so
// a settling fast scroll can't fire them all in one event-loop turn — the
// burst that froze fast scrolling on iPad. These tests pin the pacing,
// the priority order, and the hold gate.
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

void main() {
  testWidgets('requests drain paced — never a synchronous burst', (tester) async {
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
    // a frame in: some progress, but not the whole queue at once
    expect(order, isNotEmpty);
    expect(order.length, lessThan(4));

    // the nearest-the-viewport page drains first
    expect(order.first, 5);

    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    // every page interpreted, closest-to-focus order
    expect(order, [5, 6, 9, 0]);
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
}
