import 'package:pdf_document/pdf_document.dart' show PdfPage;

import 'isolate_ocr_model_runner.dart';
import 'model_manager.dart';
import 'ocr_model.dart';
import 'ocr_model_runner.dart';
import 'ocr_runner_engine.dart';
import 'onnx_ocr_model_runner.dart';

/// A [PdfOcrEngine] that recognizes pages **on device**, with no network call
/// at recognition time - the model is downloaded once (see
/// [PdfOcrModelManager]) and then runs locally.
///
/// The page geometry and span mapping are [OcrRunnerEngine]'s; this adds the
/// native, downloaded-model construction.
///
/// Use [OnDeviceOcrEngine.fromDownloadedModel] for the batteries-included
/// path (PP-OCR on ONNX Runtime from a downloaded [PdfOcrModel]), or the
/// default constructor to plug in any runner.
class OnDeviceOcrEngine extends OcrRunnerEngine {
  OnDeviceOcrEngine(super.runner, {super.minConfidence});

  /// See [OcrRunnerEngine.pixelRatioFor].
  static double pixelRatioFor(
    PdfPage page, {
    double target = 3,
    int maxSidePixels = 4000,
  }) =>
      OcrRunnerEngine.pixelRatioFor(page,
          target: target, maxSidePixels: maxSidePixels);

  /// Builds an engine that runs [model] from files already downloaded by
  /// [manager] on ONNX Runtime. Throws [PdfOcrModelException] if the model is
  /// not downloaded. Inference runs on a long-lived worker isolate by default;
  /// set [useWorkerIsolate] false only to debug it on the calling isolate.
  static Future<OnDeviceOcrEngine> fromDownloadedModel(
    PdfOcrModelManager manager,
    PdfOcrModel model, {
    double minConfidence = 0,
    bool useWorkerIsolate = true,
  }) async {
    final files = await manager.localFiles(model);
    final onnxRunner = OnnxOcrModelRunner(
      detectionModelPath: files[model.detection.name]!.path,
      recognitionModelPath: files[model.recognition.name]!.path,
      dictionaryPath: files[model.dictionary.name]!.path,
      detectionSideLimit: model.detectionSideLimit,
      detectionMean: model.detectionMean,
      detectionStd: model.detectionStd,
      recognitionImageHeight: model.recognitionImageHeight,
    );
    final OcrModelRunner runner = useWorkerIsolate
        ? IsolateOcrModelRunner(onnxRunner, debugName: 'pdf-ocr-${model.id}')
        : onnxRunner;
    return OnDeviceOcrEngine(runner, minConfidence: minConfidence);
  }
}
