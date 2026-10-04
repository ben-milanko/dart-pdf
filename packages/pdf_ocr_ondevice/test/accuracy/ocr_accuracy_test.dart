// Opt-in OCR accuracy benchmark: runs the real PP-OCR model over a synthetic
// drawing sheet with known labels (pdf_test_fixtures' buildOcrDrawingSheet)
// and prints exact-match / CER. Skipped unless PDF_OCR_MODEL_DIR points at a
// directory holding the ocr-models-v1 files (PP-OCRv5_mobile_det.onnx,
// PP-OCRv5_mobile_rec.onnx, ppocrv5_dict.txt). On Linux ONNX Runtime needs the
// pub package's library on the loader path:
//
//   LD_LIBRARY_PATH=~/.pub-cache/hosted/pub.dev/onnxruntime-1.4.1/linux \
//   PDF_OCR_MODEL_DIR=/path/to/models fvm flutter test test/accuracy
//
// Optional: PDF_OCR_PIXEL_RATIO (default OnDeviceOcrEngine.pixelRatioFor, what
// the app uses); PDF_OCR_DET_SIDE / PDF_OCR_UNCLIP / PDF_OCR_BOX_THRESH /
// PDF_OCR_DET_THRESH override the runner's detection knobs for a sweep;
// PDF_OCR_RAW=1 skips cleanRecognizedText; PDF_OCR_SHOW=<text> prints how
// every label containing <text> was read; PDF_OCR_ISOLATE=1 runs inference on
// the worker isolate the app uses (IsolateOcrModelRunner); PDF_OCR_WEB_BRIDGE=<url>
// runs the same PpOcrPipeline against the web app's onnxruntime-web bridge
// instead of native ONNX Runtime (start it with app/tool/perf/ocr_web_bridge.mjs;
// PDF_OCR_MODEL_DIR is then not needed); and PDF_OCR_REAL_PDF +
// PDF_OCR_REAL_TRUTH also score a real page against a JSON truth list
// `[{"text": ..., "bounds": [l, b, r, t]}]` in user space (real drawings stay
// out of the repo). See doc/dev-log/2026-10-04-ocr-accuracy-benchmark.md.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  final environment = Platform.environment;
  final modelDir = environment['PDF_OCR_MODEL_DIR'];
  final webBridge = environment['PDF_OCR_WEB_BRIDGE'];
  final skip = modelDir == null && webBridge == null
      ? 'set PDF_OCR_MODEL_DIR or PDF_OCR_WEB_BRIDGE to run'
      : null;
  double? env(String name) => double.tryParse(environment[name] ?? '');
  final defaults = OnnxOcrModelRunner(
      detectionModelPath: '', recognitionModelPath: '', dictionaryPath: '');
  final detSide =
      env('PDF_OCR_DET_SIDE')?.round() ?? defaults.detectionSideLimit;
  final unclip = env('PDF_OCR_UNCLIP') ?? defaults.unclipRatio;
  final boxThresh = env('PDF_OCR_BOX_THRESH') ?? defaults.boxScoreThreshold;
  final detThresh = env('PDF_OCR_DET_THRESH') ?? defaults.detectionThreshold;
  final cleanText = environment['PDF_OCR_RAW'] != '1';
  final isolate = environment['PDF_OCR_ISOLATE'] == '1';

  Future<void> run(
      String name, PdfDocument doc, List<OcrTruthLabel> truth) async {
    final OcrModelRunner runner = webBridge != null
        ? PpOcrPipeline(
            _BridgeInference(Uri.parse(webBridge)),
            detectionSideLimit: detSide,
            unclipRatio: unclip,
            boxScoreThreshold: boxThresh,
            detectionThreshold: detThresh,
            cleanText: cleanText,
          )
        : OnnxOcrModelRunner(
            detectionModelPath: '$modelDir/PP-OCRv5_mobile_det.onnx',
            recognitionModelPath: '$modelDir/PP-OCRv5_mobile_rec.onnx',
            dictionaryPath: '$modelDir/ppocrv5_dict.txt',
            detectionSideLimit: detSide,
            unclipRatio: unclip,
            boxScoreThreshold: boxThresh,
            detectionThreshold: detThresh,
            cleanText: cleanText,
          );
    final engine = OcrRunnerEngine(
        isolate ? IsolateOcrModelRunner(runner as OnnxOcrModelRunner) : runner);
    final pdfPage = doc.page(0);
    final pixelRatio =
        env('PDF_OCR_PIXEL_RATIO') ?? OnDeviceOcrEngine.pixelRatioFor(pdfPage);
    final page = await const PdfRendererOcrRasterizer()
        .rasterize(pdfPage, pageIndex: 0, pixelRatio: pixelRatio);
    final clock = Stopwatch()..start();
    final spans = await engine.recognize(page);
    clock.stop();
    page.dispose();
    await engine.dispose();
    final score = scoreOcrAccuracy(truth, [
      for (final s in spans)
        (
          text: s.text,
          left: s.bounds.left,
          bottom: s.bounds.bottom,
          right: s.bounds.right,
          top: s.bounds.top,
        ),
    ]);
    final show = environment['PDF_OCR_SHOW'];
    if (show != null) {
      for (final (want, read) in score.readings) {
        // ignore: avoid_print
        if (want.contains(show)) print('  $want -> "$read"');
      }
    }
    // ignore: avoid_print
    print('$name @${pixelRatio.toStringAsFixed(2)}x det<=$detSide '
        'unclip $unclip box $boxThresh thr $detThresh'
        '${cleanText ? '' : ' raw'}${isolate ? ' isolate' : ''}'
        '${webBridge != null ? ' web' : ''}: $score  '
        '(${clock.elapsedMilliseconds} ms, ${spans.length} spans)\n'
        '  misreads: ${score.misreads.take(25).map((m) => '${m.$1}->"${m.$2}"').join('  ')}');
  }

  test('synthetic drawing sheet', () async {
    final sheet = buildOcrDrawingSheet(
        File('../pdf_document/test/fonts/LiberationSans-Regular.ttf')
            .readAsBytesSync());
    await run('synthetic', PdfDocument.open(sheet.bytes), sheet.labels);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 30)));

  final realPdf = environment['PDF_OCR_REAL_PDF'];
  final realTruth = environment['PDF_OCR_REAL_TRUTH'];
  test('real page', () async {
    final truth = [
      for (final e in jsonDecode(File(realTruth!).readAsStringSync()) as List)
        OcrTruthLabel.fromJson(e as Map<String, Object?>),
    ];
    await run(
        'real', PdfDocument.open(File(realPdf!).readAsBytesSync()), truth);
  },
      skip: skip ??
          (realPdf == null || realTruth == null ? 'no real page' : null),
      timeout: const Timeout(Duration(minutes: 30)));
}

/// The web app's onnxruntime-web bridge, reached through
/// app/tool/perf/ocr_web_bridge.mjs.
class _BridgeInference implements PpOcrInference {
  _BridgeInference(this.base);

  final Uri base;
  final _client = HttpClient();

  @override
  Future<String> load() async {
    final request = await _client.postUrl(base.resolve('api/load'));
    final response = await request.close();
    return response.transform(utf8.decoder).join();
  }

  @override
  Future<OcrTensor> detect(Float32List input, int width, int height) =>
      _run('det', input, [1, 3, height, width]);

  @override
  Future<OcrTensor> recognize(
          Float32List input, int batch, int height, int width) =>
      _run('rec', input, [batch, 3, height, width]);

  Future<OcrTensor> _run(String name, Float32List input, List<int> dims) async {
    final request = await _client
        .postUrl(base.resolve('api/run/$name').replace(queryParameters: {
      'dims': dims.join(','),
    }));
    request.add(
        input.buffer.asUint8List(input.offsetInBytes, input.lengthInBytes));
    final response = await request.close();
    final bytes = await response.fold<BytesBuilder>(
        BytesBuilder(copy: false), (b, chunk) => b..add(chunk));
    if (response.statusCode != 200) {
      throw StateError('bridge $name: HTTP ${response.statusCode} '
          '${utf8.decode(bytes.takeBytes(), allowMalformed: true)}');
    }
    final shape =
        response.headers.value('x-dims')!.split(',').map(int.parse).toList();
    // A fresh, 4-byte-aligned copy: the chunk takeBytes hands back can be a
    // view into a larger buffer, and viewing that buffer whole would read
    // past the tensor.
    final body = Uint8List.fromList(bytes.takeBytes());
    return (data: body.buffer.asFloat32List(), shape: shape);
  }

  @override
  Future<void> dispose() async => _client.close(force: true);
}
