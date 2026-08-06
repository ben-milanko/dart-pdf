import 'package:flutter/widgets.dart';

/// Resolves the insertion index a file drop at a global position would land
/// on inside one thumbnail panel, or null when the position isn't over it.
typedef PdfThumbnailDropResolver = int? Function(Offset globalPosition);

/// Bridges the host's native file drag-and-drop (desktop_drop, the web's
/// drop events, …) to the thumbnail panels, so a PDF dragged in from the
/// desktop can be dropped *at a chosen position* in the page order instead
/// of only being appended.
///
/// The package can't see the platform's drag stream - only the host does -
/// so the host drives this controller and the panels answer with geometry:
///
/// ```dart
/// final drop = PdfThumbnailDropController();
/// ...
/// DropTarget(
///   onDragUpdated: (d) => drop.dragOver(d.globalPosition),
///   onDragExited: (_) => drop.endDrag(),
///   onDragDone: (d) {
///     final at = drop.indexAt(d.globalPosition);
///     drop.endDrag();
///     if (at != null) session.insertPagesFromBytes(bytes, at: at);
///   },
///   child: PdfEditorView(thumbnailDropController: drop, ...),
/// )
/// ```
///
/// While a drag hovers a panel the panel paints an insertion marker at the
/// index the drop would use; [endDrag] clears it. Pass the same controller
/// to [PdfThumbnailSidebar] and [PdfThumbnailView] - whichever panel is
/// under the pointer answers.
class PdfThumbnailDropController extends ChangeNotifier {
  /// The mounted panels, in attach order; the most recently attached one
  /// answers first, so a full-area page grid overlaid on a still-mounted
  /// docked strip wins the position it covers.
  final List<PdfThumbnailDropResolver> _panels = [];

  PdfThumbnailDropResolver? _target;
  int? _index;

  /// The insertion index the live drag would drop at, or null when no drag
  /// is hovering a thumbnail panel. Panels paint their marker from this.
  int? get dropIndex => _index;

  /// Whether a drag is currently over a thumbnail panel - hosts use it to
  /// step their own full-window drop hint out of the way.
  bool get isOverPanel => _index != null;

  /// Registers a panel's hit-test. Panels call this when they mount and
  /// [detachPanel] when they go away; hosts don't.
  void attachPanel(PdfThumbnailDropResolver resolver) {
    _panels.add(resolver);
  }

  /// Withdraws a panel. Clears the live indicator when it was the one
  /// showing it (a panel can be disposed mid-drag - the page grid closing,
  /// a responsive breakpoint flip).
  void detachPanel(PdfThumbnailDropResolver resolver) {
    _panels.remove(resolver);
    if (identical(_target, resolver)) {
      _target = null;
      _index = null;
      notifyListeners();
    }
  }

  /// Whether [resolver]'s panel owns the live indicator, and at which
  /// index - null when the drag is elsewhere.
  int? indicatorIndexFor(PdfThumbnailDropResolver resolver) =>
      identical(_target, resolver) ? _index : null;

  /// The insertion index a drop at [globalPosition] would use, without
  /// touching the indicator. Null when the point is over no panel.
  int? indexAt(Offset globalPosition) => _resolve(globalPosition)?.$2;

  /// Reports a live drag at [globalPosition]: moves (or clears) the
  /// insertion marker and returns the index a drop would use.
  int? dragOver(Offset globalPosition) {
    final hit = _resolve(globalPosition);
    final target = hit?.$1;
    final index = hit?.$2;
    if (identical(target, _target) && index == _index) return index;
    _target = target;
    _index = index;
    notifyListeners();
    return index;
  }

  /// Ends the drag (dropped, cancelled, or left the window), clearing the
  /// insertion marker.
  void endDrag() {
    if (_target == null && _index == null) return;
    _target = null;
    _index = null;
    notifyListeners();
  }

  (PdfThumbnailDropResolver, int)? _resolve(Offset globalPosition) {
    for (final panel in _panels.reversed) {
      final index = panel(globalPosition);
      if (index != null) return (panel, index);
    }
    return null;
  }

  @override
  void dispose() {
    _panels.clear();
    // clear the target too: a panel outliving the controller (a host that
    // disposes it first) then detaches without a notify-after-dispose
    _target = null;
    _index = null;
    super.dispose();
  }
}

/// Which edge of a page tile an insertion marker hugs. The docked strip
/// stacks tiles vertically ([top]/[bottom]); the page grid flows them
/// along the reading direction ([left]/[right]).
enum PdfThumbnailDropEdge { top, bottom, left, right }

/// The insertion index a drop at [globalPosition] lands on for a panel
/// whose tiles are laid out along [axis], or null when the point is
/// outside the panel.
///
/// [panelContext] bounds the hit to the panel's own box; [tileKeys] holds
/// the panel's per-page tile keys (only the built ones answer - a
/// scrolled-away tile has no render object, and the nearest built tile
/// then wins). The result is a *slot*: 0..pageCount, the position the
/// dropped pages would take.
int? pdfThumbnailDropIndexAt({
  required BuildContext? panelContext,
  required Map<int, GlobalKey> tileKeys,
  required int pageCount,
  required Axis axis,
  required Offset globalPosition,
  bool reversed = false,
}) {
  final panel = panelContext?.findRenderObject();
  if (panel is! RenderBox || !panel.hasSize || !panel.attached) return null;
  final local = panel.globalToLocal(globalPosition);
  if (!(Offset.zero & panel.size).contains(local)) return null;
  if (pageCount <= 0) return 0;

  int? nearest;
  Rect? nearestRect;
  var nearestDistance = double.infinity;
  for (final entry in tileKeys.entries) {
    if (entry.key >= pageCount) continue;
    final box = entry.value.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final distance = _distanceTo(rect, globalPosition);
    if (distance < nearestDistance) {
      nearest = entry.key;
      nearestRect = rect;
      nearestDistance = distance;
    }
  }
  if (nearest == null || nearestRect == null) return null;

  final centre = nearestRect.center;
  var after = axis == Axis.vertical
      ? globalPosition.dy > centre.dy
      : globalPosition.dx > centre.dx;
  if (reversed) after = !after;
  return (nearest + (after ? 1 : 0)).clamp(0, pageCount);
}

/// Squared distance from [point] to the nearest point of [rect] (zero
/// inside it) - only the ordering matters, so the square root is skipped.
double _distanceTo(Rect rect, Offset point) {
  final dx = (rect.left - point.dx).clamp(0.0, double.infinity) +
      (point.dx - rect.right).clamp(0.0, double.infinity);
  final dy = (rect.top - point.dy).clamp(0.0, double.infinity) +
      (point.dy - rect.bottom).clamp(0.0, double.infinity);
  return dx * dx + dy * dy;
}
