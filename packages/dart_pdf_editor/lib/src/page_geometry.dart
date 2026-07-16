import 'dart:math' as math;
import 'dart:ui';

import 'package:pdf_document/pdf_document.dart';

/// Converts between a page's PDF user space (origin bottom-left, y up,
/// points) and the view space of the widget displaying it (origin
/// top-left, y down, logical pixels), including the page's /Rotate.
///
/// Handed to [PdfViewer.pageOverlayBuilder] so apps can pin Flutter
/// widgets to positions on the page; the inverse mappings support
/// hit-testing and authoring (e.g. placing an annotation where the user
/// tapped). The transforms here mirror PdfPageRenderer's canvas setup, so
/// a mapped point always lands on the same spot in the rendered raster.
class PdfPageGeometry {
  const PdfPageGeometry({
    required this.cropBox,
    required this.rotation,
    required this.viewSize,
    this.origin = Offset.zero,
  });

  /// The page's crop box - the region the view displays.
  final PdfRect cropBox;

  /// The page's /Rotate value (0, 90, 180, or 270).
  final int rotation;

  /// The size the page occupies on screen, in logical pixels.
  final Size viewSize;

  /// Where the page's top-left corner sits within the coordinate space the
  /// view offsets are expressed in, in logical pixels. Zero (the default)
  /// means the page fills the surface from its top-left. A non-zero origin
  /// insets the page inside a larger drawing surface - the surrounding band
  /// is the off-page pasteboard, and view positions there map (unclamped)
  /// to PDF coordinates outside the crop box.
  final Offset origin;

  bool get _sideways => rotation == 90 || rotation == 270;

  /// Logical pixels per PDF point. A sideways page shows the crop box's
  /// height across the page's on-screen width ([viewSize]).
  double get scale {
    final width = _sideways ? cropBox.height : cropBox.width;
    return width <= 0 ? 1 : viewSize.width / width;
  }

  Offset toViewOffset(double x, double y) {
    // unrotated view point in points: origin top-left of the crop box
    final ux = x - cropBox.left;
    final uy = cropBox.top - y;
    final w = cropBox.width;
    final h = cropBox.height;
    final (vx, vy) = switch (rotation) {
      90 => (h - uy, ux),
      180 => (w - ux, h - uy),
      270 => (uy, w - ux),
      _ => (ux, uy),
    };
    return Offset(vx * scale + origin.dx, vy * scale + origin.dy);
  }

  Rect toViewRect(PdfRect rect) {
    final a = toViewOffset(rect.left, rect.bottom);
    final b = toViewOffset(rect.right, rect.top);
    return Rect.fromPoints(a, b);
  }

  /// View position → (x, y) in page space. Positions outside the page's
  /// on-screen rect map to PDF coordinates outside the crop box (the
  /// pasteboard) - the mapping is deliberately unclamped so off-page
  /// annotations can be authored in the margin.
  (double, double) toPagePoint(Offset offset) {
    final vx = (offset.dx - origin.dx) / scale;
    final vy = (offset.dy - origin.dy) / scale;
    final w = cropBox.width;
    final h = cropBox.height;
    final (ux, uy) = switch (rotation) {
      90 => (vy, h - vx),
      180 => (w - vx, h - vy),
      270 => (w - vy, vx),
      _ => (vx, vy),
    };
    return (cropBox.left + ux, cropBox.top - uy);
  }

  PdfRect toPageRect(Rect rect) {
    final (x1, y1) = toPagePoint(rect.topLeft);
    final (x2, y2) = toPagePoint(rect.bottomRight);
    return PdfRect(
      math.min(x1, x2),
      math.min(y1, y2),
      math.max(x1, x2),
      math.max(y1, y2),
    );
  }
}
