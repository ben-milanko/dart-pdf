// Unit tests for the premultiplied-RGBA box-filter downsampler that caps a
// CAD sheet's raster underlay to display resolution before it crosses the
// render-worker boundary (see render_command_codec's maxImagePixelRatio).
import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

PdfDecodedPixels _solid(int w, int h, int r, int g, int b, int a) {
  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    rgba[i * 4] = r;
    rgba[i * 4 + 1] = g;
    rgba[i * 4 + 2] = b;
    rgba[i * 4 + 3] = a;
  }
  return PdfDecodedPixels(rgba, w, h);
}

void main() {
  group('downsamplePdfDecodedPixels', () {
    test('returns the same instance when no downscale is needed', () {
      final src = _solid(4, 4, 10, 20, 30, 255);
      expect(identical(downsamplePdfDecodedPixels(src, 4, 4), src), isTrue);
      expect(identical(downsamplePdfDecodedPixels(src, 8, 8), src), isTrue,
          reason: 'must never upscale');
      // One axis already small enough but the other larger still resamples.
      expect(identical(downsamplePdfDecodedPixels(src, 4, 2), src), isFalse);
    });

    test('averages a 2x2 block into one pixel', () {
      // Four distinct pixels; the 1x1 result is their per-channel mean.
      final rgba = Uint8List.fromList(<int>[
        40, 80, 120, 160, //
        0, 0, 0, 0, //
        200, 200, 200, 200, //
        100, 100, 100, 100, //
      ]);
      final out = downsamplePdfDecodedPixels(PdfDecodedPixels(rgba, 2, 2), 1, 1);
      expect(out.width, 1);
      expect(out.height, 1);
      expect(out.rgba, equals(<int>[85, 95, 105, 115]));
    });

    test('halving a solid image preserves its colour and dimensions', () {
      final out = downsamplePdfDecodedPixels(_solid(8, 6, 33, 66, 99, 200), 4, 3);
      expect(out.width, 4);
      expect(out.height, 3);
      for (var i = 0; i < out.width * out.height; i++) {
        expect(out.rgba.sublist(i * 4, i * 4 + 4), equals(<int>[33, 66, 99, 200]));
      }
    });

    test('clamps a target larger than the source per axis', () {
      final out = downsamplePdfDecodedPixels(_solid(6, 6, 1, 2, 3, 4), 10, 3);
      expect(out.width, 6, reason: 'width target above source is clamped down');
      expect(out.height, 3);
    });

    test('a degenerate target falls back to at least 1px', () {
      final out = downsamplePdfDecodedPixels(_solid(6, 6, 9, 9, 9, 9), 0, 0);
      expect(out.width, 1);
      expect(out.height, 1);
      expect(out.rgba, equals(<int>[9, 9, 9, 9]));
    });
  });
}
