// Release Chrome A/B benchmark for #243. Run with
// `bash tool/cad_web_spatial_replay_benchmark.sh` from the example directory.
import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const _cadUrl = String.fromEnvironment('CAD_PERF_URL');
const _page = int.fromEnvironment('CAD_PERF_PAGE', defaultValue: 20);
const _samples = int.fromEnvironment('CAD_PERF_SAMPLES', defaultValue: 5);
final _ratio =
    double.tryParse(const String.fromEnvironment('CAD_PERF_RATIO')) ?? 3.4;
final _minSpeedup = double.tryParse(
      const String.fromEnvironment('CAD_PERF_MIN_SPEEDUP'),
    ) ??
    1.15;
final _maxCommandFraction = double.tryParse(
      const String.fromEnvironment('CAD_PERF_MAX_COMMAND_FRACTION'),
    ) ??
    .70;

void main() => runApp(const _BenchmarkApp());

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
    print('web-spatial-replay-benchmark: $value');
    if (mounted) setState(() => _status = value);
  }

  Future<void> _run() async {
    final previous = PdfRetainedScene.spatialRegionReplay;
    PdfRenderWorker? worker;
    PdfRetainedScene? scene;
    try {
      if (_cadUrl.isEmpty) throw StateError('CAD_PERF_URL is required');
      if (_samples < 3) throw StateError('CAD_PERF_SAMPLES must be >= 3');
      _report('loading $_cadUrl');
      final response = await web.window.fetch(_cadUrl.toJS).toDart;
      if (!response.ok) throw StateError('HTTP ${response.status}: $_cadUrl');
      final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
      final document = PdfDocument.open(bytes);
      final pageIndex = _page.clamp(0, document.pageCount - 1);
      final page = document.page(pageIndex);
      worker = PdfRenderWorker.startUncached(bytes);
      final commands = await worker.record(
        pageIndex,
        annotations: true,
        decodeImages: false,
      );
      if (commands == null) throw StateError('worker recording declined');
      scene = await PdfRetainedScene.fromCommands(
        page,
        commands,
        includeImages: false,
      );
      final size = scene.pageSize;
      final regions = _panRegions(size, _samples + 1);

      final buildClock = Stopwatch()..start();
      final supported = scene.debugRegionReplaySupported;
      buildClock.stop();
      if (!supported) throw StateError('page is not spatial-index compatible');
      final indexUnits = scene.debugRegionReplayUnitCount;
      final indexBytes = scene.debugRegionReplayEstimatedBytes;

      // Warm Skia/text caches in both modes on a region excluded from samples.
      await _sample(scene, regions.first, false);
      await _sample(scene, regions.first, true);

      final full = <double>[];
      final selective = <double>[];
      final selectedCounts = <int>[];
      for (var i = 0; i < _samples; i++) {
        _report('sample ${i + 1}/$_samples');
        final region = regions[i + 1];
        if (i.isEven) {
          full.add(await _sample(scene, region, false));
          selective.add(await _sample(scene, region, true));
          selectedCounts.add(scene.debugLastRegionReplayCommandCount);
        } else {
          selective.add(await _sample(scene, region, true));
          selectedCounts.add(scene.debugLastRegionReplayCommandCount);
          full.add(await _sample(scene, region, false));
        }
      }

      // One byte-for-byte region comparison in the same release runtime.
      final compareRegion = regions.last;
      PdfRetainedScene.spatialRegionReplay = false;
      final expected = await scene.rasterizeRegion(
        compareRegion,
        pixelRatio: _ratio,
      );
      PdfRetainedScene.spatialRegionReplay = true;
      final actual = await scene.rasterizeRegion(
        compareRegion,
        pixelRatio: _ratio,
      );
      final expectedBytes =
          await expected.toByteData(format: ui.ImageByteFormat.rawRgba);
      final actualBytes =
          await actual.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixelEqual = _equalBytes(
        expectedBytes!.buffer.asUint8List(),
        actualBytes!.buffer.asUint8List(),
      );
      expected.dispose();
      actual.dispose();

      final fullP90 = _percentile(full, .9);
      final selectiveP90 = _percentile(selective, .9);
      final speedup = fullP90 / selectiveP90;
      final worstSelected = selectedCounts.reduce(math.max);
      final commandFraction = worstSelected / math.max(1, commands.length);
      final result = 'page=${pageIndex + 1} ratio=$_ratio samples=$_samples\n'
          'commands=${commands.length} units=$indexUnits '
          'indexKB=${(indexBytes / 1024).toStringAsFixed(1)} '
          'buildMs=${buildClock.elapsedMicroseconds / 1000}\n'
          'full ms=${_list(full)} p90=${fullP90.toStringAsFixed(1)}\n'
          'selective ms=${_list(selective)} p90=${selectiveP90.toStringAsFixed(1)}\n'
          'selected=$selectedCounts worstFraction=${commandFraction.toStringAsFixed(3)}\n'
          'p90 speedup=${speedup.toStringAsFixed(2)}x '
          'reduction=${((1 - selectiveP90 / fullP90) * 100).toStringAsFixed(1)}%\n'
          'pixelEqual=$pixelEqual';
      await _publish('RESULT\n$result');
      if (!pixelEqual) throw StateError('selective pixels differ');
      if (speedup < _minSpeedup) {
        throw StateError('speedup ${speedup.toStringAsFixed(2)}x is below '
            'the ${_minSpeedup}x gate');
      }
      if (commandFraction > _maxCommandFraction) {
        throw StateError(
            'command fraction ${commandFraction.toStringAsFixed(3)} '
            'exceeds the $_maxCommandFraction gate');
      }
      _report('PASS\n$result\nPress q in the terminal to stop.');
    } catch (error, stack) {
      await _publish('ERROR\n$error\n$stack');
      _report('FAIL: $error');
    } finally {
      scene?.dispose();
      worker?.dispose();
      PdfRetainedScene.spatialRegionReplay = previous;
    }
  }

  Future<double> _sample(
    PdfRetainedScene scene,
    ui.Rect region,
    bool selective,
  ) async {
    PdfRetainedScene.spatialRegionReplay = selective;
    final clock = Stopwatch()..start();
    final image = await scene.rasterizeRegion(region, pixelRatio: _ratio);
    await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    clock.stop();
    return clock.elapsedMicroseconds / 1000;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF202124),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'dart-pdf spatial replay benchmark\n\n$_status',
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
    '/__cad_web_spatial_replay_benchmark__?result=${Uri.encodeQueryComponent(result)}',
  );
  await web.window.fetch(endpoint.toString().toJS).toDart;
}

List<ui.Rect> _panRegions(ui.Size size, int count) {
  final width = size.width * .44;
  final height = size.height * .44;
  final maxLeft = math.max(0.0, size.width - width);
  final maxTop = math.max(0.0, size.height - height);
  return List.generate(count, (i) {
    final t = count == 1 ? 0.0 : i / (count - 1);
    final y = (.5 + .5 * math.sin(t * math.pi * 2)) * maxTop;
    return ui.Rect.fromLTWH(t * maxLeft, y, width, height);
  });
}

double _percentile(List<double> values, double p) {
  final sorted = [...values]..sort();
  return sorted[((sorted.length - 1) * p).ceil()];
}

String _list(List<double> values) =>
    '[${values.map((value) => value.toStringAsFixed(1)).join(', ')}]';

bool _equalBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
