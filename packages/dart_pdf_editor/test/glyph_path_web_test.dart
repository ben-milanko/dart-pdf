// Regression for Flutter web's lazy Path.addPath implementation. The matrix
// argument is retained by reference until CanvasKit materializes the path, so
// every deferred glyph placement must own a stable value snapshot.
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main() {
  test('deferred path commands receive an immutable matrix snapshot', () {
    final matrix = Float64List(16)..[12] = 8;
    final deferred = CanvasPdfDevice.debugGlyphPathMatrixForEngine(
      matrix,
      deferred: true,
    );
    final immediate = CanvasPdfDevice.debugGlyphPathMatrixForEngine(
      matrix,
      deferred: false,
    );

    matrix[12] = 88;
    expect(deferred[12], 8,
        reason: 'CanvasKit evaluates the command after the glyph loop');
    expect(identical(deferred, matrix), isFalse);
    expect(identical(immediate, matrix), isTrue,
        reason: 'native engines consume the matrix immediately');
  });

  test('embedded glyphs retain distinct deferred path transforms', () {
    const outline = PdfPath([
      PdfMoveTo(0, 0),
      PdfLineTo(1, 0),
      PdfLineTo(1, 1),
      PdfLineTo(0, 1),
      PdfClosePath(),
    ]);
    final bounds =
        CanvasPdfDevice.debugEmbeddedGlyphPathBounds(const PdfTextRun(
      text: 'AAA',
      transform: PdfMatrix(20, 0, 0, 20, 8, 8),
      color: PdfColor.black,
      width: 5,
      glyphs: [
        PdfGlyphPlacement(offset: 0, outline: outline),
        PdfGlyphPlacement(offset: 2, outline: outline),
        PdfGlyphPlacement(offset: 4, outline: outline),
      ],
    ));

    expect(bounds.left, closeTo(8, 0.01));
    expect(bounds.right, closeTo(108, 0.01),
        reason: 'every glyph must keep its own Path.addPath transform; '
            'aliasing the matrix collapses them onto the last placement');
  });
}
