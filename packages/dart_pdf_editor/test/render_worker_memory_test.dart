// Render-worker memory: each worker's decoded-image cache is budgeted by the
// host's platform, and a memory-pressure signal reaches the workers - whose
// caches live in other isolates, out of the registry's reach - as a trim.
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/render_worker_isolate.dart'
    as isolate_worker;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// Counts the trims it is asked for; records nothing.
class _TrimCountingWorker extends PdfRenderWorker {
  int trims = 0;
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
      const <PdfRenderCommand>[];

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void trimMemory() => trims++;

  @override
  void dispose() => _active = false;
}

class _Listener implements PdfMemoryPressureListener {
  int trims = 0;

  @override
  void trimMemory() => trims++;
}

const _mb = 1024 * 1024;

void main() {
  group('pdfDefaultWorkerImageCacheBytes', () {
    test('desktop keeps 64 MB; mobile and web take 32 MB', () {
      expect(
          pdfDefaultWorkerImageCacheBytes(
              platform: PdfPerformancePlatform.desktop),
          64 * _mb);
      expect(
          pdfDefaultWorkerImageCacheBytes(
              platform: PdfPerformancePlatform.mobile),
          32 * _mb);
      expect(
          pdfDefaultWorkerImageCacheBytes(
              platform: PdfPerformancePlatform.web, deviceMemoryGb: 8),
          32 * _mb);
    });

    test('a web device admitting to 2 GB or less takes 16 MB', () {
      expect(
          pdfDefaultWorkerImageCacheBytes(
              platform: PdfPerformancePlatform.web, deviceMemoryGb: 2),
          16 * _mb);
      expect(
          pdfDefaultWorkerImageCacheBytes(
              platform: PdfPerformancePlatform.web, deviceMemoryGb: 0.5),
          16 * _mb);
    });
  });

  group('PdfCacheRegistry pressure listeners', () {
    test('memory pressure asks every live listener to trim', () {
      final registry = PdfCacheRegistry.instance;
      final a = _Listener(), b = _Listener();
      registry
        ..addPressureListener(a)
        ..addPressureListener(b)
        ..addPressureListener(a); // idempotent
      addTearDown(() => registry
        ..removePressureListener(a)
        ..removePressureListener(b));

      registry.handleMemoryPressure();
      expect((a.trims, b.trims), (1, 1));

      registry.removePressureListener(a);
      registry.handleMemoryPressure();
      expect((a.trims, b.trims), (1, 2));
    });

    test('trimPressureListeners trims without clearing the caches', () {
      final registry = PdfCacheRegistry.instance;
      final cache = PdfBudgetedCache<int, int>(
        weigher: (_) => 1,
        maxWeight: 100,
        clearsUnderMemoryPressure: true,
        debugLabel: 'render-worker-memory-test',
      )..put(1, 1);
      addTearDown(cache.dispose);
      final listener = _Listener();
      registry.addPressureListener(listener);
      addTearDown(() => registry.removePressureListener(listener));

      expect(registry.trimPressureListeners(), greaterThanOrEqualTo(1));
      expect(listener.trims, 1);
      expect(cache.lookup(1), 1, reason: 'a background trim keeps the caches');
    });
  });

  test('the caching worker forwards pressure to its backend until disposed',
      () {
    final backend = _TrimCountingWorker();
    final worker = PdfCachingRenderWorker(backend);
    PdfCacheRegistry.instance.handleMemoryPressure();
    expect(backend.trims, 1);
    worker.trimMemory();
    expect(backend.trims, 2);

    worker.dispose();
    PdfCacheRegistry.instance.handleMemoryPressure();
    expect(backend.trims, 2, reason: 'a disposed worker unregisters');
  });

  test('a pool trims every lane', () {
    final lanes = [_TrimCountingWorker(), _TrimCountingWorker()];
    final pool = PdfPooledRenderWorker.fromWorkers(lanes);
    addTearDown(pool.dispose);
    pool.trimMemory();
    expect([for (final lane in lanes) lane.trims], [1, 1]);
  });

  // End to end through a real isolate: the worker's decode count (read back
  // through the revision-report hook, with an empty update) shows a repeat
  // record hitting the cache, and the record after a trim decoding again.
  group('native worker', () {
    setUp(() {
      isolate_worker.debugReportPdfRenderWorkerRevisions = true;
      isolate_worker.debugPdfRenderWorkerRevisionReports.clear();
    });
    tearDown(() {
      isolate_worker.debugReportPdfRenderWorkerRevisions = false;
      isolate_worker.debugPdfRenderWorkerRevisionReports.clear();
    });

    testWidgets('a trim clears the decoded-image cache; records stay equal',
        (tester) async {
      await tester.runAsync(() async {
        final bytes = buildSyntheticRasterUnderlaySheet(
          underlays: const [PdfUnderlaySpec(width: 320, height: 240)],
          layers: 2,
          ops: 40,
          pageW: 612,
          pageH: 792,
        );
        final worker =
            PdfRenderWorker.startUncached(bytes, imageCacheBytes: 32 * _mb);
        addTearDown(worker.dispose);

        Future<int> decodesSoFar() async {
          // An empty update changes nothing and reports the decode count; it
          // rides the reply port ahead of the next record's reply.
          worker.updateRevision(
              bytes.length, Uint8List(0), bytes.length, const {});
          await worker.record(0, annotations: false);
          return isolate_worker
              .debugPdfRenderWorkerRevisionReports.last.imageDecodes;
        }

        final first = serializeCommands((await worker.record(0))!);
        final afterFirst = await decodesSoFar();
        expect(afterFirst, greaterThan(0));

        final repeat = serializeCommands((await worker.record(0))!);
        expect(await decodesSoFar(), afterFirst,
            reason: 'a repeat record reuses every decode');

        worker.trimMemory();
        final trimmed = serializeCommands((await worker.record(0))!);
        expect(await decodesSoFar(), greaterThan(afterFirst),
            reason: 'the trim dropped the decodes, so they were paid again');
        expect(repeat, first);
        expect(trimmed, first, reason: 'a trim never changes a record');
      });
    });
  });
}
