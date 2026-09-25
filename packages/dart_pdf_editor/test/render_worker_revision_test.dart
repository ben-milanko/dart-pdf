// The revision-aware render worker (issue #308): an editor revision feeds an
// incremental append into the live worker instead of restarting it, and only
// the changed pages' cached renders are dropped - every other page's warm
// record survives the edit boundary.
import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/render_worker_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart' show cosSparseBufferRanges;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// A fake backend that counts records per page and records the revision updates
/// it is handed. Its `record` returns an empty (weight-0) command list so the
/// caching wrapper stores and later serves it from cache.
class _FakeBackend extends PdfRenderWorker {
  final recordCounts = <int, int>{};
  final updates =
      <({int base, int appended, int newLength, Set<int>? pages})>[];
  // The appended bytes of each update, as handed over.
  final tails = <Uint8List>[];
  bool _active = true;

  // Completer gate for the in-flight test; when set, `record` waits on it.
  Completer<void>? gate;

  @override
  bool get isActive => _active;

  @override
  bool get supportsRevisionUpdate => true;

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
    recordCounts[pageIndex] = (recordCounts[pageIndex] ?? 0) + 1;
    if (gate != null) await gate!.future;
    return const <PdfRenderCommand>[];
  }

  @override
  void updateRevision(
    int baseLength,
    Uint8List appendedBytes,
    int newLength,
    Set<int>? changedPages,
  ) {
    updates.add((
      base: baseLength,
      appended: appendedBytes.length,
      newLength: newLength,
      pages: changedPages,
    ));
    tails.add(appendedBytes);
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() => _active = false;
}

void main() {
  test('supportsRevisionUpdate propagates through the caching wrapper', () {
    final backend = _FakeBackend();
    expect(PdfCachingRenderWorker(backend).supportsRevisionUpdate, isTrue);
  });

  test('editing one page drops its cache and keeps every other page warm',
      () async {
    final backend = _FakeBackend();
    final worker = PdfCachingRenderWorker(backend);

    // Warm pages 5 and 6.
    await worker.record(5);
    await worker.record(6);
    expect(backend.recordCounts[5], 1);
    expect(backend.recordCounts[6], 1);

    // Both served from cache now - no new backend records.
    await worker.record(5);
    await worker.record(6);
    expect(backend.recordCounts[5], 1);
    expect(backend.recordCounts[6], 1);

    // Edit page 5: an incremental append that changes page 5 only.
    worker.updateRevision(100, Uint8List.fromList([1, 2, 3]), 103, {5});

    // The update was forwarded to the backend unchanged.
    expect(backend.updates.single.base, 100);
    expect(backend.updates.single.appended, 3);
    expect(backend.updates.single.newLength, 103);
    expect(backend.updates.single.pages, {5});

    // Page 5's record was dropped (re-records); page 6's survived (still cached).
    await worker.record(5);
    await worker.record(6);
    expect(backend.recordCounts[5], 2, reason: 'edited page 5 must re-render');
    expect(backend.recordCounts[6], 1, reason: 'page 6 must survive the edit');
  });

  test('an all-pages revision (null changedPages) clears the whole cache',
      () async {
    final backend = _FakeBackend();
    final worker = PdfCachingRenderWorker(backend);
    await worker.record(1);
    await worker.record(2);
    expect(backend.recordCounts[1], 1);
    expect(backend.recordCounts[2], 1);

    worker.updateRevision(50, Uint8List.fromList([9]), 51, null);

    await worker.record(1);
    await worker.record(2);
    expect(backend.recordCounts[1], 2);
    expect(backend.recordCounts[2], 2);
  });

  test('an in-flight decode for a changed page is not cached (stale)',
      () async {
    final backend = _FakeBackend();
    final worker = PdfCachingRenderWorker(backend);

    // Start a decode for page 7 and hold it in flight.
    backend.gate = Completer<void>();
    final pending = worker.record(7);
    expect(backend.recordCounts[7], 1);

    // Page 7 is edited while its decode is still running.
    worker.updateRevision(10, Uint8List.fromList([1]), 11, {7});

    // Let the stale decode finish.
    backend.gate!.complete();
    await pending;
    backend.gate = null;

    // Its result must not have been cached: a fresh request re-records.
    await worker.record(7);
    expect(backend.recordCounts[7], 2,
        reason:
            'a decode dispatched before the edit must not cache its result');
  });

  test('a stale in-flight completion does not evict a newer in-flight decode',
      () async {
    final backend = _FakeBackend();
    final worker = PdfCachingRenderWorker(backend);

    // F1 for page 8 is held in flight.
    final gate1 = Completer<void>();
    backend.gate = gate1;
    final f1 = worker.record(8);
    expect(backend.recordCounts[8], 1);

    // Edit page 8: its in-flight entry is dropped from the dedup map.
    worker.updateRevision(10, Uint8List.fromList([1]), 11, {8});

    // A fresh request re-decodes against the new revision (F2) and becomes the
    // in-flight decode for page 8.
    final gate2 = Completer<void>();
    backend.gate = gate2;
    final f2 = worker.record(8);
    expect(backend.recordCounts[8], 2);

    // The stale F1 now completes. Its cleanup must NOT clear the slot F2 owns.
    gate1.complete();
    await f1;
    await Future<void>.microtask(() {});

    // A third request must share F2 (in-flight dedup), not start a third decode.
    backend.gate = null;
    final f3 = worker.record(8);
    expect(backend.recordCounts[8], 2,
        reason: 'the stale decode must not clear the fresh in-flight slot');

    gate2.complete();
    await Future.wait([f2, f3]);
  });

  testWidgets(
      'the real isolate worker updates its document in place across an edit',
      (tester) async {
    await tester.runAsync(() async {
      final original = buildMultiPagePdf(3);

      final worker =
          startPdfRenderWorker(original, pageCount: 3, workerCount: 1);
      addTearDown(worker.dispose);
      expect(worker.supportsRevisionUpdate, isTrue);

      final before0 = await worker.record(0);
      final before1 = await worker.record(1);
      expect(before0, isNotNull);
      expect(before1, isNotNull);

      // Draw a square on page 0 and feed the incremental append to the worker.
      final editor = PdfEditor(PdfDocument.open(original))
        ..addSquare(0, const PdfRect(20, 20, 120, 120));
      final updated = editor.save();
      final appended =
          Uint8List.fromList(Uint8List.sublistView(updated, original.length));
      worker.updateRevision(original.length, appended, updated.length, {0});

      final after0 = await worker.record(0);
      final after1 = await worker.record(1);
      expect(after0, isNotNull);
      expect(after1, isNotNull);

      // Page 0 gained the square's appearance commands; page 1 is untouched.
      expect(after0!.length, greaterThan(before0!.length),
          reason: 'the edited page must reflect the new annotation');
      expect(after1!.length, before1!.length,
          reason: 'an unedited page must render identically after the edit');

      // Undo: the live revision shrinks back to the original prefix (no bytes to
      // append). The isolate can't apply that as a forward append, so it
      // re-opens from the shorter prefix and page 0 renders as it did before.
      worker
          .updateRevision(original.length, Uint8List(0), original.length, {0});
      final undone0 = await worker.record(0);
      expect(undone0, isNotNull);
      expect(undone0!.length, before0.length,
          reason: 'undo must restore the pre-edit rendering of page 0');
    });
  });

  testWidgets('the pooled worker fans a revision update to every worker',
      (tester) async {
    await tester.runAsync(() async {
      // 12 pages + a pool of 2 selects the PdfPooledRenderWorker backend.
      final original = buildMultiPagePdf(12);
      final worker =
          startPdfRenderWorker(original, pageCount: 12, workerCount: 2);
      addTearDown(worker.dispose);
      expect(worker.supportsRevisionUpdate, isTrue);

      final before3 = await worker.record(3);
      final before9 = await worker.record(9);
      expect(before3, isNotNull);
      expect(before9, isNotNull);

      final editor = PdfEditor(PdfDocument.open(original))
        ..addSquare(3, const PdfRect(20, 20, 120, 120));
      final updated = editor.save();
      final appended =
          Uint8List.fromList(Uint8List.sublistView(updated, original.length));
      worker.updateRevision(original.length, appended, updated.length, {3});

      // Whichever pooled worker serves each page has the update, so page 3
      // reflects the edit and page 9 does not - no matter the routing.
      final after3 = await worker.record(3);
      final after9 = await worker.record(9);
      expect(after3!.length, greaterThan(before3!.length));
      expect(after9!.length, before9!.length);
    });
  });

  // The isolate worker appends each revision's tail to its buffer in place and
  // reads an undo as a shorter view of it. These drive a real editing session,
  // whose own buffer is overwritten in place by an edit after an undo, and
  // check every step against a fresh worker opened on a copy of the bytes.
  testWidgets(
      'the isolate worker applies revisions in place: edit, undo, an '
      'overwriting edit, redo', (tester) async {
    await tester.runAsync(() async {
      final controller = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(controller.dispose);
      // One platform worker behind the pool's router and no record cache, so
      // every record below really walks the worker's own document.
      final worker =
          PdfPooledRenderWorker(controller.bytes, 1, copySource: false);
      addTearDown(worker.dispose);
      const pages = [0, 1, 2];
      for (final page in pages) {
        await worker.record(page); // warm the caches revisions must evict
      }
      final originalLength = controller.bytes.length;

      controller.apply((e) => e.addSquare(0, const PdfRect(20, 20, 120, 120)));
      _feed(worker, controller);
      await _expectMatchesFresh(worker, controller.bytes, pages,
          step: 'edit A');
      final afterA = Uint8List.fromList(controller.bytes);

      controller.apply((e) => e.addCircle(1, const PdfRect(30, 30, 90, 90)));
      _feed(worker, controller);
      controller.undo();
      _feed(worker, controller);
      controller.undo();
      _feed(worker, controller);
      await _expectMatchesFresh(worker, controller.bytes, pages,
          step: 'undo back to the original');

      // Edit C is written where A's bytes were.
      controller
          .apply((e) => e.addCircle(0, const PdfRect(200, 200, 260, 300)));
      _feed(worker, controller);
      final overlap = afterA.length < controller.bytes.length
          ? afterA.length
          : controller.bytes.length;
      expect(Uint8List.sublistView(controller.bytes, originalLength, overlap),
          isNot(Uint8List.sublistView(afterA, originalLength, overlap)),
          reason: 'edit C must overwrite the undone bytes');
      await _expectMatchesFresh(worker, controller.bytes, pages,
          step: 'edit C over the undone revisions');

      controller.undo();
      _feed(worker, controller);
      controller.redo();
      _feed(worker, controller);
      await _expectMatchesFresh(worker, controller.bytes, pages,
          step: 'undo + redo of C');
    });
  });

  testWidgets(
      'a coalesced undo + edit (base below the worker revision) re-opens '
      'exactly', (tester) async {
    await tester.runAsync(() async {
      final controller = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(controller.dispose);
      final worker =
          PdfPooledRenderWorker(controller.bytes, 1, copySource: false);
      addTearDown(worker.dispose);
      const pages = [0, 1, 2];

      controller.apply((e) => e.addSquare(0, const PdfRect(20, 20, 120, 120)));
      _feed(worker, controller);
      controller
          .apply((e) => e.addSquare(0, const PdfRect(150, 150, 220, 220)));
      _feed(worker, controller);
      for (final page in pages) {
        await worker.record(page);
      }

      // The worker misses both undos and hears only edit C, whose base is
      // below the revision it holds: C's tail lands on bytes its open document
      // still views, so it has to re-open rather than append.
      controller.undo();
      controller.undo();
      controller.apply((e) => e.addCircle(0, const PdfRect(40, 300, 140, 380)));
      _feed(worker, controller);
      await _expectMatchesFresh(worker, controller.bytes, pages,
          step: 'coalesced undo + edit');
      // Then an ordinary forward append on top.
      controller.apply((e) => e.addSquare(1, const PdfRect(10, 10, 50, 50)));
      _feed(worker, controller);

      await _expectMatchesFresh(worker, controller.bytes, pages,
          step: 'coalesced undo + edit, then an append');
    });
  });

  // updateRevisionTo: the host hands over a view of the whole revision instead
  // of a tail, so the pool's urgent lane can open that view rather than
  // rebuild a private full-document copy on the UI isolate per revision.
  test(
      'updateRevisionTo gives a backend that only implements updateRevision a '
      'private copy of the tail', () async {
    final backend = _FakeBackend();
    final worker = PdfCachingRenderWorker(backend);
    await worker.record(5);
    await worker.record(6);

    // The revision is a view into a session buffer with spare capacity.
    final session = Uint8List(128)..setRange(100, 103, [7, 8, 9]);
    worker.updateRevisionTo(Uint8List.sublistView(session, 0, 103), 100, {5});

    final update = backend.updates.single;
    expect(update.base, 100);
    expect(update.appended, 3);
    expect(update.newLength, 103);
    expect(update.pages, {5});
    // An undo and a new edit later overwrite that range in the session; the
    // update (which a real worker ships only once it is idle) keeps its bytes.
    session.setRange(100, 103, [0, 0, 0]);
    expect(backend.tails.single, [7, 8, 9]);

    // The caching wrapper invalidated exactly as updateRevision does.
    await worker.record(5);
    await worker.record(6);
    expect(backend.recordCounts[5], 2, reason: 'edited page 5 must re-render');
    expect(backend.recordCounts[6], 1, reason: 'page 6 must survive the edit');
  });

  test('the pool seeds its urgent lane from the revision view, not a copy',
      () async {
    final session = Uint8List(128);
    for (var i = 0; i < 64; i++) {
      session[i] = i;
    }
    final seeds = <Uint8List>[];
    final backends = <_FakeBackend>[];
    final pool = PdfPooledRenderWorker.withSpawner(
      Uint8List.sublistView(session, 0, 64),
      2,
      (bytes) {
        seeds.add(bytes);
        final backend = _FakeBackend();
        backends.add(backend);
        return backend;
      },
      copySource: false,
      populatedRanges: const [0, 32],
    );
    addTearDown(pool.dispose);

    session.fillRange(64, 80, 0xab);
    final edited = Uint8List.sublistView(session, 0, 80);
    pool.updateRevisionTo(edited, 64, {0});
    for (final lane in backends) {
      final update = lane.updates.single;
      expect(update.base, 64);
      expect(update.appended, 16);
      expect(update.newLength, 80);
      expect(update.pages, {0});
    }
    expect(
        identical(backends[0].tails.single, backends[1].tails.single), isTrue,
        reason: 'one tail copy serves every lane');
    // The sparse-buffer map follows the seed onto the new view.
    expect(cosSparseBufferRanges[edited], [0, 32, 64, 80]);

    await pool.record(0, priority: -2000);
    expect(seeds, hasLength(3), reason: 'the urgent lane was spawned');
    expect(identical(seeds.last, edited), isTrue,
        reason: 'the urgent lane opens the revision view itself');

    // An undo is a shorter view, adopted as it is, and the urgent worker that
    // opened the edited revision is dropped.
    final undone = Uint8List.sublistView(session, 0, 64);
    pool.updateRevisionTo(undone, 64, {0});
    expect(backends[0].updates.last.appended, 0);
    expect(backends[2].isActive, isFalse);
    await pool.record(0, priority: -2000);
    expect(seeds, hasLength(4));
    expect(identical(seeds.last, undone), isTrue);
  });

  testWidgets(
      'through the host, the pool and its urgent lane stay exact across edit, '
      'undo, an overwriting edit and redo', (tester) async {
    await tester.runAsync(() async {
      // The host spawns a raw pool, with no record cache in front of it, so a
      // priority -2000 record really reaches the lazily spawned urgent lane.
      PdfPooledRenderWorker? pool;
      PdfRenderWorkerHost.debugSpawnOverride = (bytes,
              {required int pageCount,
              int? workerCount,
              bool copySource = false}) =>
          pool = PdfPooledRenderWorker(bytes, 2, copySource: copySource);
      addTearDown(() => PdfRenderWorkerHost.debugSpawnOverride = null);
      final controller = PdfEditingController(buildMultiPagePdf(12));
      final host = PdfRenderWorkerHost();
      // What the shell does on every session change.
      void sync() {
        final delta = controller.lastRevisionDelta;
        host.sync(
          document: controller.document,
          bytes: controller.bytes,
          pageCount: 12,
          revision: delta == null
              ? null
              : (
                  baseLength: delta.baseLength,
                  newLength: delta.newLength,
                  changedPages: delta.changedPages,
                ),
        );
      }

      sync();
      controller.addListener(sync);
      addTearDown(() {
        controller.removeListener(sync);
        host.dispose();
        controller.dispose();
      });
      final worker = pool!;
      const pages = [0, 1, 2, 5];
      const urgent = -2000;
      for (final page in pages) {
        await worker.record(page);
      }
      await worker.record(5, priority: urgent); // urgent lane on the original
      final originalLength = controller.bytes.length;

      controller.apply((e) => e.addSquare(0, const PdfRect(20, 20, 120, 120)));
      await _expectMatchesFresh(worker, controller.bytes, const [0],
          priority: urgent, step: 'edit A (urgent lane)');
      final afterA = Uint8List.fromList(controller.bytes);

      controller.apply((e) => e.addCircle(1, const PdfRect(30, 30, 90, 90)));
      controller.undo();
      controller.undo();
      await _expectMatchesFresh(worker, controller.bytes, const [0, 1],
          priority: urgent, step: 'undo back to the original (urgent lane)');

      // Edit C is written where A's bytes were.
      controller
          .apply((e) => e.addCircle(0, const PdfRect(200, 200, 260, 300)));
      final overlap = afterA.length < controller.bytes.length
          ? afterA.length
          : controller.bytes.length;
      expect(Uint8List.sublistView(controller.bytes, originalLength, overlap),
          isNot(Uint8List.sublistView(afterA, originalLength, overlap)),
          reason: 'edit C must overwrite the undone bytes');
      await _expectMatchesFresh(worker, controller.bytes, const [0],
          priority: urgent, step: 'edit C (urgent lane)');

      controller.undo();
      controller.redo();
      expect(host.generations, 1, reason: 'every revision applied in place');
      await _expectMatchesFresh(worker, controller.bytes, pages,
          step: 'undo + redo of C (pool)');
      await _expectMatchesFresh(worker, controller.bytes, pages,
          priority: urgent, step: 'undo + redo of C (urgent lane)');
    });
  });
}

/// Feeds [controller]'s latest revision to [worker] with a private copy of its
/// tail, as [PdfRenderWorker.updateRevision] callers must.
void _feed(PdfRenderWorker worker, PdfEditingController controller) {
  final delta = controller.lastRevisionDelta!;
  worker.updateRevision(
    delta.baseLength,
    Uint8List.fromList(Uint8List.sublistView(
        controller.bytes, delta.baseLength, delta.newLength)),
    delta.newLength,
    delta.changedPages,
  );
}

/// [pageIndex]'s record from [worker] in wire form, byte-comparable across
/// workers.
Future<Uint8List?> _recorded(PdfRenderWorker worker, int pageIndex,
    {int priority = 0}) async {
  final commands = await worker.record(pageIndex, priority: priority);
  return commands == null ? null : serializeCommands(commands);
}

/// Expects [worker] to record [pages] (at [priority]) byte-identically to a
/// fresh worker opened on a private copy of [bytes].
Future<void> _expectMatchesFresh(
  PdfRenderWorker worker,
  Uint8List bytes,
  List<int> pages, {
  int priority = 0,
  required String step,
}) async {
  final fresh = PdfPooledRenderWorker(Uint8List.fromList(bytes), 1);
  try {
    for (final page in pages) {
      final want = await _recorded(fresh, page);
      expect(want, isNotNull, reason: '$step: reference page $page');
      expect(await _recorded(worker, page, priority: priority), want,
          reason: '$step: page $page');
    }
  } finally {
    fresh.dispose();
  }
}
