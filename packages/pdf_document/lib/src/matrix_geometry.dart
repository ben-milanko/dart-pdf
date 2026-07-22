import 'package:pdf_cos/pdf_cos.dart';

import 'rect.dart';

/// The axis-aligned bounds of [points], or null when the list is empty.
PdfRect? boundsOfPoints(Iterable<(double, double)> points) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  var any = false;
  for (final (x, y) in points) {
    any = true;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  return any ? PdfRect(minX, minY, maxX, maxY) : null;
}

/// The axis-aligned bounds of [box]'s four corners after mapping them
/// through [matrix]. Used for form /BBox → page-space extents and image
/// unit-square footprints.
PdfRect boundsUnderMatrix(PdfMatrix matrix, PdfRect box) => boundsOfPoints([
      matrix.apply(box.left, box.bottom),
      matrix.apply(box.right, box.bottom),
      matrix.apply(box.right, box.top),
      matrix.apply(box.left, box.top),
    ])!;

/// The §12.5.5 form-appearance fit: the scale-and-translate affine that maps
/// the bounding box of [bbox]'s corners under the form's [matrix] onto
/// [rect]. This is the transform a conforming viewer concatenates *before*
/// the form's own /Matrix (which the `Do` operator applies), so extraction,
/// flatten, and resize all land the appearance identically.
///
/// A degenerate transformed dimension (width or height below 1e-9) falls back
/// to unit scale on that axis; callers that must reject the degenerate case
/// should test [boundsUnderMatrix] first.
PdfMatrix fitFormToRect(PdfRect bbox, PdfMatrix matrix, PdfRect rect) {
  final bounds = boundsUnderMatrix(matrix, bbox);
  final sx = bounds.width > 1e-9 ? rect.width / bounds.width : 1.0;
  final sy = bounds.height > 1e-9 ? rect.height / bounds.height : 1.0;
  return PdfMatrix(
    sx,
    0,
    0,
    sy,
    rect.left - bounds.left * sx,
    rect.bottom - bounds.bottom * sy,
  );
}
