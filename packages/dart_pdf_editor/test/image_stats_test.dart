// PdfPageRenderer.decodedImageStats: the diagnostic that counts a worker
// buffer's decoded images and their total pixels (recursing soft-mask groups),
// so a slow raster page's cause - one oversized image vs. many capped tiles -
// is visible in the perf trace.
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

PdfDrawImageCommand _image(int width, int height, {bool decoded = true}) {
  final stream = CosStream(CosDictionary(const {}), Uint8List(0));
  return PdfDrawImageCommand(PdfImageRequest(
    stream: stream,
    transform: PdfMatrix.identity,
    isInline: true,
    decoded:
        decoded ? PdfDecodedPixels(Uint8List(width * height * 4), width, height) : null,
  ));
}

void main() {
  test('counts decoded images and sums their pixels', () {
    final stats = PdfPageRenderer.decodedImageStats([
      _image(2, 3),
      const PdfSaveCommand(),
      _image(4, 5),
    ]);
    expect(stats, (2, 2 * 3 + 4 * 5));
  });

  test('ignores images shipped un-decoded (platform-codec path)', () {
    final stats = PdfPageRenderer.decodedImageStats([
      _image(10, 10, decoded: false),
      _image(2, 2),
    ]);
    expect(stats, (1, 4));
  });

  test('descends into soft-mask groups', () {
    final stats = PdfPageRenderer.decodedImageStats([
      _image(3, 3),
      PdfEndSoftMaskedCommand(
        luminosity: true,
        backdrop: const PdfRect(0, 0, 1, 1),
        maskCommands: [_image(2, 2)],
        backdropLuminance: 0,
        transferScale: 1,
        transferOffset: 0,
      ),
    ]);
    expect(stats, (2, 3 * 3 + 2 * 2));
  });

  test('an image-free buffer reports zero', () {
    expect(PdfPageRenderer.decodedImageStats(const [PdfSaveCommand()]), (0, 0));
  });
}
