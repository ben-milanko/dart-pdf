// The revision-aware render worker (issue #308): an editor revision feeds an
// incremental append into the live worker instead of restarting it, and only
// the changed pages' cached renders are dropped - every other page's warm
// record survives the edit boundary.
import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// A fake backend that counts records per page and records the revision updates
/// it is handed. Its `record` returns an empty (weight-0) command list so the
/// caching wrapper stores and later serves it from cache.
class _FakeBackend extends PdfRenderWorker {
  final recordCounts = <int, int>{};
  final updates = <({int base, int appended, int newLength, Set<int>? pages})>[];
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

  test('an in-flight decode for a changed page is not cached (stale)', () async {
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
        reason: 'a decode dispatched before the edit must not cache its result');
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
      worker.updateRevision(original.length, Uint8List(0), original.length, {0});
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
}
