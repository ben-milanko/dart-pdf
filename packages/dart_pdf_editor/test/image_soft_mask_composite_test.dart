// Regression test for issue #675: an image /SMask kept as a companion GPU
// surface must cut the base's alpha, not paint over it.
//
// `CanvasPdfDevice.drawImage` composites a deferred grayscale /SMask with
// `BlendMode.dstIn` plus a red->alpha `ColorFilter.matrix`. Those two were on
// the mask's own draw paint, which Skia honours - and which **Impeller
// silently degrades**: it drops a draw paint's blend mode when that same paint
// carries a colour filter, so the filtered mask (opaque black wherever the
// mask is white) composited srcOver and turned every /SMask'd JPEG into a
// black rectangle. Both must live on a layer paint instead.
//
// The assertions below pass on Skia either way, so this test earns its keep
// under `flutter test --enable-impeller` (see the CI job of the same name).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/image_decoder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

const _width = 64;
const _height = 64;

/// A solid green JPEG with a gray /SMask that is transparent on the left half
/// and opaque on the right.
CosStream _maskedJpeg() {
  final rgb = img.Image(width: _width, height: _height);
  for (final p in rgb) {
    p
      ..r = 40
      ..g = 200
      ..b = 90;
  }
  final mask = Uint8List(_width * _height);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      mask[y * _width + x] = x < _width ~/ 2 ? 0 : 0xFF;
    }
  }
  final maskBytes = Uint8List.fromList(ZLibCodec(level: 6).encode(mask));
  return CosStream(
    CosDictionary({
      'Subtype': const CosName('Image'),
      'Width': const CosInteger(_width),
      'Height': const CosInteger(_height),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceRGB'),
      'Filter': const CosName('DCTDecode'),
      'SMask': CosStream(
        CosDictionary({
          'Subtype': const CosName('Image'),
          'Width': const CosInteger(_width),
          'Height': const CosInteger(_height),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceGray'),
          'Filter': const CosName('FlateDecode'),
          'Length': CosInteger(maskBytes.length),
        }),
        maskBytes,
      ),
    }),
    Uint8List.fromList(img.encodeJpg(rgb, quality: 100)),
  );
}

void main() {
  testWidgets('a deferred image /SMask cuts the base instead of painting over '
      'it', (tester) async {
    await tester.runAsync(() async {
      final cos = CosDocument.open(buildClassicPdf());
      final request = PdfImageRequest(
        stream: _maskedJpeg(),
        // Unit square -> the middle 100x100 of a 200x200 page.
        transform: PdfMatrix(100, 0, 0, 100, 50, 50),
      );
      final images = await decodeImages(cos, [request]);
      final image = images[pdfImageKey(request)];
      expect(image, isNotNull,
          reason: 'the JPEG base must decode through the platform codec');
      // The shape under test: the mask stayed a companion GPU surface rather
      // than being multiplied into the base's pixels.
      expect(pdfGpuSoftMaskOf(image!), isNotNull,
          reason: 'this test only covers the deferred (companion) mask path');

      const size = 200.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawRect(const Rect.fromLTWH(0, 0, size, size),
            Paint()..color = const Color(0xFFFFFFFF))
        // Page space is y-up, as CanvasPdfDevice expects.
        ..translate(0, size)
        ..scale(1, -1);
      CanvasPdfDevice(canvas, images: images).drawImage(request);
      final picture = recorder.endRecording();
      final raster = await picture.toImage(size.round(), size.round());
      final data = await raster.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = data!.buffer.asUint8List();
      raster.dispose();
      picture.dispose();

      List<int> at(int x, int y) {
        final i = (y * size.round() + x) * 4;
        return [pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]];
      }

      // Masked-out (left) half: the page background survives untouched. With
      // the blend mode dropped this reads as opaque black.
      expect(at(75, 100), [255, 255, 255, 255]);
      // Opaque (right) half: the base colour, give or take JPEG rounding.
      final opaque = at(125, 100);
      expect(opaque[0], closeTo(40, 6));
      expect(opaque[1], closeTo(200, 6));
      expect(opaque[2], closeTo(90, 6));
      expect(opaque[3], 255);
      // Outside the image quad nothing was painted.
      expect(at(20, 100), [255, 255, 255, 255]);

      for (final decoded in images.values) {
        disposePdfDecodedImage(decoded);
      }
    });
  });
}
