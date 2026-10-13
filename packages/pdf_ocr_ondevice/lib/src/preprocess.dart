import 'dart:typed_data';

import 'ocr_image.dart';

/// The target size and the per-axis scale factors of a detection resize.
///
/// PP-OCR-style detection resizes the page so its longest side is at most a
/// limit and both sides are multiples of 32 (the network stride), then works
/// in that resized space; [scaleX]/[scaleY] map a box found in resized pixels
/// back to the original image's pixels.
class DetectionResize {
  const DetectionResize({
    required this.width,
    required this.height,
    required this.scaleX,
    required this.scaleY,
  });

  final int width;
  final int height;

  /// Multiply a resized-space x by this to get original-space x.
  final double scaleX;

  /// Multiply a resized-space y by this to get original-space y.
  final double scaleY;
}

/// Computes the detection input size for an [srcWidth] x [srcHeight] page:
/// longest side scaled down to at most [sideLimit], each side rounded to a
/// multiple of [multiple] (and never below it). Pages already within the
/// limit are only rounded, never upscaled.
DetectionResize detectionResize(
  int srcWidth,
  int srcHeight, {
  int sideLimit = 4000,
  int multiple = 32,
}) {
  final longest = srcWidth > srcHeight ? srcWidth : srcHeight;
  final ratio = longest > sideLimit ? sideLimit / longest : 1.0;
  int round(double v) {
    final m = (v / multiple).round() * multiple;
    return m < multiple ? multiple : m;
  }

  final w = round(srcWidth * ratio);
  final h = round(srcHeight * ratio);
  return DetectionResize(
    width: w,
    height: h,
    scaleX: srcWidth / w,
    scaleY: srcHeight / h,
  );
}

/// Normalizes [image] into an NCHW float32 tensor (`[1, 3, height, width]`,
/// channel order R, G, B) using per-channel [mean] and [std] on the 0..1
/// range - the standard ImageNet-style detection input.
///
/// [image] must already be at the network's input size.
Float32List toNchwFloat32(
  OcrImage image, {
  List<double> mean = const [0.485, 0.456, 0.406],
  List<double> std = const [0.229, 0.224, 0.225],
}) {
  final w = image.width;
  final h = image.height;
  final out = Float32List(3 * h * w);
  final plane = h * w;
  final rgba = image.rgba;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = (y * w + x) * 4;
      final o = y * w + x;
      out[o] = (rgba[p] / 255.0 - mean[0]) / std[0];
      out[plane + o] = (rgba[p + 1] / 255.0 - mean[1]) / std[1];
      out[2 * plane + o] = (rgba[p + 2] / 255.0 - mean[2]) / std[2];
    }
  }
  return out;
}

/// Recognition preprocessing for one cropped text line: resize to the
/// network's fixed [targetHeight] keeping aspect, then normalize to NCHW
/// float32 in `[-1, 1]` (PP-OCR rec convention: `(pixel/255 - 0.5) / 0.5`).
///
/// The tensor is `paddedWidth` wide: the line's own width, but never less
/// than [minWidth] (zero-padded on the right, like PaddleOCR's
/// `resize_norm_img`, which pads to `max(320/48, w/h) * 48`). The recognizer
/// is fully convolutional along x, so a long line keeps its aspect instead of
/// being squeezed into a fixed width - squashing it is what turns legible
/// characters into a different string. [maxWidth] is only a safety cap on
/// pathological crops (the width it scales a wider line down to).
///
/// Returns the tensor, the width the line actually filled, and the tensor's
/// width.
({Float32List tensor, int width, int paddedWidth}) recognitionInput(
  OcrImage crop, {
  int targetHeight = 48,
  int minWidth = 320,
  int maxWidth = 3200,
}) {
  final scaledW =
      (crop.width * targetHeight / crop.height).round().clamp(1, maxWidth);
  final paddedW = scaledW > minWidth ? scaledW : minWidth;
  final resized = crop.resize(scaledW, targetHeight);
  final out = Float32List(3 * targetHeight * paddedW); // zero-padded
  final plane = targetHeight * paddedW;
  final rgba = resized.rgba;
  for (var y = 0; y < targetHeight; y++) {
    for (var x = 0; x < scaledW; x++) {
      final p = (y * scaledW + x) * 4;
      final o = y * paddedW + x;
      out[o] = (rgba[p] / 255.0 - 0.5) / 0.5;
      out[plane + o] = (rgba[p + 1] / 255.0 - 0.5) / 0.5;
      out[2 * plane + o] = (rgba[p + 2] / 255.0 - 0.5) / 0.5;
    }
  }
  return (tensor: out, width: scaledW, paddedWidth: paddedW);
}
