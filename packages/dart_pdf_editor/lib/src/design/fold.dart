import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A fold or hinge that splits the window into two panes: a foldable held
/// half open (book or tabletop posture), or a hinge with a physical gap.
///
/// A flat fold with no gap - an unfolded phone lying open - is not one: the
/// inner display is then a single surface and content may cross it.
@immutable
class PdfDisplayFold {
  const PdfDisplayFold({required this.bounds, required this.direction});

  /// The fold's rectangle in window (MediaQuery) coordinates. Zero width or
  /// height for a fold that occludes nothing.
  final Rect bounds;

  /// [Axis.horizontal] when the panes sit side by side (a vertical crease,
  /// book posture), [Axis.vertical] when they stack (tabletop posture).
  final Axis direction;
}

/// The fold or hinge splitting a window of [size] into two panes, if any of
/// [features] is one. Mirrors material's `DisplayFeatureSubScreen`: a feature
/// separates when it is half open or physically occludes the screen, and only
/// one that runs edge to edge splits the window into panes.
PdfDisplayFold? pdfSeparatingFold(List<DisplayFeature> features, Size size) {
  for (final feature in features) {
    if (feature.type != DisplayFeatureType.fold &&
        feature.type != DisplayFeatureType.hinge) {
      continue;
    }
    final b = feature.bounds;
    if (b.shortestSide <= 0 &&
        feature.state != DisplayFeatureState.postureHalfOpened) {
      continue;
    }
    if (b.top <= 0 &&
        b.bottom >= size.height &&
        b.left > 0 &&
        b.right < size.width) {
      return PdfDisplayFold(bounds: b, direction: Axis.horizontal);
    }
    if (b.left <= 0 &&
        b.right >= size.width &&
        b.top > 0 &&
        b.bottom < size.height) {
      return PdfDisplayFold(bounds: b, direction: Axis.vertical);
    }
  }
  return null;
}

/// The fold splitting the window at [context], if any (see
/// [pdfSeparatingFold]).
PdfDisplayFold? pdfSeparatingFoldOf(BuildContext context) => pdfSeparatingFold(
    MediaQuery.displayFeaturesOf(context), MediaQuery.sizeOf(context));

/// Keeps [child] out of the crease: when a separating fold
/// ([pdfSeparatingFoldOf]) crosses this widget, [child] is inset into one pane
/// instead of straddling the hinge - the wider side of a vertical crease, the
/// upper side of a tabletop fold (content up, controls on the lower half).
///
/// The inset is a [Padding] that is always present, zero when there is no
/// fold, so a posture change never reparents [child] and its state (a
/// viewer's scroll position) survives folding and unfolding.
class PdfFoldAvoid extends StatefulWidget {
  const PdfFoldAvoid({super.key, required this.child});

  final Widget child;

  @override
  State<PdfFoldAvoid> createState() => _PdfFoldAvoidState();
}

class _PdfFoldAvoidState extends State<PdfFoldAvoid> {
  /// This widget's window-space origin as of the last frame. The fold is in
  /// window coordinates; the inset needs it in ours.
  Offset? _origin;
  bool _measureScheduled = false;

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) return;
      final origin = box.localToGlobal(Offset.zero);
      if (origin != _origin) setState(() => _origin = origin);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fold = pdfSeparatingFoldOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      var padding = EdgeInsets.zero;
      if (fold != null) {
        // Re-check the origin every frame a fold is present: a panel opening
        // beside this widget moves it without rebuilding it.
        _scheduleMeasure();
        final origin = _origin;
        if (origin != null &&
            constraints.hasBoundedWidth &&
            constraints.hasBoundedHeight) {
          padding = pdfFoldInsets(
            fold,
            origin & constraints.biggest,
            textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
          );
        }
      }
      return Padding(padding: padding, child: widget.child);
    });
  }
}

/// The insets that move content laid out in [rect] (window coordinates) off
/// [fold] into a single pane: the wider side of a vertical crease (ties go to
/// the leading side for [textDirection]), the upper side of a tabletop fold
/// unless nothing of [rect] is above it. Zero when the fold misses [rect].
EdgeInsets pdfFoldInsets(PdfDisplayFold fold, Rect rect,
    {TextDirection textDirection = TextDirection.ltr}) {
  final b = fold.bounds;
  if (fold.direction == Axis.horizontal) {
    if (b.right <= rect.left || b.left >= rect.right) return EdgeInsets.zero;
    final before = (b.left - rect.left).clamp(0.0, rect.width);
    final after = (rect.right - b.right).clamp(0.0, rect.width);
    final keepLeft = before > after ||
        (before == after && textDirection == TextDirection.ltr);
    return keepLeft
        ? EdgeInsets.only(right: rect.width - before)
        : EdgeInsets.only(left: rect.width - after);
  }
  if (b.bottom <= rect.top || b.top >= rect.bottom) return EdgeInsets.zero;
  final above = (b.top - rect.top).clamp(0.0, rect.height);
  final below = (rect.bottom - b.bottom).clamp(0.0, rect.height);
  return above > 0
      ? EdgeInsets.only(bottom: rect.height - above)
      : EdgeInsets.only(top: rect.height - below);
}
