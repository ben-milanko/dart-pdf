import 'dart:typed_data';

import 'package:dart_pdf_editor/src/web_surface_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

PdfTextRun _run({
  List<PdfGlyphPlacement>? glyphs,
  bool fill = true,
  PdfColor? strokeColor,
}) =>
    PdfTextRun(
      text: 'DartPDF',
      transform: PdfMatrix.identity,
      color: PdfColor.black,
      width: 3.5,
      fontName: 'Helvetica',
      glyphs: glyphs,
      fill: fill,
      strokeColor: strokeColor,
    );

void main() {
  const path = PdfPath([
    PdfMoveTo(0, 0),
    PdfLineTo(10, 0),
    PdfCubicTo(12, 0, 12, 10, 10, 10),
    PdfClosePath(),
  ]);

  test('plain substituted text transcript fits the browser surface profile',
      () {
    expect(
      supportsPdfTextPageSurface([
        const PdfSaveCommand(),
        PdfDrawTextCommand(_run()),
        const PdfRestoreCommand(),
      ]),
      isTrue,
    );
    expect(supportsPdfTextPageSurface(const []), isTrue,
        reason: 'a blank page still needs its paper colour painted');
  });

  test('solid path fills and strokes fit the browser surface profile', () {
    expect(
      supportsPdfTextPageSurface(const [
        PdfFillPathCommand(path, PdfColor.black, PdfFillRule.evenOdd, 0.5),
        PdfStrokePathCommand(
          path,
          PdfColor.black,
          PdfStroke(
            width: 0,
            cap: 2,
            join: 1,
            dashArray: [2, 1],
            dashPhase: 0.5,
          ),
          0.75,
        ),
      ]),
      isTrue,
    );
  });

  test('Canvas2D strokes use the same solid device hairline floor as Skia', () {
    expect(pdfCanvas2dStrokeWidth(0, 1), 1);
    expect(pdfCanvas2dStrokeWidth(0.2, 1), 1);
    expect(pdfCanvas2dStrokeWidth(0.99, 1), 1);
    expect(pdfCanvas2dStrokeWidth(1, 1), 1);
    expect(pdfCanvas2dStrokeWidth(2, 1), 2);
    expect(pdfCanvas2dStrokeWidth(0.2, 0.1), 0.1,
        reason: 'Skia hairlines stay one device pixel at every zoom');
  });

  test('focused worker surface tracks zoom while neighbours retain', () {
    expect(pdfWebSurfaceBasePixelRatio(0.75), 0.75);
    expect(pdfWebSurfaceBasePixelRatio(2), 2);
    expect(pdfWebSurfaceBasePixelRatio(3), 2,
        reason: 'deep zoom uses a viewport-sized region surface');
    expect(
      pdfRetainedWebSurfaceDimensions(null, (1200, 800), focused: false),
      (1200, 800),
    );
    expect(
      pdfRetainedWebSurfaceDimensions(
        (2400, 1600),
        (1200, 800),
        focused: true,
      ),
      (1200, 800),
      reason: 'CSS downsampling attenuates Canvas2D hairlines',
    );
    expect(
      pdfRetainedWebSurfaceDimensions(
        (1200, 800),
        (2400, 1600),
        focused: true,
      ),
      (2400, 1600),
    );
    expect(
      pdfRetainedWebSurfaceDimensions(
        (1200, 800),
        (2400, 1600),
        focused: false,
      ),
      (1200, 800),
      reason: 'cache-window neighbours do not repaint off-screen',
    );
  });

  test('ordinary decoded images fit but raw and stencil images decline', () {
    final stream = CosStream(CosDictionary(const {}), Uint8List(0));
    PdfDrawImageCommand image({
      PdfDecodedPixels? decoded,
      bool stencil = false,
    }) =>
        PdfDrawImageCommand(PdfImageRequest(
          stream: stream,
          transform: PdfMatrix.identity,
          decoded: decoded,
          isStencil: stencil,
        ));
    final pixels =
        PdfDecodedPixels(Uint8List.fromList([10, 20, 30, 255]), 1, 1);

    expect(supportsPdfTextPageSurface([image(decoded: pixels)]), isTrue);
    expect(supportsPdfTextPageSurface([image()]), isFalse);
    expect(
      supportsPdfTextPageSurface(
        [image()],
        allowUndecodedImages: true,
      ),
      isTrue,
      reason: 'the worker preflight decodes before strict presentation',
    );
    expect(
      supportsPdfTextPageSurface([image(decoded: pixels, stencil: true)]),
      isFalse,
    );
  });

  test('premultiplied image pixels convert to Canvas2D straight alpha', () {
    final straight = pdfCanvas2dStraightRgba(PdfDecodedPixels(
      Uint8List.fromList([
        100,
        50,
        25,
        128,
        17,
        18,
        19,
        255,
        9,
        8,
        7,
        0,
      ]),
      3,
      1,
    ));
    expect(straight, [199, 100, 50, 128, 17, 18, 19, 255, 0, 0, 0, 0]);
    expect(
      pdfCanvas2dPixelsAreOpaque(
        PdfDecodedPixels(Uint8List.fromList([1, 2, 3, 255]), 1, 1),
      ),
      isTrue,
    );
    expect(
      pdfCanvas2dPixelsAreOpaque(
        PdfDecodedPixels(Uint8List.fromList([1, 2, 3, 254]), 1, 1),
      ),
      isFalse,
    );
    expect(
      () => pdfCanvas2dStraightRgba(
        PdfDecodedPixels(Uint8List(3), 1, 1),
      ),
      throwsRangeError,
    );
    expect(
      pdfCanvas2dPixelsAreOpaque(
        PdfDecodedPixels(Uint8List(3), 1, 1),
      ),
      isFalse,
    );
  });

  test('glyph placement, stroke text, and stroke-only text decline', () {
    expect(
      supportsPdfTextPageSurface([
        PdfDrawTextCommand(
          _run(glyphs: const [PdfGlyphPlacement(offset: 0)]),
        ),
      ]),
      isFalse,
    );
    expect(
      supportsPdfTextPageSurface([
        PdfDrawTextCommand(_run(strokeColor: PdfColor.black)),
      ]),
      isFalse,
    );
    expect(
      supportsPdfTextPageSurface([PdfDrawTextCommand(_run(fill: false))]),
      isFalse,
    );
  });

  test('unsupported clipping and graphics-state commands decline', () {
    expect(
      supportsPdfTextPageSurface(const [
        PdfClipPathCommand(path, PdfFillRule.nonzero),
      ]),
      isFalse,
    );
    expect(
      supportsPdfTextPageSurface([
        PdfDrawTextCommand(_run()),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
      ]),
      isFalse,
    );
  });
}
