import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart' show PdfOcrSpan;

import 'model_manager.dart';
import 'ocr_image.dart';
import 'ocr_model.dart';
import 'ocr_model_runner.dart';
import 'onnx_ocr_model_runner.dart';

/// A [PdfOcrEngine] that recognizes pages **on device**, with no network call
/// at recognition time — the model is downloaded once (see
/// [PdfOcrModelManager]) and then runs locally.
///
/// The actual inference is delegated to an [OcrModelRunner]; the engine reads
/// the page raster into an [OcrImage], runs the backend, and maps each
/// recognized line's pixel box to PDF user space via
/// `PdfOcrPageImage.userSpaceRect`. So the engine itself (and the geometry it
/// owns) is independent of which recognizer runs.
///
/// Use [OnDeviceOcrEngine.fromDownloadedModel] for the batteries-included
/// path (PP-OCR on ONNX Runtime from a downloaded [PdfOcrModel]), or the
/// default constructor to plug in any runner.
class OnDeviceOcrEngine implements PdfOcrEngine {
  OnDeviceOcrEngine(this.runner, {this.minConfidence = 0});

  /// The inference backend.
  final OcrModelRunner runner;

  /// Lines below this confidence are dropped before mapping.
  final double minConfidence;

  bool _loaded = false;

  /// Builds an engine that runs [model] from files already downloaded by
  /// [manager] on ONNX Runtime. Throws [PdfOcrModelException] if the model is
  /// not downloaded.
  static Future<OnDeviceOcrEngine> fromDownloadedModel(
    PdfOcrModelManager manager,
    PdfOcrModel model, {
    double minConfidence = 0,
  }) async {
    final files = await manager.localFiles(model);
    final runner = OnnxOcrModelRunner(
      detectionModelPath: files[model.detection.name]!.path,
      recognitionModelPath: files[model.recognition.name]!.path,
      dictionaryPath: files[model.dictionary.name]!.path,
      detectionSideLimit: model.detectionSideLimit,
      detectionMean: model.detectionMean,
      detectionStd: model.detectionStd,
      recognitionImageHeight: model.recognitionImageHeight,
    );
    return OnDeviceOcrEngine(runner, minConfidence: minConfidence);
  }

  @override
  Future<List<PdfOcrSpan>> recognize(PdfOcrPageImage page) async {
    if (!_loaded) {
      await runner.load();
      _loaded = true;
    }
    final image = await OcrImage.fromUiImage(page.image);
    final lines = await runner.recognize(image);
    return [
      for (final line in lines)
        if (line.confidence >= minConfidence &&
            line.text.trim().isNotEmpty &&
            line.pixelBounds.width > 0 &&
            line.pixelBounds.height > 0)
          PdfOcrSpan(
            text: line.text,
            bounds: page.userSpaceRect(line.pixelBounds),
            confidence: line.confidence,
          ),
    ];
  }

  /// Releases the backend.
  Future<void> dispose() => runner.dispose();
}
