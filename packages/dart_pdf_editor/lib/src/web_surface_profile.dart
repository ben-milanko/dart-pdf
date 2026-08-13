import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';

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
