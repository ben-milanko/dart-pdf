import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A pointer-down gate ahead of page overlays, including their raw ink input.
/// Ordinary input retains the original hit path and transforms. Mouse tracker
/// annotations remain in that path so hover, cursors and enter/exit still work.
class PdfTemporaryPanRegion extends SingleChildRenderObjectWidget {
  const PdfTemporaryPanRegion(
      {super.key,
      super.child,
      this.cursor = MouseCursor.defer,
      required this.wantsPan,
      required this.onDown,
      required this.onMove,
      required this.onEnd});
  final MouseCursor cursor;
  final bool Function(PointerDownEvent) wantsPan;
  final PointerDownEventListener onDown;
  final PointerMoveEventListener onMove;
  final void Function(PointerEvent) onEnd;
  @override
  RenderObject createRenderObject(BuildContext context) => _PanRegion(this);
  @override
  void updateRenderObject(
      BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _PanRegion).widget = this;
  }
}

class _PanRegion extends RenderMouseRegion {
  _PanRegion(this.widget) : super(opaque: false);
  @override
  MouseCursor get cursor => widget.cursor;
  PdfTemporaryPanRegion widget;
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final children = BoxHitTestResult();
    hitTestChildren(children, position: position);
    if (widget.cursor != MouseCursor.defer) {
      result.add(BoxHitTestEntry(this, position));
    }
    // Button state is not available during hit testing. Decide at dispatch,
    // before any descendant raw listener or recognizer sees pointer-down.
    // A gate belongs to this hit path (not the widget), so release/cancel
    // remains suppressed even after a rebuild or an early Space release.
    final gate = _PanGate(widget);
    result.add(HitTestEntry(gate));
    for (final entry in children.path) {
      result.addWithRawTransform(
        transform: entry.transform,
        position: position,
        hitTest: (result, _) {
          // Mouse annotations must stay visible to MouseTracker. RenderMouseRegion
          // handles no raw button events, so it is safe to leave them unwrapped.
          result.add(HitTestEntry(entry.target is RenderMouseRegion
              ? entry.target
              : _GatedTarget(gate, entry)));
          return true;
        },
      );
    }
    return true;
  }
}

class _PanGate implements HitTestTarget {
  _PanGate(this.widget);
  final PdfTemporaryPanRegion widget;
  bool panning = false;
  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is PointerDownEvent) {
      panning = widget.wantsPan(event);
      if (panning) widget.onDown(event);
    }
    if (!panning) return;
    if (event is PointerMoveEvent) widget.onMove(event);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      widget.onEnd(event);
    }
  }
}

class _GatedTarget implements HitTestTarget {
  _GatedTarget(this.gate, this.entry);
  final _PanGate gate;
  final HitTestEntry entry;
  @override
  void handleEvent(PointerEvent event, HitTestEntry ignored) {
    if (!gate.panning) entry.target.handleEvent(event, entry);
  }
}
