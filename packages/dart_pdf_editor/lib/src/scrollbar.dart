import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// The viewer-style scrollbar: a light thumb with a dark outline over a
/// faint track scrim - always visible while the content overflows,
/// widening on hover, draggable from the first pixel, and jumping (then
/// dragging) on a track grab. [PdfViewer] paints it outside the zoom
/// transform so it keeps its place and size at any zoom, and the
/// sidebars mount the same bar over their lists so every scrollbar in
/// the chrome looks and behaves alike. Colors follow
/// [PdfViewerThemeData.scrollbar].
///
/// Two modes:
///
/// - Plain (the sidebars): pass [scroll] alone - the bar mirrors and
///   drives the controller directly.
/// - Transformed (the viewer): pass [transform] and [onScrollBy]; the
///   thumb tracks the combined scroll-plus-pan position and motion is
///   delegated so the host can spill it into the zoom window at the
///   scroll extents.
class PdfScrollbar extends StatefulWidget {
  const PdfScrollbar({
    super.key,
    this.axis = Axis.vertical,
    this.scroll,
    this.transform,
    this.minOverflow = 0,
    this.viewExtent,
    this.onScrollBy,
    this.thumbKey,
  })  : assert(axis == Axis.vertical ? scroll != null : viewExtent != null),
        assert(axis == Axis.vertical || transform != null,
            'a horizontal bar measures overflow from the transform'),
        assert(onScrollBy != null || scroll != null);

  /// How much room bars reserve: the viewer's horizontal bar is inset
  /// by this on the right so the two never overlap in the corner.
  static const hitExtent = 14.0;

  final Axis axis;

  /// Vertical only: the list's controller (vertical position is scroll
  /// plus zoom-window pan).
  final ScrollController? scroll;

  /// The viewer's zoom transform, or null for a plain scrollable.
  final TransformationController? transform;

  /// Hide while the scrollable range is at most this (the viewer's list
  /// pads its bottom by the page spacing, so a fully visible document
  /// still has that much nominal slack - no bar for just a margin).
  final double minOverflow;

  /// Horizontal only: the viewer's full width - the laid-out content
  /// width in list space (the bar's own track is inset for the corner,
  /// so it can't measure this itself).
  final double? viewExtent;

  /// Moves the view by a delta in list-space pixels; null drives
  /// [scroll] directly, clamped to its extents.
  final void Function(double delta)? onScrollBy;

  /// A key for the thumb itself, for tests.
  final Key? thumbKey;

  @override
  State<PdfScrollbar> createState() => _PdfScrollbarState();
}

class _PdfScrollbarState extends State<PdfScrollbar> {
  static const _minThumb = 36.0;

  static const _defaultThumb = Color(0xD9E8EAED);
  static const _defaultThumbActive = Color(0xFFF5F6F8);
  static const _defaultOutline = Color(0x59000000);
  static const _defaultTrack = Color(0x14000000);
  static const _defaultTrackActive = Color(0x2E000000);

  bool _hovered = false;
  bool _dragging = false;

  bool get _vertical => widget.axis == Axis.vertical;

  double get _scale => widget.transform?.value.getMaxScaleOnAxis() ?? 1;

  /// (laid-out extent, visible extent) along the axis, in list-space
  /// pixels, or null while there are no metrics yet.
  (double, double)? _extents() {
    if (_vertical) {
      final scroll = widget.scroll!;
      // exactly one: a host swapping its list's slot in the tree leaves
      // both the old and new positions attached for one frame
      if (scroll.positions.length != 1) return null;
      final position = scroll.position;
      if (!position.hasContentDimensions) return null;
      final total = position.maxScrollExtent + position.viewportDimension;
      return (total, position.viewportDimension / _scale);
    }
    // horizontally the pages always lay out at the viewer width;
    // overflow exists only inside the zoom window
    final total = widget.viewExtent!;
    return (total, total / _scale);
  }

  /// The visible window's leading edge in list space: the viewport
  /// unprojects through the transform as (p - t) / s, riding on the
  /// scroll offset vertically (see _visibleFractionOf).
  double _offset() {
    final m = widget.transform?.value;
    if (m == null) return widget.scroll!.position.pixels;
    return _vertical
        ? -m.storage[13] / _scale + widget.scroll!.position.pixels
        : -m.storage[12] / _scale;
  }

  void _scrollBy(double delta) {
    final onScrollBy = widget.onScrollBy;
    if (onScrollBy != null) return onScrollBy(delta);
    final position = widget.scroll!.position;
    position.jumpTo((position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  /// (thumb position, thumb extent) in track pixels, or null when the
  /// whole document is visible along this axis and the bar should hide.
  (double, double)? _thumb(double trackExtent) {
    if (trackExtent <= 0) return null;
    final extents = _extents();
    if (extents == null) return null;
    final (total, visible) = extents;
    if (total <= visible + widget.minOverflow + 0.5) return null;
    final thumbExtent = (trackExtent * visible / total)
        .clamp(math.min(_minThumb, trackExtent), trackExtent)
        .toDouble();
    final fraction = (_offset() / (total - visible)).clamp(0.0, 1.0);
    return (fraction * (trackExtent - thumbExtent), thumbExtent);
  }

  /// One thumb-track pixel in list-space pixels.
  double _listPixelsPerTrackPixel(double trackExtent, double thumbExtent) {
    final extents = _extents();
    if (extents == null) return 0;
    final (total, visible) = extents;
    final track = trackExtent - thumbExtent;
    return track <= 0 ? 0 : (total - visible) / track;
  }

  /// Centers the visible window on track position [tapAt].
  void _jumpTo(double tapAt, double trackExtent) {
    final thumb = _thumb(trackExtent);
    if (thumb == null) return;
    final (thumbPos, thumbExtent) = thumb;
    final perPixel = _listPixelsPerTrackPixel(trackExtent, thumbExtent);
    _scrollBy((tapAt - thumbExtent / 2 - thumbPos) * perPixel);
  }

  @override
  Widget build(BuildContext context) {
    final theme = PdfViewerTheme.of(context).scrollbar;
    return AnimatedBuilder(
      animation: Listenable.merge([
        if (widget.scroll != null) widget.scroll!,
        if (widget.transform != null) widget.transform!,
      ]),
      builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
        final trackExtent =
            _vertical ? constraints.maxHeight : constraints.maxWidth;
        final thumb = _thumb(trackExtent);
        if (thumb == null) return const SizedBox.shrink();
        final (thumbPos, thumbExtent) = thumb;
        final active = _hovered || _dragging;
        void dragStart(DragStartDetails details) {
          final at =
              _vertical ? details.localPosition.dy : details.localPosition.dx;
          // grabbing the track brings the thumb under the pointer first;
          // then the drag is relative, like grabbing the thumb
          if (at < thumbPos || at > thumbPos + thumbExtent) {
            _jumpTo(at, trackExtent);
          }
          setState(() => _dragging = true);
        }

        void dragUpdate(DragUpdateDetails details) {
          final thumb = _thumb(trackExtent);
          if (thumb == null) return;
          final perPixel = _listPixelsPerTrackPixel(trackExtent, thumb.$2);
          _scrollBy(
              (_vertical ? details.delta.dy : details.delta.dx) * perPixel);
        }

        void dragStop() => setState(() => _dragging = false);

        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // deltas from the press point: the thumb tracks the pointer
            // from the very first pixel
            dragStartBehavior: DragStartBehavior.down,
            onTapUp: (details) {
              final at = _vertical
                  ? details.localPosition.dy
                  : details.localPosition.dx;
              // a tap on the thumb itself is not a jump
              if (at < thumbPos || at > thumbPos + thumbExtent) {
                _jumpTo(at, trackExtent);
              }
            },
            onVerticalDragStart: _vertical ? dragStart : null,
            onVerticalDragUpdate: _vertical ? dragUpdate : null,
            onVerticalDragEnd: _vertical ? (_) => dragStop() : null,
            onVerticalDragCancel: _vertical ? dragStop : null,
            onHorizontalDragStart: _vertical ? null : dragStart,
            onHorizontalDragUpdate: _vertical ? null : dragUpdate,
            onHorizontalDragEnd: _vertical ? null : (_) => dragStop(),
            onHorizontalDragCancel: _vertical ? null : dragStop,
            child: SizedBox(
              width: _vertical ? PdfScrollbar.hitExtent : trackExtent,
              height: _vertical ? trackExtent : PdfScrollbar.hitExtent,
              child: Stack(children: [
                // a faint track scrim so the bar reads as a control over
                // white pages too
                Positioned.fill(
                  child: ColoredBox(
                      color: active
                          ? theme?.trackActiveColor ?? _defaultTrackActive
                          : theme?.trackColor ?? _defaultTrack),
                ),
                Positioned(
                  top: _vertical ? thumbPos : null,
                  left: _vertical ? null : thumbPos,
                  right: _vertical ? 2 : null,
                  bottom: _vertical ? null : 2,
                  width: _vertical ? (active ? 10 : 8) : thumbExtent,
                  height: _vertical ? thumbExtent : (active ? 10 : 8),
                  child: Container(
                    key: widget.thumbKey,
                    decoration: BoxDecoration(
                      // light fill + dark outline: visible on the dark
                      // canvas and on white pages alike
                      color: active
                          ? theme?.thumbActiveColor ?? _defaultThumbActive
                          : theme?.thumbColor ?? _defaultThumb,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                          color: theme?.outlineColor ?? _defaultOutline),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}
