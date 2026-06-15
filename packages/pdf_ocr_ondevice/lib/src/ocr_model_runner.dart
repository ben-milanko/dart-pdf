import 'package:flutter/painting.dart';

import 'ocr_image.dart';

/// One recognized text line: the characters and where they sit in the page
/// raster's **pixel** space (top-left origin, y down — the same space the OCR
/// model worked in). [OnDeviceOcrEngine] maps [pixelBounds] back to PDF user
/// space.
class RecognizedTextLine {
  const RecognizedTextLine({
    required this.text,
    required this.pixelBounds,
    this.confidence = 1.0,
  });

  final String text;
  final Rect pixelBounds;
  final double confidence;
}

/// The inference backend behind [OnDeviceOcrEngine]: turns a rasterized page
/// into recognized text lines.
///
/// The default backend ([OnnxOcrModelRunner]) runs a PP-OCR detect+recognize
/// pipeline on ONNX Runtime, but the engine takes any implementation — so a
/// platform-native recognizer (Vision / ML Kit / Windows OCR) or a test fake
/// can stand in without touching the engine or the page-geometry mapping.
abstract class OcrModelRunner {
  /// Loads the model (sessions, dictionary). Called once before the first
  /// [recognize]; safe to call again (must be idempotent).
  Future<void> load();

  /// Recognizes every text line in [image], returning each with its
  /// pixel-space bounds and confidence.
  Future<List<RecognizedTextLine>> recognize(OcrImage image);

  /// Releases native resources.
  Future<void> dispose();
}
