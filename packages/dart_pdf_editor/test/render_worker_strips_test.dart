// The binStrips worker protocol:
//
//  - native isolate end-to-end: a worker-binned StripPlan is bit-identical
//    to a local StripPlanBinner run over the same worker-recorded command
//    buffer (the worker re-records in its own isolate and round-trips
//    through the wire codec, so geometry carries the same float32
//    truncation as the buffer the caller's scene holds);
//  - the isolate queue's kind-scoped cancel (cancelBinStrips drops queued
//    bins without touching queued records, and vice versa);
//  - cancelBinStrips also preempts a matching IN-FLIGHT bin (the worker
//    abandons it mid-walk and the future resolves null) - what lets a
//    newer speculative/settle geometry supersede a running stale bin;
//  - pool routing by the STATIC page index (worker-side command-cache
//    affinity) for both binStrips and cancelBinStrips;
//  - the caching wrapper passes bins straight through (plans are never
//    cached - every settle has a fresh matrix);
//  - the abstract default (which the stub and web backends inherit)
//    declines with null.
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';

import 'render_seam_test.dart' show buildStripsPdf;
import 'strip_zoom_router_test.dart' show buildVectorPdf;

List<double> _coeffs(PdfMatrix m) => [m.a, m.b, m.c, m.d, m.e, m.f];

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

Uint8List _buildTwoPageDenseVectorPdf({int rects = 8000}) {
  final dense = StringBuffer();
  for (var i = 0; i < rects; i++) {
    dense.write('${(i % 10) / 10} 0 0 rg '
        '${(i * 7) % 550} ${(i * 13) % 730} 8 6 re f ');
  }
  const urgent = '0 0 1 rg 20 20 100 100 re f';
  final body = dense.toString();
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 5 0 R /Resources << >> >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 6 0 R /Resources << >> >>',
    '<< /Length ${body.length} >>\nstream\n$body\nendstream',
    '<< /Length ${urgent.length} >>\nstream\n$urgent\nendstream',
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
    worker.cancelBinStrips(0); // must be a harmless no-op
  });
}

/// Minimal fake that logs binStrips traffic and returns an empty plan.
class _BinLogWorker extends PdfRenderWorker {
  final binCalls = <int>[];
  final binCancels = <(int, int)>[];

  @override
  bool get isActive => true;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
          {bool annotations = true,
          int priority = 0,
          double? imagePixelRatio,
          bool decodeImages = true,
          int? commandLimit,
          PdfRect? imageDecodeRegion}) async =>
      null;

  @override
  Future<StripPlan?> binStrips(
    int pageIndex, {
    required bool annotations,
    required List<double> pageToDevice,
    required int deviceWidth,
    required int deviceHeight,
    required double pixelRatio,
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
    );
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
          PdfRect? imageDecodeRegion}) async =>
      null;

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}
