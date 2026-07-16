// Release Chrome A/B benchmark for #241. Run with
// `bash tool/cad_web_transcript_benchmark.sh` from the example directory.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

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
    1.10;

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
    print('web-transcript-benchmark: $value');
    if (mounted) setState(() => _status = value);
  }

  Future<void> _run() async {
    final previousReuseTranscripts = pdfRenderWorkerReuseTranscripts;
    try {
      if (_cadUrl.isEmpty) throw StateError('CAD_PERF_URL is required');
      if (_samples < 3) throw StateError('CAD_PERF_SAMPLES must be >= 3');
      _report('loading $_cadUrl');
      final response = await web.window.fetch(_cadUrl.toJS).toDart;
      if (!response.ok) throw StateError('HTTP ${response.status}: $_cadUrl');
      final buffer = await response.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      final baseline = <_Sample>[];
      final reused = <_Sample>[];
      for (var i = 0; i < _samples; i++) {
        _report('sample ${i + 1}/$_samples');
        if (i.isEven) {
          baseline.add(await _sample(bytes, false));
          reused.add(await _sample(bytes, true));
        } else {
          reused.add(await _sample(bytes, true));
          baseline.add(await _sample(bytes, false));
        }
      }
      final baselineFull = baseline.map((s) => s.fullMs).toList();
      final reusedFull = reused.map((s) => s.fullMs).toList();
      final baselineTotal = baseline.map((s) => s.totalMs).toList();
      final reusedTotal = reused.map((s) => s.totalMs).toList();
      final baseP90 = _percentile(baselineFull, .9);
      final reusedP90 = _percentile(reusedFull, .9);
      final baselineTotalP90 = _percentile(baselineTotal, .9);
      final reusedTotalP90 = _percentile(reusedTotal, .9);
      final speedup = baseP90 / reusedP90;
      final result = 'page=${_page + 1} ratio=$_ratio samples=$_samples\n'
          'baseline full ms=${_list(baselineFull)} p90=${baseP90.toStringAsFixed(1)}\n'
          'reused   full ms=${_list(reusedFull)} p90=${reusedP90.toStringAsFixed(1)}\n'
          'baseline total ms=${_list(baselineTotal)} p90=${baselineTotalP90.toStringAsFixed(1)}\n'
          'reused   total ms=${_list(reusedTotal)} p90=${reusedTotalP90.toStringAsFixed(1)}\n'
          'full-phase p90 speedup=${speedup.toStringAsFixed(2)}x '
          'reduction=${((1 - reusedP90 / baseP90) * 100).toStringAsFixed(1)}%\n'
          'sequence p90 speedup=${(baselineTotalP90 / reusedTotalP90).toStringAsFixed(2)}x '
          'reduction=${((1 - reusedTotalP90 / baselineTotalP90) * 100).toStringAsFixed(1)}%';
      await _publish('RESULT\n$result');
      if (speedup < _minSpeedup) {
        throw StateError('speedup ${speedup.toStringAsFixed(2)}x is below '
            'the ${_minSpeedup}x gate');
      }
      _report('PASS\n$result\nPress q in the terminal to stop.');
    } catch (error, stack) {
      await _publish('ERROR\n$error\n$stack');
      _report('FAIL: $error');
    } finally {
      pdfRenderWorkerReuseTranscripts = previousReuseTranscripts;
    }
  }

  Future<_Sample> _sample(Uint8List bytes, bool reuse) async {
    pdfRenderWorkerReuseTranscripts = reuse;
    final worker = PdfRenderWorker.startUncached(bytes);
    try {
      final total = Stopwatch()..start();
      final vector = Stopwatch()..start();
      final first = await worker.record(_page, decodeImages: false);
      if (first == null) throw StateError('vector record declined');
      vector.stop();
      final full = Stopwatch()..start();
      final second = await worker.record(
        _page,
        decodeImages: true,
        imagePixelRatio: _ratio,
      );
      if (second == null) throw StateError('full record declined');
      full.stop();
      total.stop();
      return _Sample(
        vector.elapsedMicroseconds / 1000,
        full.elapsedMicroseconds / 1000,
        total.elapsedMicroseconds / 1000,
      );
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
                'dart-pdf web transcript benchmark\n\n$_status',
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
    '/__cad_web_transcript_benchmark__?result=${Uri.encodeQueryComponent(result)}',
  );
  await web.window.fetch(endpoint.toString().toJS).toDart;
}

class _Sample {
  const _Sample(this.vectorMs, this.fullMs, this.totalMs);
  final double vectorMs;
  final double fullMs;
  final double totalMs;
}

double _percentile(List<double> values, double p) {
  final sorted = [...values]..sort();
  return sorted[((sorted.length - 1) * p).ceil()];
}

String _list(List<double> values) =>
    '[${values.map((v) => v.toStringAsFixed(1)).join(', ')}]';
