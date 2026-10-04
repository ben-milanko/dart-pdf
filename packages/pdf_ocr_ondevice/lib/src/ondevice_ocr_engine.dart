import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart' show PdfOcrSpan, PdfPage;

import 'isolate_ocr_model_runner.dart';
import 'model_manager.dart';
import 'ocr_image.dart';
import 'ocr_model.dart';
import 'ocr_model_runner.dart';
import 'onnx_ocr_model_runner.dart';

/// A [PdfOcrEngine] that recognizes pages **on device**, with no network call
/// at recognition time - the model is downloaded once (see
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

  /// The raster resolution (pixels per PDF point) to OCR [page] at: [target]
  /// (3 = 216 dpi) unless that would make the page's longest side exceed
  /// [maxSidePixels], in which case the ratio that fits it exactly.
  ///
  /// 216 dpi puts the ~5pt capitals of a drawing label at ~16 px - inside
  /// PP-OCR's working range, where 144 dpi (ratio 2) leaves them at ~11 px.
  /// The cap matches the detector's own side limit, so a large-format sheet
  /// is not rasterized only for detection to shrink it again, and it bounds
  /// the raster's memory (4000 x 2828 RGBA is ~45 MB; A0 at ratio 3 would be
  /// ~290 MB).
  static double pixelRatioFor(
    PdfPage page, {
    double target = 3,
    int maxSidePixels = 4000,
  }) {
    final box = page.cropBox;
    final longest = box.width > box.height ? box.width : box.height;
    if (longest <= 0) return target;
    final fit = maxSidePixels / longest;
    return fit < target ? fit : target;
  }

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
