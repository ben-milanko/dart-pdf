import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

OcrImage _solid(int w, int h, int r, int g, int b) {
  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    rgba[i * 4] = r;
    rgba[i * 4 + 1] = g;
    rgba[i * 4 + 2] = b;
    rgba[i * 4 + 3] = 255;
  }
  return OcrImage(rgba: rgba, width: w, height: h);
}

void main() {
  group('detectionResize', () {
    test('rounds each side to a multiple of 32 without upscaling', () {
      final r = detectionResize(600, 800, sideLimit: 960);
      expect(r.width % 32, 0);
      expect(r.height % 32, 0);
      // 600 -> 608 (19*32), 800 -> 800 (25*32).
      expect(r.width, 608);
      expect(r.height, 800);
      expect(r.scaleX, closeTo(600 / 608, 1e-9));
      expect(r.scaleY, closeTo(800 / 800, 1e-9));
    });

    test('scales the longest side down to the limit', () {
      final r = detectionResize(4000, 2000, sideLimit: 960);
      // longest 4000 -> ratio 0.24 -> 960 (already /32), 2000 -> 480.
      expect(r.width, 960);
      expect(r.height, 480);
      expect(r.scaleX, closeTo(4000 / 960, 1e-9));
    });

    test('never drops below the multiple', () {
      final r = detectionResize(10, 10, sideLimit: 960, multiple: 32);
      expect(r.width, 32);
      expect(r.height, 32);
    });
  });

  test('toNchwFloat32 lays channels out planar and normalizes', () {
    final img = _solid(2, 1, 255, 0, 0); // pure red
    final t = toNchwFloat32(img,
        mean: const [0.5, 0.5, 0.5], std: const [0.5, 0.5, 0.5]);
    expect(t.length, 3 * 1 * 2);
    // R plane: (1 - 0.5)/0.5 = 1.0
    expect(t[0], closeTo(1.0, 1e-6));
    expect(t[1], closeTo(1.0, 1e-6));
    // G plane: (0 - 0.5)/0.5 = -1.0
    expect(t[2], closeTo(-1.0, 1e-6));
    // B plane: -1.0
    expect(t[4], closeTo(-1.0, 1e-6));
  });

  test('recognitionInput resizes to the target height and reports width', () {
    final img = _solid(60, 20, 128, 128, 128); // aspect 3:1
    final out = recognitionInput(img, targetHeight: 48, maxWidth: 320);
    // width scaled by 48/20 -> 144
    expect(out.width, 144);
    expect(out.tensor.length, 3 * 48 * 320);
    // Normalized grey 128/255 ~ 0.502 -> (0.502 - 0.5)/0.5 ~ 0.004
    expect(out.tensor[0], closeTo(0.004, 0.01));
    // Padding past the filled width is zero.
    expect(out.tensor[48 * 320 - 1], 0.0);
  });
}
