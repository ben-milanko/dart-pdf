// A draw whose scanlines fall inside the clip's rows but whose runs fall
// outside its columns - any slanted or off-to-the-side shape crossing a
// narrow clip. Clamping start up to the clip's left edge and end down to its
// right edge then leaves `to < from`, an inverted range. The span loops
// no-op on it, but the two `fillRange` fast paths threw a RangeError, which
// escaped `drawPage` and rendered the whole page blank.
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/src/raster/colorant_raster.dart';
import 'package:test/test.dart';

void main() {
  const width = 20, height = 10;

  PdfColorantRaster raster() => PdfColorantRaster(
        width: width,
        height: height,
        mapping: const ColorantPageMapping(PdfMatrix.identity, 1),
      );

  /// Clips to the right-hand columns over every row.
  void clipRight(PdfColorantRaster r) =>
      r.clipTo(r.boxSpans(12, 0, 20, height.toDouble()));

  test('paintFlat leaves a draw entirely left of the clip alone', () {
    final r = raster();
    clipRight(r);
    expect(() => r.paintFlat(r.boxSpans(2, 0, 6, height.toDouble()), 3),
        returnsNormally);
    expect(r.cells.every((cell) => cell == 0), isTrue);
  });

  test('paintFlat still fills the part of a draw inside the clip', () {
    final r = raster();
    clipRight(r);
    r.paintFlat(r.boxSpans(2, 0, 16, height.toDouble()), 3);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        expect(r.cells[y * width + x], x >= 12 && x < 16 ? 3 : 0,
            reason: 'cell ($x,$y)');
      }
    }
  });

  test('markCovered leaves a draw entirely left of the clip alone', () {
    final r = raster();
    clipRight(r);
    final mask = Uint8List(width * height);
    expect(() => r.markCovered(r.boxSpans(2, 0, 6, height.toDouble()), mask),
        returnsNormally);
    expect(mask.every((cell) => cell == 0), isTrue);
  });
}
