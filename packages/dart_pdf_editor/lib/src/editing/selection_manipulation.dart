import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;
import 'package:pdf_document/pdf_document.dart';

import '../page_geometry.dart';
import 'handle_layout.dart';

// ---------------------------------------------------------------------------
// page-space rules shared by preview and commit

/// The strip of an off-page drawing that stays on the paper. A drag that
/// would carry page content (which nothing can grab past the edge) out of
/// sight stops this far in, and so does a point-less paste cascade.
const double pdfPageTether = 24.0;

/// How far to move the interval [lo, hi] so at least [pdfPageTether] of it
/// stays inside [min, max] - the whole interval when it is shorter than the
/// tether, and the whole of [min, max] when the page is shorter still.
/// Already-tethered intervals do not move, so an interval that hangs off the
/// edge keeps hanging off it.
double pdfTetherShift(double lo, double hi, double min, double max) {
  final keep = math.min(pdfPageTether, math.min(hi - lo, max - min));
  if (hi < min + keep) return min + keep - hi;
  if (lo > max - keep) return max - keep - lo;
  return 0;
}

/// [bounds] moved by ([dx], [dy]) page points, then pulled back so a strip
/// stays on [box] ([pdfTetherShift]) - the delta that keeps it.
(double, double) pdfTetheredDelta(
        PdfRect bounds, double dx, double dy, PdfRect box) =>
    (
      dx +
          pdfTetherShift(
              bounds.left + dx, bounds.right + dx, box.left, box.right),
      dy +
          pdfTetherShift(
              bounds.bottom + dy, bounds.top + dy, box.bottom, box.top),
    );

/// A view-space delta (y down, as the reader sees the page) as a page-space
/// delta (y up) through the page's /Rotate - the mapping
/// [PdfPageGeometry.toPagePoint] applies, at one point per view unit.
(double, double) pdfViewDeltaToPage(int rotation, double dx, double dy) =>
    switch (rotation % 360) {
      90 => (dy, dx),
      180 => (-dx, dy),
      270 => (-dy, -dx),
      _ => (dx, -dy),
    };

// ---------------------------------------------------------------------------
// the selection frame

/// The selection chrome's box and resting rotation (view space): the
/// axis-aligned [bounds] for an unrotated appearance, otherwise the view
/// [quad]'s own (pre-rotation) rectangle - the painter spins it back into
/// place, so the chrome hugs the rotated artwork instead of boxing its
/// axis-aligned bounds. Resize and rotate drags start from this frame, and a
/// committed edit is judged against the frame it leaves.
///
/// Only a [rotation] the *annotation* (or [group]) carries counts, measured
/// in page space. The view quad also carries the page's display /Rotate: on
/// a /Rotate 90 page every square annotation's lower edge runs down the
/// screen, so the view angle alone reads a plain text box as turned 90° -
/// which transposed its handles (the right-middle one resized vertically,
/// with an up-down cursor) and committed a transposed box. A page's rotation
/// turns the whole page, chrome included, so an annotation square to its
/// page is square to the chrome too.
(Rect, double) pdfSelectionFrame(Rect bounds,
    {List<Offset>? quad, double? rotation, bool group = false}) {
  if (rotation == 0 || quad == null) return (bounds, 0);
  final angle = group ? (quad[1] - quad[0]).direction : _quadAngle(quad);
  if (angle == 0) return (bounds, 0);
  final center =
      Offset((quad[0].dx + quad[2].dx) / 2, (quad[0].dy + quad[2].dy) / 2);
  return (
    Rect.fromCenter(
      center: center,
      width: (quad[1] - quad[0]).distance,
      height: (quad[3] - quad[0]).distance,
    ),
    angle,
  );
}

/// The view-space rotation of [quad]'s bottom edge - the angle the chrome
/// spins by (canvas.rotate convention: clockwise positive). Only floating
/// point noise reads as unrotated.
double _quadAngle(List<Offset> quad) {
  final edge = quad[1] - quad[0];
  if (edge.distance <= 0) return 0;
  final angle = edge.direction;
  return angle.abs() < 1e-7 ? 0 : angle;
}

// ---------------------------------------------------------------------------
// the handle model

/// A node handle on the selected annotation that reshapes it - what each
/// point a node drag can grab means, so a drag names its target instead of
/// encoding it in the handle's index.
@immutable
sealed class PdfReshapeHandle {
  const PdfReshapeHandle(this.point);

  /// Where the handle sits, page space.
  final (double, double) point;

  /// Which node of the annotation this is (its index, leader or vertex).
  int get _key;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is PdfReshapeHandle &&
      other._key == _key &&
      other.point == point;

  @override
  int get hashCode => Object.hash(runtimeType, _key, point);
}

/// A Line endpoint or a PolyLine/Polygon vertex.
final class PdfLineVertexHandle extends PdfReshapeHandle {
  const PdfLineVertexHandle(this.index, super.point);

  final int index;

  @override
  int get _key => index;
}

/// A callout leader's terminus (the arrow tip): dragging it re-aims that
/// leader.
final class PdfCalloutTerminusHandle extends PdfReshapeHandle {
  const PdfCalloutTerminusHandle(this.leader, super.point);

  final int leader;

  @override
  int get _key => leader;
}

/// Where a callout leader meets its box: dragging it slides the base.
final class PdfCalloutBaseHandle extends PdfReshapeHandle {
  const PdfCalloutBaseHandle(this.leader, super.point);

  final int leader;

  @override
  int get _key => leader;
}

/// A corner of a cloud callout's region: dragging it reshapes the cloud.
final class PdfCloudRegionHandle extends PdfReshapeHandle {
  const PdfCloudRegionHandle(this.vertex, super.point);

  final int vertex;

  @override
  int get _key => vertex;
}

/// The node handles [annotation] exposes, in paint order: a cloud callout's
/// region corners, a callout's terminus and base per leader, a line's
/// endpoints or a poly's vertices. Null for an annotation without nodes.
List<PdfReshapeHandle>? pdfReshapeHandlesOf(PdfAnnotation annotation) {
  if (annotation.calloutRegion case final region?) {
    return [
      for (final (i, p) in region.vertices.indexed) PdfCloudRegionHandle(i, p),
    ];
  }
  if (annotation.calloutLeaders case final leaders?) {
    return [
      for (final (i, line) in leaders.indexed) ...[
        PdfCalloutTerminusHandle(i, line.first),
        PdfCalloutBaseHandle(i, line.last),
      ],
    ];
  }
  if (annotation.line case final line?) {
    return [PdfLineVertexHandle(0, line.$1), PdfLineVertexHandle(1, line.$2)];
  }
  final vertices = annotation.vertices;
  if (vertices == null) return null;
  return [for (final (i, p) in vertices.indexed) PdfLineVertexHandle(i, p)];
}

// ---------------------------------------------------------------------------
// what a drag commits

/// The edit a selection drag commits, in page space - applied by
/// [PdfEditingController.applySelectionEdit]. The live preview is drawn from
/// the same drag, so what the user saw is what lands.
@immutable
sealed class PdfSelectionEdit {
  const PdfSelectionEdit();
}

/// Translate the selection (a cloud callout grabbed by its cloud moves
/// whole).
final class PdfMoveEdit extends PdfSelectionEdit {
  const PdfMoveEdit(this.dx, this.dy, {this.wholeCallout = false});

  final double dx;
  final double dy;
  final bool wholeCallout;

  @override
  bool operator ==(Object other) =>
      other is PdfMoveEdit &&
      other.dx == dx &&
      other.dy == dy &&
      other.wholeCallout == wholeCallout;

  @override
  int get hashCode => Object.hash(dx, dy, wholeCallout);

  @override
  String toString() => 'PdfMoveEdit($dx, $dy, wholeCallout: $wholeCallout)';
}

/// Re-home the selection onto [page], shifted by ([dx], [dy]).
final class PdfRehomeEdit extends PdfSelectionEdit {
  const PdfRehomeEdit(this.page, this.dx, this.dy);

  final int page;
  final double dx;
  final double dy;

  @override
  bool operator ==(Object other) =>
      other is PdfRehomeEdit &&
      other.page == page &&
      other.dx == dx &&
      other.dy == dy;

  @override
  int get hashCode => Object.hash(page, dx, dy);
}

/// Translate the selected page-content element (already tethered).
final class PdfElementMoveEdit extends PdfSelectionEdit {
  const PdfElementMoveEdit(this.dx, this.dy);

  final double dx;
  final double dy;
}

/// Re-home the selected element onto [page]: the drag's anchor
/// ([sourceX], [sourceY]) on its page lands on ([targetX], [targetY]).
final class PdfElementRehomeEdit extends PdfSelectionEdit {
  const PdfElementRehomeEdit(this.page,
      {required this.sourceX,
      required this.sourceY,
      required this.targetX,
      required this.targetY});

  final int page;
  final double sourceX;
  final double sourceY;
  final double targetX;
  final double targetY;
}

/// Resize to [rect]: page axes, or the selection's own (rotated) frame when
/// [local], mirrored by [flipX]/[flipY].
final class PdfResizeEdit extends PdfSelectionEdit {
  const PdfResizeEdit(this.rect,
      {this.local = false, this.flipX = false, this.flipY = false});

  final PdfRect rect;
  final bool local;
  final bool flipX;
  final bool flipY;
}

/// Rotate by [degrees], PDF convention (counterclockwise positive).
final class PdfRotateEdit extends PdfSelectionEdit {
  const PdfRotateEdit(this.degrees);

  final double degrees;
}

/// Move the [handle] the drag grabbed; [points] are every handle's position
/// afterwards (page space, one per handle, in handle order), the grabbed one
/// at [grabbed].
final class PdfReshapeEdit extends PdfSelectionEdit {
  const PdfReshapeEdit(this.handle, this.points, this.grabbed);

  final PdfReshapeHandle handle;
  final List<(double, double)> points;
  final int grabbed;

  /// Where the grabbed handle ends up.
  (double, double) get moved => points[grabbed];
}

// ---------------------------------------------------------------------------
// the drags

/// One in-flight drag on the selection. Pointer positions come in in view
/// space (the overlay's), already snapped; the preview the overlay paints and
/// the [PdfSelectionEdit] the drag commits come out of the same fields, so
/// the two cannot drift.
sealed class PdfSelectionDrag {
  PdfSelectionDrag();
}

/// A rubber band selecting what it covers.
final class PdfMarqueeDrag extends PdfSelectionDrag {
  PdfMarqueeDrag(this.start, {this.additive = false}) : current = start;

  final Offset start;
  Offset current;

  /// Whether the band adds to the selection rather than replacing it.
  final bool additive;

  Rect get rect => Rect.fromPoints(start, current);

  /// A band too small to mean anything: the press was a click.
  bool get isClick => rect.width < 4 && rect.height < 4;
}

/// Translating the selected annotations.
final class PdfMoveDrag extends PdfSelectionDrag {
  PdfMoveDrag(this.start, {this.wholeCallout = false}) : current = start;

  final Offset start;
  Offset current;

  /// The pointer's latest global position, so a drop over another page can
  /// be resolved there.
  Offset? currentGlobal;

  /// A cloud callout grabbed by its cloud: note, leader and cloud travel.
  final bool wholeCallout;

  /// The view-space displacement the preview paints.
  Offset get delta => current - start;

  bool get isClick => delta.distance < 2;

  /// The commit: a translation on this page, or a re-home when the drop
  /// resolved to another page ([drop] = page, x, y there) and the selection
  /// can travel ([canRehome]). Null for a click.
  PdfSelectionEdit? commit(PdfPageGeometry geometry,
      {required int page, (int, double, double)? drop, bool canRehome = true}) {
    if (isClick) return null;
    // mapping both endpoints keeps the delta correct on rotated pages
    final (x0, y0) = geometry.toPagePoint(start);
    if (canRehome && drop != null && drop.$1 != page) {
      return PdfRehomeEdit(drop.$1, drop.$2 - x0, drop.$3 - y0);
    }
    final (x1, y1) = geometry.toPagePoint(current);
    return PdfMoveEdit(x1 - x0, y1 - y0, wholeCallout: wholeCallout);
  }
}

/// Repositioning the selected page-content element. Unlike an annotation, an
/// element dragged off the paper cannot be picked up again, so a same-page
/// drop is tethered ([pdfTetheredDelta]) - and the preview is tethered the
/// same way, so the drawing never shows somewhere the commit won't put it.
final class PdfElementMoveDrag extends PdfSelectionDrag {
  PdfElementMoveDrag(this.start, {this.bounds, this.cropBox}) : current = start;

  final Offset start;
  Offset current;
  Offset? currentGlobal;

  /// The element's page-space bounds at rest and its page's crop box; the
  /// tether needs both.
  final PdfRect? bounds;
  final PdfRect? cropBox;

  /// The page (and point there) the pointer is over when that is another
  /// page: the drop re-homes, untethered.
  (int, double, double)? drop;

  bool get isClick => (current - start).distance < 2;

  /// The page-space translation a same-page drop commits.
  (double, double) pageDelta(PdfPageGeometry geometry) {
    final (x0, y0) = geometry.toPagePoint(start);
    final (x1, y1) = geometry.toPagePoint(current);
    final bounds = this.bounds, box = cropBox;
    if (bounds == null || box == null) return (x1 - x0, y1 - y0);
    return pdfTetheredDelta(bounds, x1 - x0, y1 - y0, box);
  }

  /// The view-space displacement the preview paints: the pointer's while a
  /// re-home is aimed at another page ([page] is this one), else the
  /// tethered one the commit lands.
  Offset previewDelta(PdfPageGeometry geometry, {required int page}) {
    if (drop case (final target, _, _) when target != page) {
      return current - start;
    }
    final (dx, dy) = pageDelta(geometry);
    final (x0, y0) = geometry.toPagePoint(start);
    return geometry.toViewOffset(x0 + dx, y0 + dy) - start;
  }

  /// The commit, or null for a click.
  PdfSelectionEdit? commit(PdfPageGeometry geometry, {required int page}) {
    if (isClick) return null;
    if (drop case (final target, final x, final y) when target != page) {
      final (x0, y0) = geometry.toPagePoint(start);
      return PdfElementRehomeEdit(target,
          sourceX: x0, sourceY: y0, targetX: x, targetY: y);
    }
    final (dx, dy) = pageDelta(geometry);
    return PdfElementMoveEdit(dx, dy);
  }
}

/// Dragging one of the box's eight resize handles. A rotated selection
/// resizes in its own frame: [from] and [rect] are then the chrome's local
/// box (the one the painter spins by [angle]), not page-axis view rects.
final class PdfResizeDrag extends PdfSelectionDrag {
  PdfResizeDrag(this.handle, this.from, this.start,
      {this.angle = 0, this.minSize = 12})
      : current = start,
        rect = from;

  final SelectionHandle handle;
  final Rect from;
  final double angle;
  final Offset start;

  /// The smallest the box may get, view pixels.
  final double minSize;

  Offset current;

  /// The resized box, normalized; a handle dragged past the opposite edge
  /// rides [flipX]/[flipY] instead.
  Rect rect;
  bool flipX = false;
  bool flipY = false;

  /// The box the pointer at [position] gives, without committing to it - what
  /// the overlay's snapping measures against.
  (Rect, bool, bool) resizedAt(Offset position, {double? aspectRatio}) {
    // a rotated selection's handles move along its own axes, so the
    // pointer delta rotates into the local frame
    final delta = position - start;
    return pdfResizedRect(
        from,
        handle,
        angle == 0
            ? delta
            : HandleLayout.rotatePoint(delta, Offset.zero, -angle),
        aspectRatio: aspectRatio,
        minSize: minSize);
  }

  /// Follows the (snapped) pointer at [position].
  void update(Offset position, {double? aspectRatio}) {
    current = position;
    final (resized, x, y) = resizedAt(position, aspectRatio: aspectRatio);
    flipX = x;
    flipY = y;
    rect = _anchored(resized);
  }

  /// The committed annotation re-rotates about the *new* local box's
  /// center, so a resize that moves the center would translate every
  /// un-dragged point by Δ − R(Δ). Shifting the local box by R(Δ) − Δ
  /// cancels that: the geometry opposite the drag stays anchored on screen
  /// and the dragged handle rides the pointer.
  Rect _anchored(Rect resized) {
    if (angle == 0) return resized;
    final delta = resized.center - from.center;
    return resized
        .shift(HandleLayout.rotatePoint(delta, Offset.zero, angle) - delta);
  }

  /// The commit. A rotated selection's local box keeps its own width and
  /// height on a sideways page - they run along the annotation's (or
  /// group's) own edges, which the frame measures in view space - while the
  /// generic rect conversion swaps the two there, so only the centre is
  /// converted.
  PdfResizeEdit commit(PdfPageGeometry geometry) {
    var to = geometry.toPageRect(rect);
    if (angle != 0 && (geometry.rotation == 90 || geometry.rotation == 270)) {
      final cx = (to.left + to.right) / 2;
      final cy = (to.bottom + to.top) / 2;
      to = PdfRect(cx - to.height / 2, cy - to.width / 2, cx + to.height / 2,
          cy + to.width / 2);
    }
    return PdfResizeEdit(to, local: angle != 0, flipX: flipX, flipY: flipY);
  }
}

/// Spinning the selection by its rotate knob.
final class PdfRotateDrag extends PdfSelectionDrag {
  PdfRotateDrag(Offset position, this.center, {this.resting = 0})
      : startAngle = (position - center).direction;

  /// The selection's center the knob turns about, view space.
  final Offset center;
  final double startAngle;

  /// The selection's resting rotation when the drag began.
  final double resting;

  /// The swept angle, view space, clockwise positive (y is down).
  double delta = 0;

  /// Rotation drags snap the total to 45° multiples within this margin.
  static const double snapRadians = 3 * math.pi / 180;

  /// Follows the pointer at [position]: the angle swept about [center],
  /// with the *total* rotation (resting + delta) snapping near 45° so a
  /// rotated annotation can snap back to square.
  void update(Offset position) {
    var swept = (position - center).direction - startAngle;
    while (swept > math.pi) {
      swept -= 2 * math.pi;
    }
    while (swept <= -math.pi) {
      swept += 2 * math.pi;
    }
    final total = resting + swept;
    final snapped = (total / (math.pi / 4)).round() * (math.pi / 4);
    delta = (total - snapped).abs() <= snapRadians ? snapped - resting : swept;
  }

  /// View-space clockwise (y down) is page-space clockwise on every /Rotate,
  /// and PDF rotation is counterclockwise-positive - hence the sign flip.
  PdfRotateEdit commit() => PdfRotateEdit(-delta * 180 / math.pi);
}

/// Dragging one node handle ([handles] by [grabbed]).
final class PdfReshapeDrag extends PdfSelectionDrag {
  PdfReshapeDrag(this.handles, this.grabbed, List<Offset> points)
      : points = List.of(points);

  final List<PdfReshapeHandle> handles;
  final int grabbed;

  /// Every handle's live position, view space.
  List<Offset> points;

  PdfReshapeHandle get handle => handles[grabbed];

  /// Moves the grabbed handle to [position].
  void update(Offset position) {
    points = List.of(points)..[grabbed] = position;
  }

  /// The callout leaders as the handles now put them: (terminus, base) per
  /// leader, view space.
  List<(Offset, Offset)> get leaders => pdfCalloutLeaderPairs(handles, points);

  PdfReshapeEdit commit(PdfPageGeometry geometry) => PdfReshapeEdit(
      handle, [for (final p in points) geometry.toPagePoint(p)], grabbed);
}

/// Pairs each callout terminus in [handles] with its leader's base, reading
/// positions from [points] (one per handle).
List<(Offset, Offset)> pdfCalloutLeaderPairs(
    List<PdfReshapeHandle> handles, List<Offset> points) {
  final termini = <int, Offset>{};
  final bases = <int, Offset>{};
  for (var i = 0; i < handles.length && i < points.length; i++) {
    switch (handles[i]) {
      case PdfCalloutTerminusHandle(:final leader):
        termini[leader] = points[i];
      case PdfCalloutBaseHandle(:final leader):
        bases[leader] = points[i];
      case PdfLineVertexHandle() || PdfCloudRegionHandle():
        break;
    }
  }
  return [
    for (final MapEntry(key: leader, value: tip) in termini.entries)
      if (bases[leader] case final base?) (tip, base),
  ];
}

/// The resized box, plus whether the drag inverted it horizontally /
/// vertically. The returned rect is always normalized (positive
/// width/height); a flip rides the booleans, so chrome and ghost layout stay
/// simple. A handle dragged past the opposite edge crosses the 0 point and
/// the box flips out the other side (with [minSize] kept on the far side);
/// aspect-locked drags (Shift) keep the old clamp-at-minimum and never flip.
(Rect, bool, bool) pdfResizedRect(
    Rect from, SelectionHandle handle, Offset delta,
    {double? aspectRatio, double minSize = 12}) {
  var left = from.left, top = from.top;
  var right = from.right, bottom = from.bottom;
  if (handle.dx < 0) left += delta.dx;
  if (handle.dx > 0) right += delta.dx;
  if (handle.dy < 0) top += delta.dy;
  if (handle.dy > 0) bottom += delta.dy;

  if (aspectRatio != null && aspectRatio > 0) {
    // aspect-locked: keep the original clamp-at-minimum, never invert
    if (right - left < minSize) {
      if (handle.dx < 0) {
        left = right - minSize;
      } else {
        right = left + minSize;
      }
    }
    if (bottom - top < minSize) {
      if (handle.dy < 0) {
        top = bottom - minSize;
      } else {
        bottom = top + minSize;
      }
    }
    var width = right - left;
    var height = bottom - top;
    if (handle.dx != 0 && handle.dy != 0) {
      // corner: lock the off-axis to whichever side the pointer pushed
      // harder (relative to the original size), then re-anchor at the
      // fixed corner so the dragged corner tracks the pointer
      if (width / from.width >= height / from.height) {
        height = width / aspectRatio;
      } else {
        width = height * aspectRatio;
      }
      if (height < minSize) {
        height = minSize;
        width = height * aspectRatio;
      }
      if (width < minSize) {
        width = minSize;
        height = width / aspectRatio;
      }
      if (handle.dx < 0) {
        left = right - width;
      } else {
        right = left + width;
      }
      if (handle.dy < 0) {
        top = bottom - height;
      } else {
        bottom = top + height;
      }
    } else if (handle.dy == 0) {
      // vertical edge: width drives, height follows about the center
      height = math.max(width / aspectRatio, minSize);
      final cy = from.center.dy;
      top = cy - height / 2;
      bottom = cy + height / 2;
    } else {
      // horizontal edge: height drives, width follows about the center
      width = math.max(height * aspectRatio, minSize);
      final cx = from.center.dx;
      left = cx - width / 2;
      right = cx + width / 2;
    }
    return (Rect.fromLTRB(left, top, right, bottom), false, false);
  }

  // free resize: let the dragged edge cross its anchor and invert the box.
  // Keep |size| ≥ minSize on whichever side of 0 it currently sits so it
  // never collapses to a line.
  var flipX = false, flipY = false;
  if (handle.dx != 0) {
    var width = right - left;
    if (width.abs() < minSize) {
      width = width < 0 ? -minSize : minSize;
      if (handle.dx < 0) {
        left = right - width;
      } else {
        right = left + width;
      }
    }
    flipX = width < 0;
  }
  if (handle.dy != 0) {
    var height = bottom - top;
    if (height.abs() < minSize) {
      height = height < 0 ? -minSize : minSize;
      if (handle.dy < 0) {
        top = bottom - height;
      } else {
        bottom = top + height;
      }
    }
    flipY = height < 0;
  }
  return (
    Rect.fromLTRB(
      math.min(left, right),
      math.min(top, bottom),
      math.max(left, right),
      math.max(top, bottom),
    ),
    flipX,
    flipY,
  );
}
