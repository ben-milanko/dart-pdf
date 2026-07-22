// Release Chrome A/B benchmark for #242. Run with
// `bash tool/cad_web_cold_start_benchmark.sh` from the example directory.
//
// The separate worker-start experiment was rejected before selecting this
// policy: lazy pool startup regressed visible p90 403.8 -> 668.0 ms and warm
// p90 2135.0 -> 2830.7 ms (three alternating samples). Parallel worker open is
// therefore retained. This harness covers the selected second experiment:
// concurrent full refinement versus starting it after visible detail paints.
import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:web/web.dart' as web;

const _cadUrl = String.fromEnvironment('CAD_PERF_URL');
const _page = int.fromEnvironment('CAD_PERF_PAGE', defaultValue: 20);
const _samples = int.fromEnvironment('CAD_PERF_SAMPLES', defaultValue: 5);
final _ratio =
    double.tryParse(const String.fromEnvironment('CAD_PERF_RATIO')) ?? 3.4;
final _minVisibleSpeedup = double.tryParse(
      const String.fromEnvironment('CAD_PERF_MIN_VISIBLE_SPEEDUP'),
    ) ??
    1.10;
final _maxWarmRegression = double.tryParse(
      const String.fromEnvironment('CAD_PERF_MAX_WARM_REGRESSION'),
    ) ??
    1.10;

void main() {
  registerBundledEditorAssets();
  runApp(const _BenchmarkApp());
}

class _BenchmarkApp extends StatefulWidget {
  const _BenchmarkApp();

  @override
  State<_BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<_BenchmarkApp> {
  String _status = 'Starting…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _report(String value) {
    // ignore: avoid_print
    print('web-cold-start-benchmark: $value');
    if (mounted) setState(() => _status = value);
  }

  Future<void> _run() async {
    try {
      if (_cadUrl.isEmpty) throw StateError('CAD_PERF_URL is required');
      if (_samples < 3) throw StateError('CAD_PERF_SAMPLES must be >= 3');
      _report('loading $_cadUrl');
      final response = await web.window.fetch(_cadUrl.toJS).toDart;
      if (!response.ok) throw StateError('HTTP ${response.status}: $_cadUrl');
      final buffer = await response.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      final document = PdfDocument.open(bytes);
      final pageIndex = _page.clamp(0, document.pageCount - 1);
      final page = document.page(pageIndex);
      final size = PdfPageRenderer.pageSize(page);
      final region = ui.Rect.fromLTWH(
        size.width * .28,
        size.height * .28,
        size.width * .44,
        size.height * .44,
      );
      final baseline = <_Sample>[];
      final deferred = <_Sample>[];
      for (var i = 0; i < _samples; i++) {
        _report('sample ${i + 1}/$_samples');
        if (i.isEven) {
          baseline
              .add(await _sample(bytes, document, pageIndex, region, false));
          deferred.add(await _sample(bytes, document, pageIndex, region, true));
        } else {
          deferred.add(await _sample(bytes, document, pageIndex, region, true));
          baseline
              .add(await _sample(bytes, document, pageIndex, region, false));
        }
      }
      final baselineVisible =
          baseline.map((sample) => sample.visibleMs).toList();
      final deferredVisible =
          deferred.map((sample) => sample.visibleMs).toList();
      final baselineWarm = baseline.map((sample) => sample.warmMs).toList();
      final deferredWarm = deferred.map((sample) => sample.warmMs).toList();
      final baseVisibleP90 = _percentile(baselineVisible, .9);
      final deferredVisibleP90 = _percentile(deferredVisible, .9);
      final baseWarmP90 = _percentile(baselineWarm, .9);
      final deferredWarmP90 = _percentile(deferredWarm, .9);
      final visibleSpeedup = baseVisibleP90 / deferredVisibleP90;
      final warmRatio = deferredWarmP90 / baseWarmP90;
      final result = 'page=${pageIndex + 1} ratio=$_ratio samples=$_samples\n'
          'concurrent visible ms=${_list(baselineVisible)} p90=${baseVisibleP90.toStringAsFixed(1)}\n'
          'defer visible ms=${_list(deferredVisible)} p90=${deferredVisibleP90.toStringAsFixed(1)}\n'
          'concurrent warm ms=${_list(baselineWarm)} p90=${baseWarmP90.toStringAsFixed(1)}\n'
          'defer warm ms=${_list(deferredWarm)} p90=${deferredWarmP90.toStringAsFixed(1)}\n'
          'visible p90 speedup=${visibleSpeedup.toStringAsFixed(2)}x '
          'reduction=${((1 - deferredVisibleP90 / baseVisibleP90) * 100).toStringAsFixed(1)}%\n'
          'warm p90 ratio=${warmRatio.toStringAsFixed(2)}x';
      await _publish('RESULT\n$result');
      if (visibleSpeedup < _minVisibleSpeedup) {
        throw StateError(
            'visible speedup ${visibleSpeedup.toStringAsFixed(2)}x '
            'is below the ${_minVisibleSpeedup}x gate');
      }
      if (warmRatio > _maxWarmRegression) {
        throw StateError('warm ratio ${warmRatio.toStringAsFixed(2)}x exceeds '
            'the ${_maxWarmRegression}x regression gate');
      }
      _report('PASS\n$result\nPress q in the terminal to stop.');
    } catch (error, stack) {
      await _publish('ERROR\n$error\n$stack');
      _report('FAIL: $error');
    }
  }

  Future<_Sample> _sample(
    Uint8List bytes,
    PdfDocument document,
    int pageIndex,
    ui.Rect region,
    bool deferFull,
  ) async {
    final total = Stopwatch()..start();
    final worker = startPdfRenderWorker(
      bytes,
      pageCount: document.pageCount,
      workerCount: 3,
    );
    try {
      final vectorFuture = worker.record(
        pageIndex,
        priority: -100,
        decodeImages: false,
      );
      final neighbours = <Future<List<PdfRenderCommand>?>>[
        if (pageIndex > 0)
          worker.record(pageIndex - 1, priority: 1, imagePixelRatio: 1),
        if (pageIndex + 1 < document.pageCount)
          worker.record(pageIndex + 1, priority: 1, imagePixelRatio: 1),
      ];
      final vector = await vectorFuture;
      if (vector == null) throw StateError('vector record declined');
      final scene = await PdfRetainedScene.fromCommands(
        document.page(pageIndex),
        vector,
        includeImages: false,
      );
      try {
        final geometry = scene.stripRegionGeometry(region, pixelRatio: _ratio);
        final matrix = geometry.pageToDevice;
        final detailFuture = worker.recordStripDetail(
          pageIndex,
          annotations: true,
          pageToDevice: [
            matrix.a,
            matrix.b,
            matrix.c,
            matrix.d,
            matrix.e,
            matrix.f,
          ],
          deviceWidth: geometry.width,
          deviceHeight: geometry.height,
          pixelRatio: _ratio,
          imageDecodeRegion: _pdfRegion(document.page(pageIndex), region),
          priority: -1,
        );
        Future<List<PdfRenderCommand>?>? fullFuture;
        if (!deferFull) {
          fullFuture = worker.record(
            pageIndex,
            priority: 0,
            imagePixelRatio: _ratio,
          );
        }
        final detail = await detailFuture;
        if (detail == null) throw StateError('detail record declined');
        final detailScene = await PdfRetainedScene.fromCommands(
          document.page(pageIndex),
          detail.commands,
        );
        try {
          final image = await detailScene.rasterizeRegionStrips(
            region,
            pixelRatio: _ratio,
            stripPlan: detail.plan,
          );
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          image.dispose();
        } finally {
          detailScene.dispose();
        }
        final visibleMs = total.elapsedMicroseconds / 1000;
        fullFuture ??= worker.record(
          pageIndex,
          priority: 0,
          imagePixelRatio: _ratio,
        );
        await Future.wait([fullFuture, ...neighbours]);
        return _Sample(visibleMs, total.elapsedMicroseconds / 1000);
      } finally {
        scene.dispose();
      }
    } finally {
      worker.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF202124),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'dart-pdf web cold-start benchmark\n\n$_status',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ),
      );
}

Future<void> _publish(String result) async {
  final endpoint = Uri.parse(_cadUrl).resolve(
    '/__cad_web_cold_start_benchmark__?result=${Uri.encodeQueryComponent(result)}',
  );
  await web.window.fetch(endpoint.toString().toJS).toDart;
}

PdfRect _pdfRegion(PdfPage page, ui.Rect region) {
  final box = page.cropBox;
  final rotation = ((page.rotation % 360) + 360) % 360;
  final points = <(double, double)>[
    _pdfPoint(region.left, region.top, box, rotation),
    _pdfPoint(region.right, region.top, box, rotation),
    _pdfPoint(region.right, region.bottom, box, rotation),
    _pdfPoint(region.left, region.bottom, box, rotation),
  ];
  return PdfRect(
    points.map((point) => point.$1).reduce(math.min),
    points.map((point) => point.$2).reduce(math.min),
    points.map((point) => point.$1).reduce(math.max),
    points.map((point) => point.$2).reduce(math.max),
  );
}

(double, double) _pdfPoint(
  double x,
  double y,
  PdfRect box,
  int rotation,
) {
  final (u, v) = switch (rotation) {
    90 => (y, box.height - x),
    180 => (box.width - x, box.height - y),
    270 => (box.width - y, x),
    _ => (x, y),
  };
  return (box.left + u, box.top - v);
}

class _Sample {
  const _Sample(this.visibleMs, this.warmMs);
  final double visibleMs;
  final double warmMs;
}

double _percentile(List<double> values, double p) {
  final sorted = [...values]..sort();
  return sorted[((sorted.length - 1) * p).ceil()];
}

String _list(List<double> values) =>
    '[${values.map((value) => value.toStringAsFixed(1)).join(', ')}]';
