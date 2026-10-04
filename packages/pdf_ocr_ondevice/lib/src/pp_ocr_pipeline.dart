import 'dart:typed_data';

import 'ctc_decode.dart';
import 'db_postprocess.dart';
import 'ocr_image.dart';
import 'ocr_model_runner.dart';
import 'preprocess.dart';
import 'text_cleanup.dart';

/// A float tensor's elements (row-major) and its shape.
typedef OcrTensor = ({Float32List data, List<int> shape});

/// The two network calls of a PP-OCR pipeline - everything [PpOcrPipeline]
/// cannot do in plain Dart. Natively that is ONNX Runtime over FFI
/// ([OnnxOcrModelRunner]); in a browser it is onnxruntime-web behind a JS
/// bridge. Both run the same Dart pre- and post-processing around it, so the
/// platforms read a page identically.
abstract class PpOcrInference {
  /// Loads both networks and returns the recognizer's character dictionary
  /// file contents (one token per line). Called once, before the first
  /// [detect].
  Future<String> load();

  /// Runs the detection network on a `[1, 3, height, width]` NCHW [input];
  /// returns its `[1, 1, height, width]` probability map.
  Future<OcrTensor> detect(Float32List input, int width, int height);

  /// Runs the recognition network on a `[batch, 3, height, width]` NCHW
  /// [input] (lines zero-padded to a shared width); returns its
  /// `[batch, T, vocab]` per-timestep scores.
  Future<OcrTensor> recognize(
      Float32List input, int batch, int height, int width);

  /// Releases the networks.
  Future<void> dispose();
}

/// A PP-OCR-style detect-then-recognize pipeline over a [PpOcrInference]:
///
///   1. resize the page for detection ([detectionResize]) and normalize it
///      ([toNchwFloat32]);
///   2. run detection → a probability map, from which [extractDetectionBoxes]
///      derives text-line boxes (mapped back to the original raster);
///   3. crop each box, normalize it for recognition ([recognitionInput]), run
///      recognition, greedily CTC-decode ([CtcDecoder]) the scores against the
///      model's dictionary, and drop drawing symbols ([cleanRecognizedText]).
///
/// Pure Dart apart from the [inference] calls, so it compiles for the VM and
/// the web alike. The defaults are the ones the accuracy benchmark
/// (`test/accuracy/ocr_accuracy_test.dart`) chose; see the package README.
class PpOcrPipeline implements OcrModelRunner {
  PpOcrPipeline(
    this.inference, {
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

  /// The network backend.
  final PpOcrInference inference;

  /// Detection resizes the page so its longest side is at most this many
  /// pixels (rounded to a multiple of 32).
  final int detectionSideLimit;
  final List<double> detectionMean;
  final List<double> detectionStd;

  /// The recognizer's fixed input height (PP-OCRv5 = 48).
  final int recognitionImageHeight;

  /// The narrowest recognition input; shorter lines are zero-padded to it.
  final int recognitionMinWidth;

  /// A safety cap on a recognition input's width.
  final int recognitionMaxWidth;

  /// Lines recognized per network call. Lines are sorted by aspect ratio and
  /// batched like PaddleOCR's `TextRecognizer` (its default is 6), so each
  /// batch pads only to its own widest line; one call per line costs a
  /// browser a WASM round trip each (~400 per drawing).
  final int recognitionBatchSize;
  final double detectionThreshold;
  final double boxScoreThreshold;
  final double unclipRatio;

  /// Whether the recognizer emits raw logits rather than softmax
  /// probabilities (see [CtcDecoder.applySoftmax]).
  final bool recognitionEmitsLogits;

  /// Whether each line goes through [cleanRecognizedText].
  final bool cleanText;

  /// Called during [recognize] with the fraction of the page done so far
  /// (detection counts as the first 10%, then each line). For a progress UI.
  void Function(double fraction)? onProgress;

  CtcDecoder? _decoder;
  Future<void>? _loading;

  @override
  Future<void> load() => _loading ??=
          _load().then((_) {}, onError: (Object error, StackTrace stack) {
        _loading = null; // a failed load can be retried
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _load() async {
    final dictionary = await inference.load();
    _decoder = CtcDecoder(parseDictionary(dictionary),
        applySoftmax: recognitionEmitsLogits);
  }

  @override
  Future<List<RecognizedTextLine>> recognize(OcrImage image) async {
    final decoder = _decoder;
    if (decoder == null) {
      throw StateError('PpOcrPipeline.load() must run before recognize()');
    }

    // --- detection ---
    final size = detectionResize(image.width, image.height,
        sideLimit: detectionSideLimit);
    final resized = image.resize(size.width, size.height);
    final detInput =
        toNchwFloat32(resized, mean: detectionMean, std: detectionStd);
    final probMap =
        (await inference.detect(detInput, size.width, size.height)).data;
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
    onProgress?.call(0.1);

    // --- recognition, in aspect-sorted batches ---
    int scaledWidth(DetectedBox box) {
      final r = box.rect;
      final h = r.height <= 0 ? 1.0 : r.height;
      return (r.width * recognitionImageHeight / h)
          .round()
          .clamp(1, recognitionMaxWidth);
    }

    final order = [for (var i = 0; i < boxes.length; i++) i]..sort((a, b) =>
        (boxes[a].rect.width / boxes[a].rect.height)
            .compareTo(boxes[b].rect.width / boxes[b].rect.height));
    final texts = List<RecognizedTextLine?>.filled(boxes.length, null);
    final batchSize = recognitionBatchSize < 1 ? 1 : recognitionBatchSize;
    var done = 0;
    for (var start = 0; start < order.length; start += batchSize) {
      final batch = order.sublist(start,
          start + batchSize > order.length ? order.length : start + batchSize);
      var width = recognitionMinWidth;
      for (final i in batch) {
        final w = scaledWidth(boxes[i]);
        if (w > width) width = w;
      }
      final plane = 3 * recognitionImageHeight * width;
      final tensor = Float32List(batch.length * plane);
      for (var k = 0; k < batch.length; k++) {
        final input = recognitionInput(image.crop(boxes[batch[k]].rect),
            targetHeight: recognitionImageHeight,
            minWidth: width,
            maxWidth: recognitionMaxWidth);
        tensor.setRange(k * plane, (k + 1) * plane, input.tensor);
      }
      final scores = await inference.recognize(
          tensor, batch.length, recognitionImageHeight, width);
      done += batch.length;
      onProgress?.call(0.1 + 0.9 * done / boxes.length);
      final vocab = scores.shape.isEmpty ? 0 : scores.shape.last;
      if (vocab <= 0) continue;
      final perLine = scores.data.length ~/ batch.length;
      for (var k = 0; k < batch.length; k++) {
        final result = decoder.decode(
            Float32List.sublistView(
                scores.data, k * perLine, (k + 1) * perLine),
            perLine ~/ vocab,
            vocab);
        final text = cleanText ? cleanRecognizedText(result.text) : result.text;
        if (text == null || text.trim().isEmpty) continue;
        texts[batch[k]] = RecognizedTextLine(
          text: text,
          pixelBounds: boxes[batch[k]].rect,
          confidence: result.confidence,
        );
      }
    }
    // Back in detection (reading) order.
    final lines = [
      for (final line in texts)
        if (line != null) line,
    ];
    return lines;
  }

  @override
  Future<void> dispose() async {
    final loading = _loading;
    _loading = null;
    _decoder = null;
    if (loading != null) await inference.dispose();
  }
}
