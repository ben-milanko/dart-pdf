import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A viewport-level hit-test bridge to visible off-page editing chrome.
///
/// List item bounds cannot route a handle in the preceding/following gutter.
/// This bridge visits registered editing targets only for points outside every
/// page. It does not clamp the pointer or send it through unrelated page widgets.
class PdfEditingCanvasReach extends SingleChildRenderObjectWidget {
  const PdfEditingCanvasReach(
      {super.key, required this.targets, required this.overPage, super.child});
  final Iterable<GlobalKey> Function() targets;
  final bool Function(Offset) overPage;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      PdfRenderEditingCanvasReach(targets, overPage);
  @override
  void updateRenderObject(BuildContext context,
      covariant PdfRenderEditingCanvasReach renderObject) {
    renderObject
      ..targets = targets
      ..overPage = overPage;
  }
}

class PdfRenderEditingCanvasReach extends RenderProxyBox {
  PdfRenderEditingCanvasReach(this.targets, this.overPage);
  Iterable<GlobalKey> Function() targets;
  bool Function(Offset) overPage;
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!overPage(position)) {
      for (final key in targets()) {
        final target = key.currentContext?.findRenderObject();
        if (target is! PdfRenderEditingReach ||
            !target.attached ||
            !target.hasSize) {
          continue;
        }
        final transform = target.getTransformTo(this);
        if (result.addWithPaintTransform(
            transform: transform,
            position: position,
            hitTest: (result, local) =>
                target.grabs(local) &&
                target.hitTest(result, position: local))) {
          return true;
        }
      }
    }
    return super.hitTestChildren(result, position: position);
  }
}

/// Lets a page's editing layer be grabbed from *outside* the page.
///
/// An annotation's geometry is not confined to the crop box - a markup can
/// hang off the paper, and the editor paints the part that does. Pointer
/// routing did not follow: a page's render box stops at the page edge and
/// [RenderBox.hitTest] refuses any position outside `size`, so a press on
/// the off-page half of a selected annotation reached nothing at all. The
/// annotation could only be moved, resized, or drawn by its on-page half.
///
/// This proxy accepts those positions and forwards them into the page
/// subtree at the nearest point *inside* it.
///
/// Clamping is sound because **hit testing only decides routing**. Every
/// pointer event still carries its true global position, and
/// `PointerEvent.localPosition` is derived from that through the target's
/// own transform - never from the position the hit test was performed at.
/// So the editing overlay reads the real off-page point (negative, or past
/// the page's width) and every bit of its drag math works unchanged.
///
/// The viewport bridge also routes gutter hits across list-item boundaries.
/// It excludes points over any page, preserving adjacent-page interaction.
///
/// [grabs] decides which outside positions come in, and it must stay narrow:
/// the canvas beside a page belongs to scrolling. A phone at
/// `PdfViewerFit.page` leaves margin down both sides of a portrait page for
/// a thumb to land on, and taking that away to hand every margin press to
/// the page would cost scrolling far more than it buys editing. So the
/// viewer only accepts positions that land on the selection hanging off the
/// page - the one thing out there worth grabbing. Everything else falls
/// through untouched.
class PdfEditingReach extends SingleChildRenderObjectWidget {
  const PdfEditingReach({super.key, required this.grabs, super.child});

  /// Whether a press at this position - in the page's own view space, and
  /// always outside it - should reach the page. See the class docs for why
  /// this has to be selective rather than "anything in the margin".
  final bool Function(Offset position) grabs;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      PdfRenderEditingReach(grabs: grabs);

  @override
  void updateRenderObject(
          BuildContext context, PdfRenderEditingReach renderObject) =>
      renderObject.grabs = grabs;
}

/// The render object behind [PdfEditingReach]. Public so tests can reach it.
class PdfRenderEditingReach extends RenderProxyBox {
  PdfRenderEditingReach({required this.grabs});

  /// Routing only - nothing about layout or paint depends on this, so
  /// changing it never needs to mark anything dirty.
  bool Function(Offset position) grabs;

  /// `Rect.contains` is half-open on the right and bottom edges, so a
  /// position clamped exactly to `size` would be rejected by the very child
  /// it is being routed to. Land a hair inside instead.
  static const double _insetFromEdge = 0.01;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.isEmpty || size.contains(position) || !grabs(position)) {
      return super.hitTest(result, position: position);
    }
    return super.hitTest(result, position: _nearestInside(position));
  }

  Offset _nearestInside(Offset position) => Offset(
        position.dx
            .clamp(0.0, math.max(0.0, size.width - _insetFromEdge))
            .toDouble(),
        position.dy
            .clamp(0.0, math.max(0.0, size.height - _insetFromEdge))
            .toDouble(),
      );
}
