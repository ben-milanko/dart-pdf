import 'dart:io';
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'ctc_decode.dart';
import 'db_postprocess.dart';
import 'ocr_image.dart';
import 'ocr_model_runner.dart';
import 'preprocess.dart';

/// An [OcrModelRunner] that runs a PP-OCR-style detect-then-recognize
/// pipeline on [ONNX Runtime](https://onnxruntime.ai).
///
/// Pipeline per page:
///   1. resize the page for detection ([detectionResize]) and normalize it
///      ([toNchwFloat32]);
///   2. run the detection network → a probability map, from which
///      [extractDetectionBoxes] derives text-line boxes (mapped back to the
///      original raster);
///   3. crop each box, normalize it for recognition ([recognitionInput]), run
///      the recognition network, and greedily CTC-decode ([CtcDecoder]) the
///      logits against the model's dictionary.
///
/// Everything except the two `OrtSession.run` calls is plain Dart and unit
/// tested; this class wires those pieces to the native runtime. ONNX Runtime
/// ships prebuilt for Android, iOS, macOS, Windows, and Linux, so one Dart
/// path covers every supported platform.
class OnnxOcrModelRunner implements OcrModelRunner {
  OnnxOcrModelRunner({
    required this.detectionModelPath,
    required this.recognitionModelPath,
    required this.dictionaryPath,
    this.runtimeModelDirectory,
    this.detectionSideLimit = 960,
    this.detectionMean = const [0.485, 0.456, 0.406],
    this.detectionStd = const [0.229, 0.224, 0.225],
    this.recognitionImageHeight = 48,
    this.recognitionMaxWidth = 512,
    this.detectionThreshold = 0.3,
    this.boxScoreThreshold = 0.5,
    this.unclipRatio = 1.6,
    this.recognitionEmitsLogits = false,
  });

  final String detectionModelPath;
  final String recognitionModelPath;
  final String dictionaryPath;

  /// Optional directory used to stage model files for ONNX Runtime.
  ///
  /// This is primarily for tests. On Windows, some ONNX Runtime builds fail to
  /// open model paths containing non-ASCII user/profile characters because the
  /// path is handed through the native boundary as a narrow string. The runner
  /// therefore copies model files to an ASCII-only staging directory before
  /// constructing native sessions.
  final Directory? runtimeModelDirectory;
  final int detectionSideLimit;
  final List<double> detectionMean;
  final List<double> detectionStd;
  final int recognitionImageHeight;
  final int recognitionMaxWidth;
  final double detectionThreshold;
  final double boxScoreThreshold;
  final double unclipRatio;

  /// Set this when the recognition model emits raw logits rather than softmax
  /// probabilities, so confidences are softmaxed before use. PaddleOCR's
  /// exported PP-OCR rec model already ends in a softmax, so the default is
  /// false; flip it for a logits-only export.
  final bool recognitionEmitsLogits;

  OrtSession? _det;
  OrtSession? _rec;
  CtcDecoder? _decoder;

  @override
  Future<void> load() async {
    if (_det != null) return;
    OrtEnv.instance.init();
    final options = OrtSessionOptions();
    final paths = await _runtimePaths(
      detectionModelPath: detectionModelPath,
      recognitionModelPath: recognitionModelPath,
      dictionaryPath: dictionaryPath,
      stagingDirectory: runtimeModelDirectory,
    );
    _det = OrtSession.fromFile(File(paths.detection), options);
    _rec = OrtSession.fromFile(File(paths.recognition), options);
    final dict = await File(paths.dictionary).readAsString();
    _decoder =
        CtcDecoder(parseDictionary(dict), applySoftmax: recognitionEmitsLogits);
  }

  static Future<({String detection, String recognition, String dictionary})>
      runtimePathsForTesting({
    required String detectionModelPath,
    required String recognitionModelPath,
    required String dictionaryPath,
    Directory? stagingDirectory,
    bool forceWindowsStaging = false,
  }) =>
          _runtimePaths(
            detectionModelPath: detectionModelPath,
            recognitionModelPath: recognitionModelPath,
            dictionaryPath: dictionaryPath,
            stagingDirectory: stagingDirectory,
            forceWindowsStaging: forceWindowsStaging,
          );

  static Future<({String detection, String recognition, String dictionary})>
      _runtimePaths({
    required String detectionModelPath,
    required String recognitionModelPath,
    required String dictionaryPath,
    Directory? stagingDirectory,
    bool forceWindowsStaging = false,
  }) async {
    if (!forceWindowsStaging && !Platform.isWindows) {
      return (
        detection: detectionModelPath,
        recognition: recognitionModelPath,
        dictionary: dictionaryPath,
      );
    }

    final sourcePaths = [
      detectionModelPath,
      recognitionModelPath,
      dictionaryPath
    ];
    if (sourcePaths.every(_isAsciiPath)) {
      return (
        detection: detectionModelPath,
        recognition: recognitionModelPath,
        dictionary: dictionaryPath,
      );
    }

    final root = stagingDirectory ?? await _defaultRuntimeModelDirectory();
    await root.create(recursive: true);
    if (!_isAsciiPath(root.path)) {
      throw FileSystemException(
        'OCR model staging directory must contain only ASCII characters '
        'on Windows',
        root.path,
      );
    }

    final det = await _copyForRuntime(detectionModelPath, root,
        'detection-${_stableSuffix(detectionModelPath)}.onnx');
    final rec = await _copyForRuntime(recognitionModelPath, root,
        'recognition-${_stableSuffix(recognitionModelPath)}.onnx');
    final dict = await _copyForRuntime(dictionaryPath, root,
        'dictionary-${_stableSuffix(dictionaryPath)}.txt');
    return (detection: det.path, recognition: rec.path, dictionary: dict.path);
  }

  static Future<Directory> _defaultRuntimeModelDirectory() async {
    for (final envName in const ['PROGRAMDATA', 'TEMP', 'TMP']) {
      final value = Platform.environment[envName];
      if (value == null || value.isEmpty || !_isAsciiPath(value)) continue;
      final dir =
          Directory('$value${Platform.pathSeparator}dart_pdf_ocr_runtime');
      try {
        await dir.create(recursive: true);
        return dir;
      } catch (_) {
        // Try the next candidate.
      }
    }
    return Directory('${Directory.current.path}${Platform.pathSeparator}'
        '.dart_pdf_ocr_runtime');
  }

  static Future<File> _copyForRuntime(
      String sourcePath, Directory targetDir, String targetName) async {
    final source = File(sourcePath);
    final target =
        File('${targetDir.path}${Platform.pathSeparator}$targetName');
    if (await target.exists() &&
        await target.length() == await source.length()) {
      return target;
    }
    final part = File('${target.path}.part');
    if (await part.exists()) await part.delete();
    await source.copy(part.path);
    if (await target.exists()) await target.delete();
    return part.rename(target.path);
  }

  static bool _isAsciiPath(String path) =>
      path.codeUnits.every((unit) => unit <= 0x7f);

  static String _stableSuffix(String path) {
    var hash = 0x811c9dc5;
    for (final unit in path.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  @override
  Future<List<RecognizedTextLine>> recognize(OcrImage image) async {
    final det = _det;
    final rec = _rec;
    final decoder = _decoder;
    if (det == null || rec == null || decoder == null) {
      throw StateError('OnnxOcrModelRunner.load() must run before recognize()');
    }

    // --- detection ---
    final size = detectionResize(image.width, image.height,
        sideLimit: detectionSideLimit);
    final resized = image.resize(size.width, size.height);
    final detInput =
        toNchwFloat32(resized, mean: detectionMean, std: detectionStd);
    final probMap = await _runDetection(det, detInput, size.width, size.height);
    final boxes = extractDetectionBoxes(
      probMap,
      size.width,
      size.height,
      threshold: detectionThreshold,
      boxScoreThreshold: boxScoreThreshold,
      unclipRatio: unclipRatio,
      scaleX: size.scaleX,
      scaleY: size.scaleY,
    );

    // --- recognition (one crop at a time) ---
    final lines = <RecognizedTextLine>[];
    for (final box in boxes) {
      final crop = image.crop(box.rect);
      final input = recognitionInput(crop,
          targetHeight: recognitionImageHeight, maxWidth: recognitionMaxWidth);
      final (predictions: predictions, timesteps: t, vocab: v) =
          await _runRecognition(
              rec, input.tensor, recognitionImageHeight, recognitionMaxWidth);
      final result = decoder.decode(predictions, t, v);
      if (result.text.trim().isEmpty) continue;
      lines.add(RecognizedTextLine(
        text: result.text,
        pixelBounds: box.rect,
        confidence: result.confidence,
      ));
    }
    return lines;
  }

  Future<Float32List> _runDetection(
      OrtSession session, Float32List input, int width, int height) async {
    final tensor =
        OrtValueTensor.createTensorWithDataList(input, [1, 3, height, width]);
    final runOptions = OrtRunOptions();
    try {
      final outputs = await session
          .runAsync(runOptions, {session.inputNames.first: tensor});
      final out = _flatten(outputs?.first?.value);
      _release(outputs);
      // The detection output is [1, 1, H, W]; the flat order matches the map.
      return out;
    } finally {
      tensor.release();
      runOptions.release();
    }
  }

  Future<({Float32List predictions, int timesteps, int vocab})> _runRecognition(
      OrtSession session, Float32List input, int height, int width) async {
    final tensor =
        OrtValueTensor.createTensorWithDataList(input, [1, 3, height, width]);
    final runOptions = OrtRunOptions();
    try {
      final outputs = await session
          .runAsync(runOptions, {session.inputNames.first: tensor});
      final raw = outputs?.first?.value;
      // Recognition output is [1, T, vocab].
      final shape = _innerShape(raw);
      final predictions = _flatten(raw);
      _release(outputs);
      final vocab = shape.last;
      final timesteps = vocab > 0 ? predictions.length ~/ vocab : 0;
      return (predictions: predictions, timesteps: timesteps, vocab: vocab);
    } finally {
      tensor.release();
      runOptions.release();
    }
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

  @override
  Future<void> dispose() async {
    _det?.release();
    _rec?.release();
    _det = null;
    _rec = null;
    _decoder = null;
  }
}
