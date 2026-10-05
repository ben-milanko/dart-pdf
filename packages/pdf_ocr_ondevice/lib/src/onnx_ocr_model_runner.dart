import 'dart:io';
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'ocr_image.dart';
import 'ocr_model_runner.dart';
import 'ort_tensor_data.dart';
import 'pp_ocr_pipeline.dart';
import 'text_cleanup.dart';

/// An [OcrModelRunner] that runs the PP-OCR detect-then-recognize pipeline
/// ([PpOcrPipeline]) on [ONNX Runtime](https://onnxruntime.ai) over FFI.
///
/// Everything except the two `OrtSession.run` calls is the shared, plain-Dart
/// [PpOcrPipeline] - the same code the web build runs over onnxruntime-web -
/// and this class wires those calls to the native runtime. ONNX Runtime ships
/// prebuilt for Android, iOS, macOS, Windows, and Linux, so one Dart path
/// covers every supported platform.
class OnnxOcrModelRunner implements OcrModelRunner {
  OnnxOcrModelRunner({
    required this.detectionModelPath,
    required this.recognitionModelPath,
    required this.dictionaryPath,
    this.detectionSideLimit = 4000,
    this.detectionMean = const [0.485, 0.456, 0.406],
    this.detectionStd = const [0.229, 0.224, 0.225],
    this.recognitionImageHeight = 48,
    this.recognitionMinWidth = 320,
    this.recognitionMaxWidth = 3200,
    this.recognitionBatchSize = 6,
    this.detectionThreshold = 0.3,
    this.boxScoreThreshold = 0.6,
    this.unclipRatio = 1.5,
    this.recognitionEmitsLogits = false,
    this.cleanText = true,
  });

  final String detectionModelPath;
  final String recognitionModelPath;
  final String dictionaryPath;

  final int detectionSideLimit;
  final List<double> detectionMean;
  final List<double> detectionStd;
  final int recognitionImageHeight;

  /// The narrowest recognition input; shorter lines are zero-padded to it
  /// (PP-OCR's 320). Longer lines keep their own aspect-preserving width.
  final int recognitionMinWidth;

  /// A safety cap on a recognition input's width: a crop that would scale
  /// wider is squeezed to it. Not a padding width - lines keep their aspect
  /// below it.
  final int recognitionMaxWidth;

  /// Lines per recognition call (see [PpOcrPipeline.recognitionBatchSize]).
  final int recognitionBatchSize;
  final double detectionThreshold;
  final double boxScoreThreshold;
  final double unclipRatio;

  /// Set this when the recognition model emits raw logits rather than softmax
  /// probabilities, so confidences are softmaxed before use. PaddleOCR's
  /// exported PP-OCR rec model already ends in a softmax, so the default is
  /// false; flip it for a logits-only export.
  final bool recognitionEmitsLogits;

  /// Whether each line goes through [cleanRecognizedText] - drawing symbols
  /// (● ▲ ▼ ...) removed, symbol-only lines dropped. On by default; turn it off
  /// to see the recognizer's raw output.
  final bool cleanText;

  late final PpOcrPipeline _pipeline = PpOcrPipeline(
    _FfiInference(this),
    detectionSideLimit: detectionSideLimit,
    detectionMean: detectionMean,
    detectionStd: detectionStd,
    recognitionImageHeight: recognitionImageHeight,
    recognitionMinWidth: recognitionMinWidth,
    recognitionMaxWidth: recognitionMaxWidth,
    recognitionBatchSize: recognitionBatchSize,
    detectionThreshold: detectionThreshold,
    boxScoreThreshold: boxScoreThreshold,
    unclipRatio: unclipRatio,
    recognitionEmitsLogits: recognitionEmitsLogits,
    cleanText: cleanText,
  );

  @override
  Future<void> load() => _pipeline.load();

  @override
  Future<List<RecognizedTextLine>> recognize(OcrImage image) =>
      _pipeline.recognize(image);

  @override
  Future<void> dispose() => _pipeline.dispose();
}

/// The [PpOcrInference] over native ONNX Runtime sessions.
class _FfiInference implements PpOcrInference {
  _FfiInference(this._runner);

  final OnnxOcrModelRunner _runner;
  OrtSession? _det;
  OrtSession? _rec;

  @override
  Future<String> load() async {
    OrtEnv.instance.init();
    final options = OrtSessionOptions();
    // Hand ONNX Runtime the model *bytes*, not a path. `OrtSession.fromFile`
    // passes the path as a narrow UTF-8 `char*`, but on Windows ONNX Runtime's
    // `CreateSession` expects a wide `ORTCHAR_T*` (`wchar_t`/UTF-16). The UTF-8
    // bytes are reinterpreted as UTF-16, which mangles *every* path - even a
    // pure-ASCII one (e.g. `C:` → `㩃`) - into CJK mojibake and surfaces as the
    // "Load model from … failed. File doesn't exist" error. Reading the bytes
    // with Dart's own file API (which uses the wide Windows APIs internally)
    // and using `fromBuffer`/`CreateSessionFromArray` keeps the path off the
    // native boundary entirely, so this works on every platform regardless of
    // where the models are stored.
    _det = OrtSession.fromBuffer(
        await File(_runner.detectionModelPath).readAsBytes(), options);
    _rec = OrtSession.fromBuffer(
        await File(_runner.recognitionModelPath).readAsBytes(), options);
    return File(_runner.dictionaryPath).readAsString();
  }

  @override
  Future<OcrTensor> detect(Float32List input, int width, int height) =>
      _run(_det, input, [1, 3, height, width]);

  @override
  Future<OcrTensor> recognize(
          Float32List input, int batch, int height, int width) =>
      _run(_rec, input, [batch, 3, height, width]);

  Future<OcrTensor> _run(
      OrtSession? session, Float32List input, List<int> shape) async {
    if (session == null) {
      throw StateError('OnnxOcrModelRunner.load() must run before recognize()');
    }
    final tensor = OrtValueTensor.createTensorWithDataList(input, shape);
    final runOptions = OrtRunOptions();
    try {
      final outputs = await session
          .runAsync(runOptions, {session.inputNames.first: tensor});
      try {
        final first = outputs?.first;
        final fast = first == null ? null : readFloatTensor(first);
        if (fast != null) return fast;
        final value = first?.value;
        return (data: _flatten(value), shape: _innerShape(value));
      } finally {
        _release(outputs);
      }
    } finally {
      tensor.release();
      runOptions.release();
    }
  }

  @override
  Future<void> dispose() async {
    _det?.release();
    _rec?.release();
    _det = null;
    _rec = null;
  }

  /// Flattens ONNX Runtime's nested `List` output into a [Float32List].
  static Float32List _flatten(Object? value) {
    final out = <double>[];
    void walk(Object? v) {
      if (v is num) {
        out.add(v.toDouble());
      } else if (v is List) {
        for (final e in v) {
          walk(e);
        }
      }
    }

    walk(value);
    return Float32List.fromList(out);
  }

  /// The dimensions of a nested `List` (the tensor shape), e.g. `[1, T, C]`.
  static List<int> _innerShape(Object? value) {
    final dims = <int>[];
    Object? cur = value;
    while (cur is List && cur.isNotEmpty) {
      dims.add(cur.length);
      cur = cur.first;
    }
    return dims;
  }

  static void _release(List<OrtValue?>? outputs) {
    if (outputs == null) return;
    for (final o in outputs) {
      o?.release();
    }
  }
}
