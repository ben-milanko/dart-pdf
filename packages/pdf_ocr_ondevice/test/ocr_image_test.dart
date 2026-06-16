import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

/// A `w` x `h` image whose red channel encodes `x` and green encodes `y`.
OcrImage _gradient(int w, int h) {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      rgba[i] = x;
      rgba[i + 1] = y;
      rgba[i + 2] = 0;
      rgba[i + 3] = 255;
    }
  }
  return OcrImage(rgba: rgba, width: w, height: h);
}

void main() {
  test('crop copies the requested sub-rectangle', () {
    final img = _gradient(10, 10);
    final crop = img.crop(const Rect.fromLTWH(3, 4, 4, 2));
    expect(crop.width, 4);
    expect(crop.height, 2);
    // Top-left of the crop is original (3, 4).
    expect(crop.pixel(0, 0).r, 3);
    expect(crop.pixel(0, 0).g, 4);
    expect(crop.pixel(3, 1).r, 6);
    expect(crop.pixel(3, 1).g, 5);
  });

  test('crop clamps to image bounds', () {
    final img = _gradient(8, 8);
    final crop = img.crop(const Rect.fromLTWH(6, 6, 10, 10));
    expect(crop.width, lessThanOrEqualTo(2));
    expect(crop.height, lessThanOrEqualTo(2));
  });

  test('resize preserves corner colours (bilinear)', () {
    final img = _gradient(8, 8);
    final up = img.resize(16, 16);
    expect(up.width, 16);
    expect(up.height, 16);
    // Top-left corner stays near (0,0); bottom-right near (7,7).
    expect(up.pixel(0, 0).r, lessThan(2));
    expect(up.pixel(15, 15).r, greaterThan(5));
    expect(up.pixel(15, 15).g, greaterThan(5));
  });
}
