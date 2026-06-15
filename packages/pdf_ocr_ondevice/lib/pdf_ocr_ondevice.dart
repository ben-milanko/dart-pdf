/// On-device, downloadable OCR for [`dart_pdf_editor`](https://pub.dev/packages/dart_pdf_editor).
///
/// Implements `PdfOcrEngine` so `PdfEditor.applyOcr` can add a selectable,
/// searchable, invisible text layer over scanned PDF pages — running entirely
/// on the device, with no per-page network call. The (small, ~21 MB) PP-OCR
/// model is downloaded once via [PdfOcrModelManager] and then runs locally on
/// ONNX Runtime.
///
/// Supported on the native platforms (Android, iOS, macOS, Windows, Linux);
/// on the web use the HTTP-backed `pdf_ocr_vlm` engine instead.
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
export 'src/model_manager.dart';
export 'src/ocr_image.dart';
export 'src/ocr_model.dart';
export 'src/ocr_model_runner.dart';
export 'src/ondevice_ocr_engine.dart';
export 'src/onnx_ocr_model_runner.dart';
export 'src/preprocess.dart';
