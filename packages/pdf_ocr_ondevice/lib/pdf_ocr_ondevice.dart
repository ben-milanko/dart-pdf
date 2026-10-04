/// On-device, downloadable OCR for [`dart_pdf_editor`](https://pub.dev/packages/dart_pdf_editor).
///
/// Implements `PdfOcrEngine` so `PdfEditor.applyOcr` can add a selectable,
/// searchable, invisible text layer over scanned PDF pages - running entirely
/// on the device, with no per-page network call. The (small, ~21 MB) PP-OCR
/// model is downloaded once via [PdfOcrModelManager] and then runs locally on
/// ONNX Runtime.
///
/// This library needs the native platforms (Android, iOS, macOS, Windows,
/// Linux). For the web, `package:pdf_ocr_ondevice/pp_ocr.dart` is the same
/// pipeline without the native runtime - supply an onnxruntime-web
/// [PpOcrInference] (the DartPDF app's `web/index.html` bridge is one).
///
/// ```dart
/// final manager = PdfOcrModelManager();
/// final model = PdfOcrModels.ppOcrV5Mobile;
/// if (!await manager.isDownloaded(model)) {
///   await manager.download(model, onProgress: (p) => print(p.fraction));
/// }
/// final engine = await OnDeviceOcrEngine.fromDownloadedModel(manager, model);
/// final editor = PdfEditor(PdfDocument.open(bytes));
/// await editor.applyOcr(0, engine);
/// await engine.dispose();
/// ```
library;

export 'src/ctc_decode.dart';
export 'src/db_postprocess.dart' show DetectedBox, extractDetectionBoxes;
export 'src/isolate_ocr_model_runner.dart';
export 'src/model_manager.dart';
export 'src/ocr_image.dart';
export 'src/ocr_model.dart';
export 'src/ocr_model_runner.dart';
export 'src/ondevice_ocr_engine.dart';
export 'src/ocr_runner_engine.dart';
export 'src/onnx_ocr_model_runner.dart';
export 'src/pp_ocr_pipeline.dart';
export 'src/preprocess.dart';
export 'src/text_cleanup.dart';
