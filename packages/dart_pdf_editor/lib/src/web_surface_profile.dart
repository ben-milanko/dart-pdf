import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';

/// One substring painted by the worker-owned Canvas2D text surface.
///
/// [x] is measured in the same device-font units as
/// [PdfCanvas2dTextLayout.unitsPerEm]. Scaling both by the reciprocal places
/// the substring at its exact PDF advance in em space.
class PdfCanvas2dTextPart {
  const PdfCanvas2dTextPart(this.text, this.x);

  final String text;
  final double x;
}

/// Exact-placement plan for a substituted Canvas2D text run.
class PdfCanvas2dTextLayout {
  const PdfCanvas2dTextLayout(this.unitsPerEm, this.parts);

  final double unitsPerEm;
  final List<PdfCanvas2dTextPart> parts;
}

/// How far a substitute's natural boundary may differ from the PDF's before a
/// word is split into independently positioned glyphs.
const double _canvas2dPlacementToleranceEm = 0.02;

/// Plans substituted text at the PDF's own per-character advances.
///
/// Matching only [PdfTextRun.width] pins a run's endpoints but lets a fallback
/// font distribute every interior glyph by its own metrics. That is visibly
/// wrong when (for example) unembedded Century Gothic is painted with
/// Helvetica. [measureText] measures one character in the active Canvas2D font;
/// the returned plan applies one uniform horizontal glyph scale while placing
/// each mismatched character at its PDF offset. Words whose interior already
/// agrees within 0.02 em remain whole so their shaping and kerning are kept.
///
/// Returns null for missing/malformed offsets, all-whitespace text, or scripts
/// that need joining, reordering, combining, or multi-code-unit shaping. Those
/// keep the established whole-run Canvas2D path.
PdfCanvas2dTextLayout? pdfCanvas2dTextLayout(
  PdfTextRun run,
  double Function(String text) measureText,
) {
  final text = run.text;
  final offsets = run.charOffsets;
  if (text.isEmpty ||
      !run.width.isFinite ||
      run.width <= 0 ||
      offsets == null ||
      offsets.length != text.length + 1 ||
      !_canvas2dPlaceableRun(text)) {
    return null;
  }
  var previous = double.negativeInfinity;
  for (final offset in offsets) {
    if (!offset.isFinite || offset < previous) return null;
    previous = offset;
  }

  final widths = <int, double>{};
  double widthOf(int codeUnit) => widths.putIfAbsent(codeUnit, () {
        final width = measureText(String.fromCharCode(codeUnit));
        return width.isFinite && width >= 0 ? width : double.nan;
      });

  var natural = 0.0;
  var advance = 0.0;
  for (var i = 0; i < text.length; i++) {
    final codeUnit = text.codeUnitAt(i);
    if (_canvas2dTrimWhitespace(codeUnit)) continue;
    final width = widthOf(codeUnit);
    if (!width.isFinite) return null;
    natural += width;
    advance += offsets[i + 1] - offsets[i];
  }
  if (natural <= 0 || advance <= 0) return null;

  final unitsPerEm = natural / advance;
  if (!unitsPerEm.isFinite || unitsPerEm <= 0) return null;
  final parts = <PdfCanvas2dTextPart>[];
  var start = 0;
  while (start < text.length) {
    if (_canvas2dTrimWhitespace(text.codeUnitAt(start))) {
      start++;
      continue;
    }
    var end = start + 1;
    while (
        end < text.length && !_canvas2dTrimWhitespace(text.codeUnitAt(end))) {
      end++;
    }
    if (_canvas2dWordHolds(text, offsets, start, end, unitsPerEm, widthOf)) {
      parts.add(PdfCanvas2dTextPart(
        text.substring(start, end),
        offsets[start] * unitsPerEm,
      ));
    } else {
      for (var i = start; i < end; i++) {
        parts.add(PdfCanvas2dTextPart(
          text.substring(i, i + 1),
          offsets[i] * unitsPerEm,
        ));
      }
    }
    start = end;
  }
  return parts.isEmpty ? null : PdfCanvas2dTextLayout(unitsPerEm, parts);
}

bool _canvas2dWordHolds(
  String text,
  List<double> offsets,
  int start,
  int end,
  double unitsPerEm,
  double Function(int codeUnit) widthOf,
) {
  var natural = 0.0;
  for (var i = start; i < end; i++) {
    if ((natural / unitsPerEm - (offsets[i] - offsets[start])).abs() >
        _canvas2dPlacementToleranceEm) {
      return false;
    }
    natural += widthOf(text.codeUnitAt(i));
  }
  return (natural / unitsPerEm - (offsets[end] - offsets[start])).abs() <=
      _canvas2dPlacementToleranceEm;
}

bool _canvas2dPlaceableRun(String text) {
  for (final codeUnit in text.codeUnits) {
    if (!_canvas2dPlaceableChar(codeUnit)) return false;
  }
  return true;
}

bool _canvas2dPlaceableChar(int codeUnit) =>
    (codeUnit >= 0x20 && codeUnit <= 0x2FF && codeUnit != 0x7F) ||
    (codeUnit >= 0x370 && codeUnit <= 0x482) ||
    (codeUnit >= 0x48A && codeUnit <= 0x52F) ||
    (codeUnit >= 0x2010 && codeUnit <= 0x2027) ||
    (codeUnit >= 0x2030 && codeUnit <= 0x205E) ||
    (codeUnit >= 0x20A0 && codeUnit <= 0x20BF) ||
    (codeUnit >= 0x2100 && codeUnit <= 0x23FF) ||
    (codeUnit >= 0x2460 && codeUnit <= 0x27BF) ||
    (codeUnit >= 0x3000 && codeUnit <= 0x3098) ||
    (codeUnit >= 0x309B && codeUnit <= 0x30FF) ||
    (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) ||
    (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
    (codeUnit >= 0xAC00 && codeUnit <= 0xD7A3) ||
    (codeUnit >= 0xF900 && codeUnit <= 0xFAFF) ||
    (codeUnit >= 0xFF01 && codeUnit <= 0xFFEE);

bool _canvas2dTrimWhitespace(int codeUnit) =>
    (codeUnit >= 0x09 && codeUnit <= 0x0D) ||
    codeUnit == 0x20 ||
    codeUnit == 0x85 ||
    codeUnit == 0xA0 ||
    codeUnit == 0x1680 ||
    (codeUnit >= 0x2000 && codeUnit <= 0x200A) ||
    codeUnit == 0x2028 ||
    codeUnit == 0x2029 ||
    codeUnit == 0x202F ||
    codeUnit == 0x205F ||
    codeUnit == 0x3000 ||
    codeUnit == 0xFEFF;

/// Canvas2D equivalent of Skia's zero-width hairline policy.
///
/// [hairlineWidth] is one device pixel expressed in PDF page units. This
/// mirrors [CanvasPdfDevice]: any PDF stroke below one page unit is recorded as
/// Skia's transform-invariant zero-width hairline. Leaving those widths literal
/// makes Canvas2D attenuate them at fit scale and thicken them at deep zoom.
double pdfCanvas2dStrokeWidth(double width, double hairlineWidth) =>
    width < 1 ? hairlineWidth : width;

/// Highest full-page backing ratio used by the worker-owned DOM surface.
///
/// Past this point a visible-region overlay is cheaper than resizing and
/// committing the whole page. An A3 scan at 3x is roughly nine million canvas
/// pixels even though the viewport exposes only about one megapixel.
const double pdfWebSurfaceBaseMaxPixelRatio = 2;

/// Caps the retained full-page surface; deep zoom is supplied by a region.
double pdfWebSurfaceBasePixelRatio(double desired) =>
    desired.clamp(0.0, pdfWebSurfaceBaseMaxPixelRatio).toDouble();

/// Chooses a backing size for a live worker-owned page canvas.
///
/// A focused page tracks the requested size in both directions. CSS
/// downsampling a denser Canvas2D backing attenuates one-device-pixel PDF
/// hairlines; on real CAD pages that made a zoom-out visibly lighter than the
/// same scale rendered directly. A cache-window neighbour still keeps its
/// existing size until it becomes focused, so its off-screen update cannot
/// become the action's final visual change.
(int, int) pdfRetainedWebSurfaceDimensions(
  (int, int)? current,
  (int, int) desired, {
  required bool focused,
}) {
  if (current == null) return desired;
  return focused ? desired : current;
}

/// Converts the renderer's premultiplied image pixels to Canvas ImageData's
/// straight-alpha RGBA representation.
///
/// Opaque scans take the cheap copy-only path. Partially transparent pixels
/// are unpremultiplied with nearest-integer rounding; fully transparent RGB is
/// canonicalized to zero because its hidden colour cannot affect rendering.
Uint8ClampedList pdfCanvas2dStraightRgba(PdfDecodedPixels pixels) {
  final expected = pixels.width * pixels.height * 4;
  if (pixels.width <= 0 ||
      pixels.height <= 0 ||
      pixels.rgba.length != expected) {
    throw RangeError('decoded RGBA length does not match image dimensions');
  }
  final result = Uint8ClampedList.fromList(pixels.rgba);
  for (var offset = 0; offset < result.length; offset += 4) {
    final alpha = result[offset + 3];
    if (alpha == 255) continue;
    if (alpha == 0) {
      result[offset] = 0;
      result[offset + 1] = 0;
      result[offset + 2] = 0;
      continue;
    }
    for (var channel = 0; channel < 3; channel++) {
      final straight = (result[offset + channel] * 255 + alpha ~/ 2) ~/ alpha;
      result[offset + channel] = straight > 255 ? 255 : straight;
    }
  }
  return result;
}

/// Whether [pixels] can be handed to Canvas ImageData without
/// unpremultiplication.
bool pdfCanvas2dPixelsAreOpaque(PdfDecodedPixels pixels) {
  final expected = pixels.width * pixels.height * 4;
  if (pixels.width <= 0 ||
      pixels.height <= 0 ||
      pixels.rgba.length != expected) {
    return false;
  }
  for (var offset = 3; offset < pixels.rgba.length; offset += 4) {
    if (pixels.rgba[offset] != 255) return false;
  }
  return true;
}

/// Describes a command transcript accepted by the deliberately narrow
/// worker-owned Canvas2D renderer, or null when the established renderer must
/// stay visible.
///
/// [allowUndecodedImages] is only for the worker's preflight pass. The worker
/// then decodes every admitted image and reruns the strict check before it
/// resizes or paints the destination surface.
({bool hasImages, bool needsImageDecode})? pdfBrowserPageSurfaceProfile(
  List<PdfRenderCommand> commands, {
  bool allowUndecodedImages = false,
}) {
  var hasImages = false;
  var needsImageDecode = false;
  for (final command in commands) {
    switch (command) {
      case PdfSaveCommand() || PdfRestoreCommand():
        continue;
      case PdfFillPathCommand() || PdfStrokePathCommand():
        continue;
      case PdfDrawTextCommand(:final run):
        if (run.glyphs != null ||
            run.gradient != null ||
            run.strokeColor != null ||
            !run.fill) {
          return null;
        }
      case PdfDrawImageCommand(:final request):
        hasImages = true;
        if (request.isStencil || !request.alpha.isFinite) return null;
        final decoded = request.decoded;
        if (decoded == null) {
          if (!allowUndecodedImages) return null;
          needsImageDecode = true;
          continue;
        }
        final pixels = decoded.width * decoded.height;
        if (decoded.width <= 0 ||
            decoded.height <= 0 ||
            decoded.width > 16384 ||
            decoded.height > 16384 ||
            pixels > 64 * 1024 * 1024 ||
            decoded.rgba.length != pixels * 4) {
          return null;
        }
      default:
        return null;
    }
  }
  return (hasImages: hasImages, needsImageDecode: needsImageDecode);
}

/// Whether [commands] fit the deliberately narrow worker-owned Canvas2D
/// prototype.
///
/// Keep this check pure and run it over the complete transcript before the web
/// device resizes or paints its canvas. Returning false is the correctness
/// boundary: [PdfPageView] exposes the established Flutter renderer instead.
bool supportsPdfTextPageSurface(
  List<PdfRenderCommand> commands, {
  bool allowUndecodedImages = false,
}) =>
    pdfBrowserPageSurfaceProfile(
      commands,
      allowUndecodedImages: allowUndecodedImages,
    ) !=
    null;
