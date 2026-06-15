import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// A decoded RGBA raster in plain Dart memory — the form the OCR pipeline
/// works in, so all of its geometry/cropping/resizing is pure Dart and unit
/// testable off a GPU.
///
/// Pixels are row-major, 4 bytes (R, G, B, A) each, top-left origin, y down —
/// the same convention as `ui.Image.toByteData(rawRgba)` and an OCR model's
/// pixel boxes.
class OcrImage {
  OcrImage({required this.rgba, required this.width, required this.height})
      : assert(rgba.length == width * height * 4, 'rgba size mismatch');

  final Uint8List rgba;
  final int width;
  final int height;

  /// Reads a page raster off the GPU into an [OcrImage].
  static Future<OcrImage> fromUiImage(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw StateError('could not read the page raster');
    }
    return OcrImage(
      rgba: data.buffer.asUint8List(),
      width: image.width,
      height: image.height,
    );
  }

  /// The RGB value at integer pixel [x], [y] (clamped to the image).
  ({int r, int g, int b}) pixel(int x, int y) {
    final cx = x.clamp(0, width - 1);
    final cy = y.clamp(0, height - 1);
    final i = (cy * width + cx) * 4;
    return (r: rgba[i], g: rgba[i + 1], b: rgba[i + 2]);
  }

  /// A copy of the sub-rectangle [rect] (clamped to the image bounds).
  OcrImage crop(Rect rect) {
    final l = rect.left.floor().clamp(0, width - 1);
    final t = rect.top.floor().clamp(0, height - 1);
    final r = rect.right.ceil().clamp(l + 1, width);
    final b = rect.bottom.ceil().clamp(t + 1, height);
    final w = r - l;
    final h = b - t;
    final out = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      final srcRow = ((t + y) * width + l) * 4;
      out.setRange(y * w * 4, (y + 1) * w * 4,
          rgba.sublist(srcRow, srcRow + w * 4));
    }
    return OcrImage(rgba: out, width: w, height: h);
  }

  /// A bilinearly-resampled copy at [newWidth] x [newHeight].
  OcrImage resize(int newWidth, int newHeight) {
    final out = Uint8List(newWidth * newHeight * 4);
    final sx = width / newWidth;
    final sy = height / newHeight;
    for (var y = 0; y < newHeight; y++) {
      final fy = (y + 0.5) * sy - 0.5;
      final y0 = fy.floor().clamp(0, height - 1);
      final y1 = (y0 + 1).clamp(0, height - 1);
      final wy = (fy - y0).clamp(0.0, 1.0);
      for (var x = 0; x < newWidth; x++) {
        final fx = (x + 0.5) * sx - 0.5;
        final x0 = fx.floor().clamp(0, width - 1);
        final x1 = (x0 + 1).clamp(0, width - 1);
        final wx = (fx - x0).clamp(0.0, 1.0);
        final o = (y * newWidth + x) * 4;
        for (var c = 0; c < 4; c++) {
          final p00 = rgba[(y0 * width + x0) * 4 + c].toDouble();
          final p01 = rgba[(y0 * width + x1) * 4 + c].toDouble();
          final p10 = rgba[(y1 * width + x0) * 4 + c].toDouble();
          final p11 = rgba[(y1 * width + x1) * 4 + c].toDouble();
          final top = p00 + (p01 - p00) * wx;
          final bot = p10 + (p11 - p10) * wx;
          out[o + c] = (top + (bot - top) * wy).round().clamp(0, 255);
        }
      }
    }
    return OcrImage(rgba: out, width: newWidth, height: newHeight);
  }
}
