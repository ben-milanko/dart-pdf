import 'rect.dart';

/// How a set of annotation rectangles should be lined up or spread out
/// relative to one another. The first six values align an edge or centre
/// line of every rect to a shared reference taken from the group's overall
/// bounding box; the last two spread the rects so the gaps between them are
/// equal.
///
/// All geometry is in PDF user space (origin bottom-left, y grows upward),
/// so [top] is the visually-highest edge and [bottom] the lowest.
enum PdfAlignment {
  /// Move every rect so its left edge sits on the group's leftmost edge.
  left,

  /// Centre every rect horizontally on the group's horizontal midpoint.
  horizontalCenter,

  /// Move every rect so its right edge sits on the group's rightmost edge.
  right,

  /// Move every rect so its top edge sits on the group's highest edge.
  top,

  /// Centre every rect vertically on the group's vertical midpoint.
  verticalCenter,

  /// Move every rect so its bottom edge sits on the group's lowest edge.
  bottom,

  /// Spread the rects horizontally so the gaps between consecutive rects
  /// are equal, holding the leftmost and rightmost edges fixed.
  distributeHorizontal,

  /// Spread the rects vertically so the gaps between consecutive rects are
  /// equal, holding the lowest and highest edges fixed.
  distributeVertical;

  /// Whether this is a distribute (spread-evenly) operation rather than an
  /// edge/centre alignment.
  bool get isDistribute =>
      this == distributeHorizontal || this == distributeVertical;

  /// The fewest rects the operation is meaningful for: two to align, three
  /// to distribute (the first and last are anchors, so distribution only
  /// moves anything with a rect in between).
  int get minimumCount => isDistribute ? 3 : 2;
}

/// Computes the translation to apply to each rect in [rects] to satisfy
/// [alignment], returned as `(dx, dy)` offsets in PDF user space, parallel
/// to (and in the same order as) [rects].
///
/// Returns all-zero offsets when there are too few rects for the operation
/// ([PdfAlignment.minimumCount]). The caller applies the offsets by
/// translating each annotation's /Rect (and its coordinate arrays) - see
/// `PdfEditor.moveAnnotation`.
List<({double dx, double dy})> alignmentOffsets(
    List<PdfRect> rects, PdfAlignment alignment) {
  final n = rects.length;
  final offsets =
      List<({double dx, double dy})>.filled(n, (dx: 0.0, dy: 0.0));
  if (n < alignment.minimumCount) return offsets;

  // The group's overall bounding box.
  var minLeft = rects.first.left;
  var minBottom = rects.first.bottom;
  var maxRight = rects.first.right;
  var maxTop = rects.first.top;
  for (final r in rects) {
    if (r.left < minLeft) minLeft = r.left;
    if (r.bottom < minBottom) minBottom = r.bottom;
    if (r.right > maxRight) maxRight = r.right;
    if (r.top > maxTop) maxTop = r.top;
  }

  switch (alignment) {
    case PdfAlignment.left:
      for (var i = 0; i < n; i++) {
        offsets[i] = (dx: minLeft - rects[i].left, dy: 0);
      }
    case PdfAlignment.right:
      for (var i = 0; i < n; i++) {
        offsets[i] = (dx: maxRight - rects[i].right, dy: 0);
      }
    case PdfAlignment.horizontalCenter:
      final cx = (minLeft + maxRight) / 2;
      for (var i = 0; i < n; i++) {
        final c = (rects[i].left + rects[i].right) / 2;
        offsets[i] = (dx: cx - c, dy: 0);
      }
    case PdfAlignment.top:
      for (var i = 0; i < n; i++) {
        offsets[i] = (dx: 0, dy: maxTop - rects[i].top);
      }
    case PdfAlignment.bottom:
      for (var i = 0; i < n; i++) {
        offsets[i] = (dx: 0, dy: minBottom - rects[i].bottom);
      }
    case PdfAlignment.verticalCenter:
      final cy = (minBottom + maxTop) / 2;
      for (var i = 0; i < n; i++) {
        final c = (rects[i].bottom + rects[i].top) / 2;
        offsets[i] = (dx: 0, dy: cy - c);
      }
    case PdfAlignment.distributeHorizontal:
      // Hold the group's left and right edges; equalise the gaps between
      // rects taken in left-to-right order. Total free space is the span
      // minus the summed widths, divided across the n-1 gaps.
      final order = [for (var i = 0; i < n; i++) i]
        ..sort((a, b) => rects[a].left.compareTo(rects[b].left));
      var summed = 0.0;
      for (final r in rects) {
        summed += r.width;
      }
      final gap = (maxRight - minLeft - summed) / (n - 1);
      var cursor = minLeft;
      for (final i in order) {
        offsets[i] = (dx: cursor - rects[i].left, dy: 0);
        cursor += rects[i].width + gap;
      }
    case PdfAlignment.distributeVertical:
      final order = [for (var i = 0; i < n; i++) i]
        ..sort((a, b) => rects[a].bottom.compareTo(rects[b].bottom));
      var summed = 0.0;
      for (final r in rects) {
        summed += r.height;
      }
      final gap = (maxTop - minBottom - summed) / (n - 1);
      var cursor = minBottom;
      for (final i in order) {
        offsets[i] = (dx: 0, dy: cursor - rects[i].bottom);
        cursor += rects[i].height + gap;
      }
  }
  return offsets;
}
