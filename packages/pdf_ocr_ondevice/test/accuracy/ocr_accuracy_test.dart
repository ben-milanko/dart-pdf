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
// PDF_OCR_RAW=1 skips cleanRecognizedText; PDF_OCR_ISOLATE=1 runs inference on
// the worker isolate the app uses (IsolateOcrModelRunner); and PDF_OCR_REAL_PDF +
// PDF_OCR_REAL_TRUTH also score a real page against a JSON truth list
// `[{"text": ..., "bounds": [l, b, r, t]}]` in user space (real drawings stay
// out of the repo). See doc/dev-log/2026-10-04-ocr-accuracy-benchmark.md.
import 'dart:convert';
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  final environment = Platform.environment;
  final modelDir = environment['PDF_OCR_MODEL_DIR'];
  final skip = modelDir == null ? 'set PDF_OCR_MODEL_DIR to run' : null;
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
    final runner = OnnxOcrModelRunner(
      detectionModelPath: '$modelDir/PP-OCRv5_mobile_det.onnx',
      recognitionModelPath: '$modelDir/PP-OCRv5_mobile_rec.onnx',
      dictionaryPath: '$modelDir/ppocrv5_dict.txt',
      detectionSideLimit: detSide,
      unclipRatio: unclip,
      boxScoreThreshold: boxThresh,
      detectionThreshold: detThresh,
      cleanText: cleanText,
    );
    final engine =
        OnDeviceOcrEngine(isolate ? IsolateOcrModelRunner(runner) : runner);
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
    // ignore: avoid_print
    print('$name @${pixelRatio.toStringAsFixed(2)}x det<=$detSide '
        'unclip $unclip box $boxThresh thr $detThresh'
        '${cleanText ? '' : ' raw'}${isolate ? ' isolate' : ''}: $score  '
        '(${clock.elapsedMilliseconds} ms, ${spans.length} spans)\n'
        '  misreads: ${score.misreads.take(25).map((m) => '${m.$1}->"${m.$2}"').join('  ')}');
  }

  test('synthetic drawing sheet', () async {
    final sheet = buildOcrDrawingSheet(
        File('../pdf_document/test/fonts/LiberationSans-Regular.ttf')
            .readAsBytesSync());
    await run('synthetic', PdfDocument.open(sheet.bytes), sheet.labels);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 10)));

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
      timeout: const Timeout(Duration(minutes: 10)));
}
