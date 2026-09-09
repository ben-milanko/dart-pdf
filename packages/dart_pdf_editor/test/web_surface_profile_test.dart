import 'dart:typed_data';

import 'package:dart_pdf_editor/src/font_substitution.dart';
import 'package:dart_pdf_editor/src/web_surface_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

PdfTextRun _run({
  List<PdfGlyphPlacement>? glyphs,
  bool fill = true,
  PdfColor? strokeColor,
  String text = 'DartPDF',
  double width = 3.5,
  List<double>? charOffsets,
  String fontName = 'Helvetica',
  double letterSpacing = 0,
}) =>
    PdfTextRun(
      text: text,
      transform: PdfMatrix.identity,
      color: PdfColor.black,
      width: width,
      fontName: fontName,
      glyphs: glyphs,
      fill: fill,
      strokeColor: strokeColor,
      charOffsets: charOffsets,
      letterSpacing: letterSpacing,
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

  test('Canvas2D substituted glyphs use the PDF character advances', () {
    // The Century Gothic Bold run from the reported PDF. Canvas2D substitutes
    // Helvetica here; these are representative 100px Helvetica advances.
    const natural = <String, double>{
      'B': 72.2,
      'O': 77.8,
      'K': 72.2,
      '1': 55.6,
    };
    final layout = pdfCanvas2dTextLayout(
      _run(
        text: 'BOOK 1B',
        width: 4.3002916666666655,
        charOffsets: const [
          0,
          0.5800416666666666,
          1.4200833333333331,
          2.260125,
          2.8801666666666663,
          3.160208333333333,
          3.720249999999999,
          4.3002916666666655,
        ],
      ),
      (text) => natural[text] ?? 30,
    );

    expect(layout, isNotNull);
    expect(
      layout!.parts.map((part) => part.text),
      ['B', 'O', 'O', 'K', '1', 'B'],
      reason: 'mismatched words must not keep fallback-font distribution',
    );
    final origins = layout.parts
        .map((part) => part.x / layout.unitsPerEm)
        .toList(growable: false);
    const expected = [
      0.0,
      0.5800416666666666,
      1.4200833333333331,
      2.260125,
      3.160208333333333,
      3.720249999999999,
    ];
    for (var i = 0; i < expected.length; i++) {
      expect(
        origins[i],
        closeTo(expected[i], 1e-12),
        reason: 'painted glyph $i must recover its PDF offset',
      );
    }
  });

  test('Canvas2D keeps a word whole when its interior advances agree', () {
    final layout = pdfCanvas2dTextLayout(
      _run(
        text: 'BOOK',
        width: 4,
        charOffsets: const [0, 1, 2, 3, 4],
      ),
      (_) => 100,
    );
    expect(layout, isNotNull);
    expect(layout!.parts, hasLength(1));
    expect(layout.parts.single.text, 'BOOK');
    expect(layout.parts.single.x, 0);
  });

  test('Adventor keeps Century Gothic words whole without glyph distortion',
      () {
    // TeX Gyre Adventor Bold is metric-compatible with the reported PDF's
    // Century Gothic Bold /Widths. The tiny difference is the PDF's Tc.
    const natural = <String, double>{
      'T': 42,
      'e': 64,
      'r': 32,
      'i': 24,
      't': 30,
      'o': 64,
      'y': 58,
    };
    final layout = pdfCanvas2dTextLayout(
      _run(
        text: 'Territory',
        fontName: 'CenturyGothic-Bold',
        width: 3.785327868852459,
        charOffsets: const [
          0,
          0.4205919854280502,
          1.061183970856101,
          1.381775956284151,
          1.702367941712204,
          1.942959927140254,
          2.243551912568305,
          2.884143897996356,
          3.204735883424408,
          3.785327868852459,
        ],
      ),
      (text) => natural[text]!,
    );

    expect(layout, isNotNull);
    expect(layout!.parts, hasLength(1));
    expect(layout.parts.single.text, 'Territory');
    expect(layout.parts.single.x, 0);
  });

  test('Canvas2D sizes glyphs by the PDF width, not the spaced pen step', () {
    // `( 3)Tj` under a `15.137 Tc` at 9pt - a bridging-details table reaching
    // its column. The pen steps 2.24 em across a digit the PDF gives 0.556 em,
    // and scaling the glyph to the step drew it four times too wide.
    const tc = 15.137 / 9;
    const space = 0.278 + tc;
    const digit = 0.556 + tc;
    final layout = pdfCanvas2dTextLayout(
      _run(
        text: ' 3',
        width: space + digit,
        charOffsets: const [0, space, space + digit],
        letterSpacing: tc,
      ),
      (_) => 55.6,
    );

    expect(layout, isNotNull);
    expect(layout!.unitsPerEm, closeTo(100, 1e-9),
        reason: 'the digit is drawn at its own width, spacing left as a gap');
    expect(layout.parts.single.text, '3');
    expect(layout.parts.single.x / layout.unitsPerEm, closeTo(space, 1e-12),
        reason: 'the gap the Tc opens is still in front of the digit');
  });

  test('Canvas2D cuts a spaced word where its interior would drift', () {
    // A Tc the shaped text does not carry pushes the characters apart a
    // fortieth of an em at a time; the parts must be cut before any of them
    // sits more than the 0.02 em tolerance from its own offset.
    const tc = 0.025;
    final offsets = <double>[0];
    for (var i = 0; i < 4; i++) {
      offsets.add(offsets.last + 0.5 + tc);
    }
    final layout = pdfCanvas2dTextLayout(
      _run(
        text: 'BOOK',
        width: offsets.last,
        charOffsets: offsets,
        letterSpacing: tc,
      ),
      (_) => 50,
    );

    expect(layout, isNotNull);
    expect(layout!.unitsPerEm, closeTo(100, 1e-9));
    expect(layout.parts.length, greaterThan(1),
        reason: 'shaping the word whole would leave its tail 0.075 em short');
    expect(layout.parts.map((part) => part.text).join(), 'BOOK');
    var index = 0;
    for (final part in layout.parts) {
      expect(part.x / layout.unitsPerEm, closeTo(offsets[index], 1e-12),
          reason: 'every part starts on the PDF offset of its first character');
      index += part.text.length;
    }
  });

  test('Century Gothic routes to the metric-compatible Canvas2D family', () {
    expect(pdfUsesAdventorSubstitute('ABCDEF+CenturyGothic-Bold'), isTrue);
    expect(pdfUsesAdventorSubstitute('AvantGarde-Demi'), isTrue);
    expect(pdfUsesAdventorSubstitute('MS-Gothic'), isFalse);
    expect(
      pdfCanvas2dSubstituteFamily('CenturyGothic-Bold'),
      '"TeX Gyre Adventor", "Century Gothic", "URW Gothic L", '
      '"Avenir Next", Futura, Helvetica',
    );
    expect(pdfCanvas2dSubstituteFamily('Helvetica-Bold'), 'Helvetica');
  });

  test('Canvas2D exact placement declines complex and malformed runs', () {
    expect(
      pdfCanvas2dTextLayout(
        _run(
          text: 'مرحبا',
          width: 3,
          charOffsets: const [0, 0.6, 1.2, 1.8, 2.4, 3],
        ),
        (_) => 100,
      ),
      isNull,
      reason: 'Arabic must retain whole-run joining and shaping',
    );
    expect(
      pdfCanvas2dTextLayout(
        _run(text: 'AB', width: 2, charOffsets: const [0, 2]),
        (_) => 100,
      ),
      isNull,
      reason: 'one boundary per character plus the closing edge is required',
    );
    expect(
      pdfCanvas2dTextLayout(
        _run(
          text: 'AB',
          width: double.nan,
          charOffsets: const [0, 1, 2],
        ),
        (_) => 100,
      ),
      isNull,
      reason: 'non-finite run geometry must retain the safe fallback',
    );
    expect(
      pdfCanvas2dTextLayout(
        _run(text: 'AB', width: 2, charOffsets: const [0, 1, 0.5]),
        (_) => 100,
      ),
      isNull,
      reason: 'character boundaries must remain monotonic',
    );
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
