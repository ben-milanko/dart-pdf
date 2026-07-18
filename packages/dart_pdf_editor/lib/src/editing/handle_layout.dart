import 'dart:math' as math;
import 'dart:ui';

/// A resize handle identified by its unit direction from the selection
/// center: `dx`/`dy` each in `{-1, 0, 1}`. `(-1, -1)` is the top-left corner,
/// `(0, -1)` the top edge, `(1, 1)` the bottom-right corner, and so on.
typedef SelectionHandle = ({int dx, int dy});

/// The eight corner and edge resize handles, in a stable order (corners and
/// edges interleaved top-to-bottom, left-to-right).
const List<SelectionHandle> selectionHandles = [
  (dx: -1, dy: -1),
  (dx: 0, dy: -1),
  (dx: 1, dy: -1),
  (dx: -1, dy: 0),
  (dx: 1, dy: 0),
  (dx: -1, dy: 1),
  (dx: 0, dy: 1),
  (dx: 1, dy: 1),
];

/// The pure geometry of a selection's resize/rotate chrome: where each handle
/// sits around an axis-aligned view [rect], which handle a pointer hits, and
/// where the rotate knob floats. All view-space, all pure - so hit-testing is
/// a plain unit test instead of a simulated drag.
///
/// Handles are laid out in the box's own axis-aligned frame; a rotated
/// selection is hit-tested by mapping the pointer into that frame with
/// [toLocal] first (the annotation overlay pre-rotates the pointer by the
/// resting angle). The rotate knob is the one piece that carries [rotation]:
/// it spins about the box center so it always floats "above" the visual top
/// edge.
class HandleLayout {
  const HandleLayout({
    required this.rect,
    this.rotation = 0,
    this.chromeScale = 1,
    this.hitRadius = defaultHitRadius,
    this.rotateHandleDistance = defaultRotateHandleDistance,
  });

  /// Default pointer-hit radius (view pixels at 1× chrome scale).
  static const double defaultHitRadius = 12;

  /// Default distance the rotate knob floats above the selection's top edge.
  static const double defaultRotateHandleDistance = 22;

  /// The selection's axis-aligned view rectangle (before any resting spin).
  final Rect rect;

  /// The selection's resting rotation, in radians, about [rect]'s center.
  final double rotation;

  /// View-pixel-per-logical scale for the chrome (`1 / zoom`), so handles and
  /// hit targets stay a constant on-screen size as the page zooms.
  final double chromeScale;

  final double hitRadius;
  final double rotateHandleDistance;

  double get _hitDistance => hitRadius * chromeScale;

  /// The center of [handle] as an axis-aligned offset from [rect]'s center.
  Offset handleCenter(SelectionHandle handle) => Offset(
        rect.center.dx + handle.dx * rect.width / 2,
        rect.center.dy + handle.dy * rect.height / 2,
      );

  /// The resize handle a pointer at local-frame [position] hits, or null when
  /// none is within [hitRadius] (scaled by [chromeScale]). Later handles in
  /// [selectionHandles] do not shadow earlier ones - the first within range
  /// wins, matching the draw order.
  SelectionHandle? handleAt(Offset position) {
    for (final handle in selectionHandles) {
      if ((position - handleCenter(handle)).distance <= _hitDistance) {
        return handle;
      }
    }
    return null;
  }

  /// The rotate knob's view position: above [rect]'s top edge, spun by
  /// [rotation] about the box center.
  Offset get rotateHandleCenter => rotatePoint(
        Offset(rect.center.dx, rect.top - rotateHandleDistance * chromeScale),
        rect.center,
        rotation,
      );

  /// Whether a pointer at view [position] hits the rotate knob.
  bool hitsRotateHandle(Offset position) =>
      (position - rotateHandleCenter).distance <= _hitDistance;

  /// [position] mapped into the box's local (unrotated) frame, so a rotated
  /// selection can hit-test its axis-aligned handles.
  Offset toLocal(Offset position) =>
      rotatePoint(position, rect.center, -rotation);

  /// Rotates [p] about [center] by [angle] radians.
  static Offset rotatePoint(Offset p, Offset center, double angle) {
    final d = p - center;
    final c = math.cos(angle), s = math.sin(angle);
    return center + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }
}
