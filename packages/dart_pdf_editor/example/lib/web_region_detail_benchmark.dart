// Release-mode browser-worker A/B benchmark for #240.
//
// Run with `bash tool/cad_web_detail_benchmark.sh` from the example directory.
// The companion script serves the local CAD corpus with CORS enabled and
// launches this entrypoint in Chrome. The corpus PDF is never checked in.
import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:web/web.dart' as web;

const _cadUrl = String.fromEnvironment('CAD_PERF_URL');
const _cadPage = int.fromEnvironment('CAD_PERF_PAGE', defaultValue: 4);
final _ratio =
    double.tryParse(const String.fromEnvironment('CAD_PERF_RATIO')) ?? 3.4;
const _samples = int.fromEnvironment('CAD_PERF_SAMPLES', defaultValue: 5);
final _minSpeedup = double.tryParse(
      const String.fromEnvironment('CAD_PERF_MIN_SPEEDUP'),
    ) ??
    1.10;

void main() {
  PdfPerfLog.enabled = true;
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

  void _report(String status) {
    // ignore: avoid_print
    print('web-region-detail-benchmark: $status');
    if (mounted) setState(() => _status = status);
  }

  Future<void> _run() async {
    PdfRenderWorker? worker;
    PdfRetainedScene? baseScene;
    try {
      if (_cadUrl.isEmpty) throw StateError('CAD_PERF_URL is required');
      if (_samples < 3) throw StateError('CAD_PERF_SAMPLES must be >= 3');
      _report('loading $_cadUrl');
      final response = await web.window.fetch(_cadUrl.toJS).toDart;
      if (!response.ok) throw StateError('HTTP ${response.status}: $_cadUrl');
      final data = await response.arrayBuffer().toDart;
      final bytes = data.toDart.asUint8List();
      final document = PdfDocument.open(bytes);
      final pageIndex = _cadPage.clamp(0, document.pageCount - 1);
      final page = document.page(pageIndex);
      final size = PdfPageRenderer.pageSize(page);
      final regions = _panRegions(size, _samples + 1);
      _report(
        'opened ${(bytes.lengthInBytes / 1e6).toStringAsFixed(1)} MB, '
        '${document.pageCount} pages; warming page ${pageIndex + 1}',
      );

      worker = PdfRenderWorker.startUncached(bytes);
      if (!worker.isActive) throw StateError('web render worker unavailable');
      final baseCommands = await worker.record(
        pageIndex,
        annotations: true,
        decodeImages: false,
      );
      if (baseCommands == null) {
        throw StateError('page ${pageIndex + 1} declined worker recording');
      }
      baseScene = await PdfRetainedScene.fromCommands(page, baseCommands);
      await _warmStripCache(worker, pageIndex, page, size);

      _report('warming legacy and combined pan paths');
      await _legacyPanToSharp(worker, pageIndex, page, regions.first);
      await _combinedPanToSharp(
        worker,
        pageIndex,
        page,
        baseScene,
        regions.first,
      );

      final legacy = <double>[];
      final combined = <double>[];
      for (var i = 0; i < _samples; i++) {
        _report('sample ${i + 1}/$_samples');
        final region = regions[i + 1];
        if (i.isEven) {
          legacy.add(await _legacyPanToSharp(
            worker,
            pageIndex,
            page,
            region,
          ));
          combined.add(await _combinedPanToSharp(
            worker,
            pageIndex,
            page,
            baseScene,
            region,
          ));
        } else {
          combined.add(await _combinedPanToSharp(
            worker,
            pageIndex,
            page,
            baseScene,
            region,
          ));
          legacy.add(await _legacyPanToSharp(
            worker,
            pageIndex,
            page,
            region,
          ));
        }
      }

      final legacyMedian = _percentile(legacy, 0.5);
      final legacyP90 = _percentile(legacy, 0.9);
      final combinedMedian = _percentile(combined, 0.5);
      final combinedP90 = _percentile(combined, 0.9);
      final speedup = legacyP90 / combinedP90;
      final reduction = (1 - combinedP90 / legacyP90) * 100;
      final result = 'page=${pageIndex + 1} ratio=$_ratio samples=$_samples\n'
          'legacy   ms=${_list(legacy)} median=${legacyMedian.toStringAsFixed(1)} '
          'p90=${legacyP90.toStringAsFixed(1)}\n'
          'combined ms=${_list(combined)} '
          'median=${combinedMedian.toStringAsFixed(1)} '
          'p90=${combinedP90.toStringAsFixed(1)}\n'
          'p90 speedup=${speedup.toStringAsFixed(2)}x '
          'reduction=${reduction.toStringAsFixed(1)}%';
      // Stable markers make the result easy to retain in PRs and CI logs.
      // ignore: avoid_print
      print('CAD_WEB_DETAIL_BENCHMARK_RESULT\n$result');
      await _publishResult('RESULT\n$result');
      if (speedup < _minSpeedup) {
        throw StateError(
          'combined p90 did not meet the ${_minSpeedup}x material-speedup '
          'gate',
        );
      }
      _report('PASS\n$result\nPress q in the terminal to stop.');
    } catch (error, stack) {
      // ignore: avoid_print
      print('CAD_WEB_DETAIL_BENCHMARK_ERROR $error\n$stack');
      await _publishResult('ERROR\n$error\n$stack');
      _report('FAIL: $error');
    } finally {
      baseScene?.dispose();
      worker?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF202124),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Text(
                'dart-pdf web region-detail benchmark\n\n$_status',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      );
}

Future<void> _publishResult(String result) async {
  try {
    final endpoint = Uri.parse(_cadUrl).resolve(
      '/__cad_web_detail_benchmark__?result=${Uri.encodeQueryComponent(result)}',
    );
    await web.window.fetch(endpoint.toString().toJS).toDart;
  } catch (_) {
    // Console/on-screen output remains the fallback if the harness endpoint
    // is unavailable.
  }
}

Future<void> _warmStripCache(
  PdfRenderWorker worker,
  int pageIndex,
  PdfPage page,
  ui.Size size,
) async {
  final matrix = PdfPageRenderer.pageToDeviceMatrix(
    page,
    size,
    page.cropBox,
    pixelRatio: 1,
  );
  final plan = await worker.binStrips(
    pageIndex,
    annotations: true,
    pageToDevice: [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f],
    deviceWidth: size.width.ceil(),
    deviceHeight: size.height.ceil(),
    pixelRatio: 1,
  );
  if (plan == null) throw StateError('strip-cache warm declined');
}

Future<double> _legacyPanToSharp(
  PdfRenderWorker worker,
  int pageIndex,
  PdfPage page,
  ui.Rect region,
) async {
  final sw = Stopwatch()..start();
  final commands = await worker.record(
    pageIndex,
    annotations: true,
    imagePixelRatio: _ratio,
    imageDecodeRegion: _pdfRegion(page, region),
  );
  if (commands == null) throw StateError('legacy region record declined');
  final picture = await PdfPageRenderer.pictureFromCommands(page, commands);
  final image = await PdfPageRenderer.rasterizeRegion(
    picture,
    region,
    _ratio,
  );
  await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  sw.stop();
  return sw.elapsedMicroseconds / 1000;
}

Future<double> _combinedPanToSharp(
  PdfRenderWorker worker,
  int pageIndex,
  PdfPage page,
  PdfRetainedScene baseScene,
  ui.Rect region,
) async {
  final sw = Stopwatch()..start();
  final geometry = baseScene.stripRegionGeometry(
    region,
    pixelRatio: _ratio,
  );
  final matrix = geometry.pageToDevice;
  final detail = await worker.recordStripDetail(
    pageIndex,
    annotations: true,
    pageToDevice: [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f],
    deviceWidth: geometry.width,
    deviceHeight: geometry.height,
    pixelRatio: _ratio,
    imageDecodeRegion: _pdfRegion(page, region),
  );
  if (detail == null) throw StateError('combined detail request declined');
  final scene = await PdfRetainedScene.fromCommands(page, detail.commands);
  final image = await scene.rasterizeRegionStrips(
    region,
    pixelRatio: _ratio,
    stripPlan: detail.plan,
  );
  await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  scene.dispose();
  sw.stop();
  return sw.elapsedMicroseconds / 1000;
}

List<ui.Rect> _panRegions(ui.Size size, int count) {
  final width = size.width * 0.44;
  final height = size.height * 0.44;
  final maxLeft = math.max(0.0, size.width - width);
  final maxTop = math.max(0.0, size.height - height);
  return List.generate(count, (i) {
    final t = count == 1 ? 0.0 : i / (count - 1);
    final y = (0.5 + 0.5 * math.sin(t * math.pi * 2)) * maxTop;
    return ui.Rect.fromLTWH(t * maxLeft, y, width, height);
  });
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
  var left = points.first.$1;
  var right = left;
  var bottom = points.first.$2;
  var top = bottom;
  for (final point in points.skip(1)) {
    left = math.min(left, point.$1);
    right = math.max(right, point.$1);
    bottom = math.min(bottom, point.$2);
    top = math.max(top, point.$2);
  }
  return PdfRect(left, bottom, right, top);
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

double _percentile(List<double> samples, double percentile) {
  final sorted = [...samples]..sort();
  return sorted[((sorted.length - 1) * percentile).ceil()];
}

String _list(List<double> samples) =>
    '[${samples.map((v) => v.toStringAsFixed(1)).join(', ')}]';
