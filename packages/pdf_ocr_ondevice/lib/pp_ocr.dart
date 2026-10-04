/// The web-safe core of `pdf_ocr_ondevice`: the PP-OCR detect-then-recognize
/// pipeline in plain Dart ([PpOcrPipeline]) over a pluggable network backend
/// ([PpOcrInference]), and the [OcrRunnerEngine] that turns its lines into a
/// `PdfOcrEngine`'s spans.
///
/// The package's main library adds native ONNX Runtime ([OnnxOcrModelRunner]),
/// the worker isolate and the model downloader, none of which compile for the
/// web. A browser build imports this library instead and supplies an
/// onnxruntime-web [PpOcrInference], so both platforms run the same pre- and
/// post-processing - and read a page the same way.
library;

export 'src/ctc_decode.dart';
export 'src/db_postprocess.dart' show DetectedBox, extractDetectionBoxes;
export 'src/ocr_image.dart';
export 'src/ocr_model_runner.dart';
export 'src/ocr_runner_engine.dart';
export 'src/pp_ocr_pipeline.dart';
export 'src/preprocess.dart';
export 'src/text_cleanup.dart';
