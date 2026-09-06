// The binStrips worker protocol:
//
//  - native isolate end-to-end: a worker-binned StripPlan is bit-identical
//    to a local StripPlanBinner run over the same worker-recorded command
//    buffer (the worker re-records in its own isolate and round-trips
//    through the wire codec, so geometry carries the same float32
//    truncation as the buffer the caller's scene holds);
//  - the isolate queue's kind-scoped cancel (cancelBinStrips drops queued
//    bins without touching queued records, and vice versa);
//  - cancelBinStrips also preempts matching IN-FLIGHT bin and combined-detail
//    jobs (the worker abandons the stale walk and resolves null) - what lets a
//    newer speculative/settle geometry supersede the translated region;
//  - pool routing by the STATIC page index (worker-side command-cache
//    affinity) for both binStrips and cancelBinStrips;
//  - the caching wrapper passes bins straight through (plans are never
//    cached - every settle has a fresh matrix);
//  - the abstract default (which the unsupported-platform stub inherits)
//    declines with null.
import 'dart:typed_data';
import 'dart:ui' show Image, ImageByteFormat, Rect;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/region_replay_index.dart';
import 'package:dart_pdf_editor/src/render_worker_isolate.dart'
    as isolate_worker;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'render_seam_test.dart' show buildStripsPdf;
import 'strip_zoom_router_test.dart' show buildVectorPdf;

List<double> _coeffs(PdfMatrix m) => [m.a, m.b, m.c, m.d, m.e, m.f];

Future<Uint8List> _rgba(Image image) async =>
    (await image.toByteData(format: ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();

/// A one-page PDF dense enough (thousands of interpreter ops) that a bin
/// job reliably spans several of the worker's cooperative yield points, so
/// an in-flight cancel deterministically lands mid-walk.
Uint8List buildDenseVectorPdf({int rects = 4000}) {
  final content = StringBuffer();
  for (var i = 0; i < rects; i++) {
    final x = (i * 7) % 550;
    final y = (i * 13) % 730;
    content.write('${(i % 10) / 10} 0 0 rg $x $y 8 6 re f ');
  }
  final body = content.toString();
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << >> >>',
    '<< /Length ${body.length} >>\nstream\n$body\nendstream',
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
  return Uint8List.fromList(buffer.toString().codeUnits);
}

// Each rectangle contributes three PDF operators. Keep this above the native
// worker's 64k-operation resumable-record chunk so the first page necessarily
// reaches a cooperative cancellation boundary before it can finish. This test
// used 8k rectangles when the chunk was 4k operations; the merged performance
// work grew that chunk, making the old fixture too small to exercise
// preemption at all.
Uint8List _buildTwoPageDenseVectorPdf({int rects = 24000}) {
  final dense = StringBuffer();
  for (var i = 0; i < rects; i++) {
    dense.write('${(i % 10) / 10} 0 0 rg '
        '${(i * 7) % 550} ${(i * 13) % 730} 8 6 re f ');
  }
  final body = dense.toString();
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 5 0 R /Resources << >> >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 6 0 R /Resources << >> >>',
    '<< /Length ${body.length} >>\nstream\n$body\nendstream',
    '<< /Length ${body.length} >>\nstream\n$body\nendstream',
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
  return Uint8List.fromList(buffer.toString().codeUnits);
}

void main() {
  testWidgets(
      'isolate returns region commands and matching strip plan together',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildVectorPdf();
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);

      final size = PdfPageRenderer.pageSize(page);
      const ratio = 2.0;
      final matrix = PdfPageRenderer.pageToDeviceMatrix(
          page, size, page.cropBox,
          pixelRatio: ratio);
      final detail = await worker.recordStripDetail(
        0,
        annotations: true,
        pageToDevice: _coeffs(matrix),
        deviceWidth: (size.width * ratio).ceil(),
        deviceHeight: (size.height * ratio).ceil(),
        pixelRatio: ratio,
        imageDecodeRegion: PdfRect(0, 0, size.width / 2, size.height / 2),
      );

      expect(detail, isNotNull);
      expect(detail!.commands, isNotEmpty);
      expect(detail.plan.batches, isNotEmpty);
      final local = StripPlanBinner(
        pageToDevice: matrix,
        deviceWidth: (size.width * ratio).ceil(),
        deviceHeight: (size.height * ratio).ceil(),
        pixelRatio: ratio,
      );
      await local.bin(detail.commands);
      expect(encodeStripPlan(detail.plan), encodeStripPlan(local.finish()),
          reason: 'the returned plan must describe the returned commands, '
              'not a separate base recording');
    });
  });

  testWidgets('isolate detail culls a wide CAD transcript byte-identically',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildSyntheticCadStrip(ops: 6000, streams: 2);
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);

      final commands = await worker.record(0, decodeImages: false);
      expect(commands, isNotNull);
      final fullScene = await PdfRetainedScene.fromCommands(page, commands!);
      addTearDown(fullScene.dispose);

      const region = Rect.fromLTWH(120, 300, 300, 180);
      const ratio = 1.5;
      final geometry = fullScene.stripRegionGeometry(
        region,
        pixelRatio: ratio,
      );
      final m = geometry.pageToDevice;
      final size = fullScene.pageSize;
      final detail = await worker.recordStripDetail(
        0,
        annotations: true,
        pageToDevice: _coeffs(m),
        deviceWidth: geometry.width,
        deviceHeight: geometry.height,
        pixelRatio: ratio,
        imageDecodeRegion: PdfRect(
          region.left,
          size.height - region.bottom,
          region.right,
          size.height - region.top,
        ),
      );
      expect(detail, isNotNull);
      expect(detail!.commands.length, lessThan(commands.length ~/ 2),
          reason: 'the worker should not transfer the offscreen CAD strokes');

      final detailScene = await PdfRetainedScene.fromCommands(
        page,
        detail.commands,
      );
      addTearDown(detailScene.dispose);
      final expected = await fullScene.rasterizeRegionStrips(
        region,
        pixelRatio: ratio,
      );
      final actual = await detailScene.rasterizeRegionStrips(
        region,
        pixelRatio: ratio,
        stripPlan: detail.plan,
      );
      try {
        expect(await _rgba(actual), await _rgba(expected),
            reason: 'selective worker detail must preserve region pixels');
      } finally {
        actual.dispose();
        expected.dispose();
      }
    });
  });

  testWidgets('combined detail decodes region images in the worker',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildStripsPdf();
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);
      final size = PdfPageRenderer.pageSize(page);
      const ratio = 2.0;
      final matrix = PdfPageRenderer.pageToDeviceMatrix(
          page, size, page.cropBox,
          pixelRatio: ratio);
      expect(await worker.record(0, decodeImages: false), isNotNull,
          reason: 'the image page must support a weightless recording');
      expect(
          await worker.record(0,
              imagePixelRatio: ratio,
              imageDecodeRegion: const PdfRect(0, 0, 100, 100)),
          isNotNull,
          reason: 'the image page must support a region decode');
      final detail = await worker.recordStripDetail(
        0,
        annotations: true,
        pageToDevice: _coeffs(matrix),
        deviceWidth: (size.width * ratio).ceil(),
        deviceHeight: (size.height * ratio).ceil(),
        pixelRatio: ratio,
        imageDecodeRegion: const PdfRect(0, 0, 100, 100),
      );
      expect(detail, isNotNull);
      expect(PdfPageRenderer.decodedImageStats(detail!.commands).$1,
          greaterThan(0),
          reason: 'region image pixels must ride in the combined response');

      final scene = await PdfRetainedScene.fromCommands(page, detail.commands);
      final image = await scene.rasterizeRegionStrips(
        const Rect.fromLTWH(0, 0, 100, 100),
        pixelRatio: ratio,
        stripPlan: detail.plan,
      );
      expect(image.width, 200);
      expect(image.height, 200);
      image.dispose();
      scene.dispose();
    });
  });

  testWidgets('isolate binStrips matches a local bin of the recorded buffer',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildVectorPdf();
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);

      final commands = await worker.record(0);
      expect(commands, isNotNull);

      final size = PdfPageRenderer.pageSize(page);
      const ratio = 2.0;
      final matrix = PdfPageRenderer.pageToDeviceMatrix(
          page, size, page.cropBox,
          pixelRatio: ratio);
      final width = (size.width * ratio).ceil();
      final height = (size.height * ratio).ceil();

      final plan = await worker.binStrips(0,
          annotations: true,
          pageToDevice: _coeffs(matrix),
          deviceWidth: width,
          deviceHeight: height,
          pixelRatio: ratio);
      expect(plan, isNotNull, reason: 'a vector page must bin off-thread');
      expect(plan!.batches, isNotEmpty);
      expect(plan.deviceWidth, width);
      expect(plan.deviceHeight, height);
      expect(plan.pageToDevice.a, matrix.a);
      expect(plan.pageToDevice.f, matrix.f);
      expect(plan.tolerance, stripFlattenTolerance);

      final local = StripPlanBinner(
        pageToDevice: matrix,
        deviceWidth: width,
        deviceHeight: height,
        pixelRatio: ratio,
      );
      await local.bin(commands!);
      final localPlan = local.finish();
      expect(encodeStripPlan(plan), encodeStripPlan(localPlan),
          reason: 'worker and local binning of the same buffer must be '
              'bit-identical');

      // A repeat settle at a different geometry serves from the worker-side
      // command cache and stays consistent.
      const ratio2 = 3.0;
      final matrix2 = PdfPageRenderer.pageToDeviceMatrix(
          page, size, page.cropBox,
          pixelRatio: ratio2);
      final plan2 = await worker.binStrips(0,
          annotations: true,
          pageToDevice: _coeffs(matrix2),
          deviceWidth: (size.width * ratio2).ceil(),
          deviceHeight: (size.height * ratio2).ceil(),
          pixelRatio: ratio2);
      expect(plan2, isNotNull);
      expect(plan2!.totalFlushPoints, plan.totalFlushPoints,
          reason: 'flush structure is geometry-independent');
    });
  });

  testWidgets('isolate builds Slug batches bit-identically off-thread',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildEmbeddedFontPdf();
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);
      final commands = await worker.record(0);
      expect(commands, isNotNull);
      final size = PdfPageRenderer.pageSize(page);
      final matrix = PdfPageRenderer.pageToDeviceMatrix(
          page, size, page.cropBox,
          pixelRatio: 1);
      final plan = await worker.binStrips(0,
          annotations: true,
          pageToDevice: _coeffs(matrix),
          deviceWidth: size.width.ceil(),
          deviceHeight: size.height.ceil(),
          pixelRatio: 1,
          slugGlyphs: true);
      expect(plan, isNotNull);
      expect(plan!.slugGlyphs, isTrue);
      expect(plan.slugBatches, isNotEmpty);
      expect(plan.slugQuadCount, greaterThan(0));
      expect(plan.slugFallbackOutlineRuns, 0);

      final local = StripPlanBinner(
        pageToDevice: matrix,
        deviceWidth: size.width.ceil(),
        deviceHeight: size.height.ceil(),
        pixelRatio: 1,
        slugGlyphs: true,
      );
      await local.bin(commands!);
      expect(encodeStripPlan(plan), encodeStripPlan(local.finish()),
          reason: 'the UI must only upload worker-built Slug data');
    });
  });

  testWidgets('cancelBinStrips drops queued bins, not queued records',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildVectorPdf();
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);

      // Queue both before the spawn handshake can complete, then cancel the
      // bin: its future must resolve null while the record still runs.
      final record = worker.record(0);
      final bin = worker.binStrips(0,
          annotations: true,
          pageToDevice: const [1, 0, 0, 1, 0, 0],
          deviceWidth: 100,
          deviceHeight: 100,
          pixelRatio: 1);
      worker.cancelBinStrips(0);
      expect(await bin, isNull, reason: 'cancelled bin resolves null');
      expect(await record, isNotNull,
          reason: 'the record must survive a bin cancel for the same page');

      // And the mirror: cancel() must not touch a queued bin.
      final worker2 = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker2.dispose);
      final record2 = worker2.record(0);
      final bin2 = worker2.binStrips(0,
          annotations: true,
          pageToDevice: const [1, 0, 0, 1, 0, 0],
          deviceWidth: 100,
          deviceHeight: 100,
          pixelRatio: 1);
      worker2.cancel(0);
      expect(await record2, isNull, reason: 'cancelled record resolves null');
      expect(await bin2, isNotNull,
          reason: 'the bin must survive a record cancel for the same page');
    });
  });

  testWidgets('cancelBinStrips preempts a matching in-flight bin',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildDenseVectorPdf();
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);
      // Warm up so the isolate is spawned and idle: the next binStrips is
      // dispatched (in flight) synchronously, not parked in the queue.
      expect(await worker.record(0), isNotNull);

      Future<StripPlan?> bin() => worker.binStrips(0,
          annotations: true,
          pageToDevice: const [1, 0, 0, 1, 0, 0],
          deviceWidth: 612,
          deviceHeight: 792,
          pixelRatio: 1);

      final stale = bin(); // in flight on the worker now
      worker.cancelBinStrips(0); // same (page, priority): preempt mid-walk
      expect(await stale.timeout(const Duration(seconds: 30)), isNull,
          reason: 'the preempted in-flight bin must resolve null');

      // The worker survives the preemption and serves the next identical
      // request with a real plan.
      final fresh = await bin().timeout(const Duration(seconds: 30));
      expect(fresh, isNotNull,
          reason: 'a fresh bin after the preemption must succeed');
      expect(fresh!.batches, isNotEmpty);
    });
  });

  testWidgets('cancelBinStrips preempts a matching in-flight detail job',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildDenseVectorPdf();
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);
      expect(await worker.record(0), isNotNull);

      Future<PdfStripDetail?> detail() => worker.recordStripDetail(
            0,
            annotations: true,
            pageToDevice: const [1, 0, 0, 1, 0, 0],
            deviceWidth: 612,
            deviceHeight: 792,
            pixelRatio: 1,
            imageDecodeRegion: const PdfRect(0, 0, 612, 792),
          );

      final stale = detail();
      worker.cancelBinStrips(0);
      expect(await stale.timeout(const Duration(seconds: 30)), isNull,
          reason: 'the superseded region detail must stop mid-walk');

      final fresh = await detail().timeout(const Duration(seconds: 30));
      expect(fresh, isNotNull,
          reason: 'the worker must survive detail preemption');
      expect(fresh!.plan.batches, isNotEmpty);
    });
  });

  testWidgets('priority preemption requeues a shared in-flight record',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = _buildTwoPageDenseVectorPdf();
      final backend = PdfRenderWorker.startUncached(bytes);
      // Complete the spawn handshake so page 0 is already in flight when the
      // urgent page is submitted, rather than both merely being sorted in the
      // startup queue.
      expect(await backend.record(1), isNotNull);
      final worker = PdfCachingRenderWorker(backend);
      addTearDown(worker.dispose);

      final completionOrder = <String>[];
      final lowA = worker.record(0, priority: 10).then((value) {
        completionOrder.add('low');
        return value;
      });
      final lowB = worker.record(0, priority: 10);
      final urgent = worker.record(1, priority: 0).then((value) {
        completionOrder.add('urgent');
        return value;
      });

      expect(await urgent.timeout(const Duration(seconds: 30)), isNotNull);
      expect(await lowA.timeout(const Duration(seconds: 30)), isNotNull,
          reason: 'the interrupted shared record must be retried, not nulled');
      expect(await lowB.timeout(const Duration(seconds: 30)), isNotNull,
          reason: 'every deduplicated waiter must receive the retried record');
      expect(completionOrder.first, 'urgent',
          reason: 'the visible page must still cut ahead of the prefetch');
    });
  });

  testWidgets('a late cancel id cannot abort the next worker request',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = _buildTwoPageDenseVectorPdf();
      // Enable the defer hook BEFORE spawning: the worker reads the global into
      // its init synchronously as it starts, so a later assignment is too late.
      isolate_worker.debugDeferPdfRenderWorkerCancelUntilNextRequest = true;
      addTearDown(() => isolate_worker
          .debugDeferPdfRenderWorkerCancelUntilNextRequest = false);
      isolate_worker.debugPdfRenderWorkerIgnoredStaleCancels = 0;
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);

      // Warm the handshake, then let page 1 request preemption while page 0
      // is already running. The worker withholds page 0's cancel until page 1
      // goes active, then replays it - recreating the old cross-request race
      // deterministically, on the worker's own event loop.
      expect(await worker.record(1), isNotNull);
      final first = worker.record(0, priority: 10);
      final next = worker.record(1, priority: 0);
      expect(await first.timeout(const Duration(seconds: 30)), isNotNull);
      expect(await next.timeout(const Duration(seconds: 30)), isNotNull,
          reason:
              'page 0\'s late cancel must be ignored while page 1 is active');
      expect(isolate_worker.debugPdfRenderWorkerIgnoredStaleCancels, 1);
    });
  });

  test('pool routes binStrips by the static page index', () async {
    final workers = [for (var i = 0; i < 3; i++) _BinLogWorker()];
    final pool = PdfPooledRenderWorker.fromWorkers(workers);
    addTearDown(pool.dispose);

    await pool.binStrips(4,
        annotations: true,
        pageToDevice: const [1, 0, 0, 1, 0, 0],
        deviceWidth: 10,
        deviceHeight: 10,
        pixelRatio: 1);
    expect(workers[4 % 3].binCalls, [4]);
    expect(workers[0].binCalls, isEmpty);
    expect(workers[2].binCalls, isEmpty);

    pool.cancelBinStrips(4, priority: 7);
    expect(workers[4 % 3].binCancels, [(4, 7)]);
    expect(workers[0].binCancels, isEmpty);
  });

  test('pool keeps record and detail phases on one page-affine worker',
      () async {
    final workers = [for (var i = 0; i < 3; i++) _BinLogWorker()];
    final pool = PdfPooledRenderWorker.fromWorkers(workers);
    addTearDown(pool.dispose);

    await pool.record(4, priority: 7, decodeImages: false);
    await pool.record(4, priority: 0, decodeImages: true);
    await pool.binStrips(4,
        annotations: true,
        pageToDevice: const [1, 0, 0, 1, 0, 0],
        deviceWidth: 10,
        deviceHeight: 10,
        pixelRatio: 1);

    expect(workers[1].recordCalls, [(4, 7), (4, 0)]);
    expect(workers[1].binCalls, [4]);
    expect(workers[0].recordCalls, isEmpty);
    expect(workers[2].recordCalls, isEmpty);
  });

  test('caching wrapper passes bins straight through (never cached)', () async {
    final inner = _BinLogWorker();
    final caching = PdfCachingRenderWorker(inner);
    addTearDown(caching.dispose);

    Future<StripPlan?> bin() => caching.binStrips(2,
        annotations: true,
        pageToDevice: const [1, 0, 0, 1, 0, 0],
        deviceWidth: 10,
        deviceHeight: 10,
        pixelRatio: 1);
    await bin();
    await bin(); // identical args - still no caching
    expect(inner.binCalls, [2, 2]);

    caching.cancelBinStrips(2, priority: 3);
    expect(inner.binCancels, [(2, 3)]);
  });

  test('pool routes buildRegionIndex by the static page index', () async {
    final workers = [for (var i = 0; i < 3; i++) _BinLogWorker()];
    final pool = PdfPooledRenderWorker.fromWorkers(workers);
    addTearDown(pool.dispose);

    await pool.buildRegionIndex(4,
        annotations: true, maxCommands: 1000, buildGrid: true);
    expect(workers[4 % 3].regionIndexCalls, [4]);
    expect(workers[0].regionIndexCalls, isEmpty);
    expect(workers[2].regionIndexCalls, isEmpty);
  });

  test('caching wrapper passes buildRegionIndex straight through', () async {
    final inner = _BinLogWorker();
    final caching = PdfCachingRenderWorker(inner);
    addTearDown(caching.dispose);

    Future<PdfRegionReplayIndex?> build() => caching.buildRegionIndex(2,
        annotations: true, maxCommands: 1000, buildGrid: true);
    await build();
    await build(); // identical args - still no caching (index is scene-memoized)
    expect(inner.regionIndexCalls, [2, 2]);
  });

  test('the abstract default declines (stub/web behavior)', () async {
    final worker = _DefaultWorker();
    final plan = await worker.binStrips(0,
        annotations: true,
        pageToDevice: const [1, 0, 0, 1, 0, 0],
        deviceWidth: 10,
        deviceHeight: 10,
        pixelRatio: 1);
    expect(plan, isNull);
    final detail = await worker.recordStripDetail(
      0,
      annotations: true,
      pageToDevice: const [1, 0, 0, 1, 0, 0],
      deviceWidth: 10,
      deviceHeight: 10,
      pixelRatio: 1,
      imageDecodeRegion: const PdfRect(0, 0, 10, 10),
    );
    expect(detail, isNull);
    final index = await worker.buildRegionIndex(0,
        annotations: true, maxCommands: 1000, buildGrid: true);
    expect(index, isNull);
    worker.cancelBinStrips(0); // must be a harmless no-op
  });
}

/// Minimal fake that logs binStrips traffic and returns an empty plan.
class _BinLogWorker extends PdfRenderWorker {
  final recordCalls = <(int, int)>[];
  final binCalls = <int>[];
  final binCancels = <(int, int)>[];
  final regionIndexCalls = <int>[];

  @override
  bool get isActive => true;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial}) async {
    recordCalls.add((pageIndex, priority));
    return null;
  }

  @override
  Future<StripPlan?> binStrips(
    int pageIndex, {
    required bool annotations,
    required List<double> pageToDevice,
    required int deviceWidth,
    required int deviceHeight,
    required double pixelRatio,
    bool slugGlyphs = false,
    int priority = 0,
  }) async {
    binCalls.add(pageIndex);
    return StripPlan(
      totalFlushPoints: 0,
      deviceWidth: deviceWidth,
      deviceHeight: deviceHeight,
      pageToDevice: PdfMatrix(pageToDevice[0], pageToDevice[1], pageToDevice[2],
          pageToDevice[3], pageToDevice[4], pageToDevice[5]),
      tolerance: stripFlattenTolerance,
      batches: const [],
      slugGlyphs: slugGlyphs,
    );
  }

  @override
  Future<PdfRegionReplayIndex?> buildRegionIndex(
    int pageIndex, {
    required bool annotations,
    required int maxCommands,
    required bool buildGrid,
    int priority = 0,
  }) async {
    regionIndexCalls.add(pageIndex);
    return null;
  }

  @override
  void cancelBinStrips(int pageIndex, {int priority = 0}) =>
      binCancels.add((pageIndex, priority));

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}

/// Overrides nothing strip-related: exercises the abstract class defaults
/// the stub and web backends inherit.
class _DefaultWorker extends PdfRenderWorker {
  @override
  bool get isActive => false;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
          {bool annotations = true,
          int priority = 0,
          double? imagePixelRatio,
          bool decodeImages = true,
          int? commandLimit,
          PdfRect? imageDecodeRegion,
          PdfPartialRecordSink? onPartial}) async =>
      null;

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}
