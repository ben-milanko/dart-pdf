import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'viewport.dart';

/// Where a [PdfViewer] is looking, as one value: the layout zoom the list is
/// laid out at, the scroll offset along the main (scroll) axis, and the zoom
/// transform's scale and translation, in axis terms rather than x/y.
///
/// Zoom has two regimes. At or below fit the list itself lays out smaller
/// ([layoutZoom] <= 1) and the transform is the identity ([scale] 1). Above
/// fit the list lays out at fit and zoom rides a scale + translation
/// transform over it, so a view-space point unprojects to list space as
/// `(p - t) / s`, plus the scroll offset along the main axis. Every capture,
/// placement, framing, zoom about a focal point and fold between the two
/// regimes is a function from one frame to another; this is the one place
/// they are written. The viewer only applies the result (lays out at
/// [layoutZoom], jumps to [scroll], writes the transform) and picks the frame
/// timing.
@immutable
class PdfViewportFrame {
  const PdfViewportFrame({
    required this.scroll,
    this.scale = 1,
    this.mainTranslate = 0,
    this.crossTranslate = 0,
    this.layoutZoom = 1,
  });

  /// The list's scroll offset, in list space at [layoutZoom].
  final double scroll;

  /// The transform's scale (1 at or below fit; briefly below 1 while a
  /// gesture the transform owns is still in flight).
  final double scale;

  /// The transform's translation along the main and cross axes (view
  /// pixels, at most 0).
  final double mainTranslate;
  final double crossTranslate;

  /// The zoom the pages are laid out at: fit is 1, below fit the pages lay
  /// out smaller so more of the document is on screen. Never above 1.
  final double layoutZoom;

  /// The effective zoom the user sees (1 = fit). A transform within 1% of
  /// the identity defers to the layout zoom; anything else - including a
  /// sub-1 transform mid-gesture - combines with it.
  double get zoom =>
      scale > 1.01 || scale < 0.99 ? scale * layoutZoom : layoutZoom;

  /// Whether the transform is zoomed in past fit.
  bool get zoomed => scale > 1.01;

  /// Whether [other] has the same transform (scale and translation).
  bool sameTransformAs(PdfViewportFrame other) =>
      other.scale == scale &&
      other.mainTranslate == mainTranslate &&
      other.crossTranslate == crossTranslate;

  /// An effective [zoom] split into its two regimes: the layout zoom (at or
  /// below fit, at least [minZoom]) and the transform scale (above fit, at
  /// most [maxZoom]). One of the two is always 1.
  static (double layoutZoom, double scale) zoomParts(double zoom,
          {required double minZoom, required double maxZoom}) =>
      zoom <= 1
          ? (zoom.clamp(minZoom, 1.0).toDouble(), 1.0)
          : (1.0, zoom.clamp(1.0, maxZoom).toDouble());

  /// The list-space main coordinate under view-space [viewMain].
  double listMainAt(double viewMain) =>
      (viewMain - mainTranslate) / scale + scroll;

  /// The list-space cross coordinate under view-space [viewCross].
  double listCrossAt(double viewCross) => (viewCross - crossTranslate) / scale;

  /// The view-space main coordinate of list-space [listMain].
  double viewMainOf(double listMain) =>
      (listMain - scroll) * scale + mainTranslate;

  /// The view-space cross coordinate of list-space [listCross].
  double viewCrossOf(double listCross) => listCross * scale + crossTranslate;

  /// The frame at [scale] that shows list point ([listMain], [listCross]) at
  /// view point ([atMain], [atCross]) - the viewport's leading corner by
  /// default - as closely as the content allows: the scroll stays within
  /// `[0, maxScroll]` and the transform never pulls the content's edge
  /// inside a [mainView] x [crossView] viewport. The list is laid out at
  /// [layoutZoom] already; framing does not relayout.
  factory PdfViewportFrame.showing({
    required double listMain,
    required double listCross,
    required double scale,
    required double mainView,
    required double crossView,
    required double maxScroll,
    double atMain = 0,
    double atCross = 0,
    double layoutZoom = 1,
  }) {
    final s = scale < 1 ? 1.0 : scale;
    final scroll = (listMain - atMain).clamp(0.0, maxScroll).toDouble();
    if (s == 1) return PdfViewportFrame(scroll: scroll, layoutZoom: layoutZoom);
    return PdfViewportFrame(
      scroll: scroll,
      scale: s,
      layoutZoom: layoutZoom,
      mainTranslate:
          (s * (scroll - listMain) + atMain).clamp(mainView * (1 - s), 0.0),
      crossTranslate: (atCross - s * listCross).clamp(crossView * (1 - s), 0.0),
    );
  }

  /// Zoom about a focal point: the frame at [scale] that keeps list point
  /// ([listMain], [listCross]) under view point ([atMain], [atCross]) while
  /// the scroll stays at [scroll] - wheel, pinch and trackpad zoom hold the
  /// content under the pointer. The translation is clamped so the content's
  /// edge never comes inside a [mainView] x [crossView] viewport; with
  /// [clampCross] false the cross axis is left free for a touch pan's
  /// rubber band. Within 1% of fit the transform snaps to the identity.
  factory PdfViewportFrame.zoomedAbout({
    required double scroll,
    required double listMain,
    required double listCross,
    required double scale,
    required double atMain,
    required double atCross,
    required double mainView,
    required double crossView,
    bool clampCross = true,
    double layoutZoom = 1,
  }) {
    if (scale <= 1.01) {
      return PdfViewportFrame(scroll: scroll, layoutZoom: layoutZoom);
    }
    final mainTranslate = atMain - scale * (listMain - scroll);
    final crossTranslate = atCross - scale * listCross;
    return PdfViewportFrame(
      scroll: scroll,
      scale: scale,
      layoutZoom: layoutZoom,
      mainTranslate: mainTranslate.clamp(mainView * (1 - scale), 0.0),
      crossTranslate: clampCross
          ? crossTranslate.clamp(crossView * (1 - scale), 0.0)
          : crossTranslate,
    );
  }

  /// This frame relaid out at layout zoom [to]: the transform is kept, and
  /// the scroll moves so [content] (a main-axis list coordinate at the
  /// current layout zoom; whatever sits at [anchor] now by default) lands at
  /// view main [anchor]. The scroll is never negative; its far end is the
  /// applier's to clamp once the new extents exist.
  PdfViewportFrame withLayoutZoom(
    double to, {
    required PdfLayoutZoomAxis axis,
    required double anchor,
    double? content,
  }) {
    if (to == layoutZoom) return this;
    return PdfViewportFrame(
      scroll: axis.scrollKeeping(content ?? scroll + anchor,
          from: layoutZoom, to: to, anchor: anchor),
      scale: scale,
      mainTranslate: mainTranslate,
      crossTranslate: crossTranslate,
      layoutZoom: to,
    );
  }

  /// Zoom to effective [zoom] (already within the viewer's limits) about the
  /// content at list point ([listMain], [listCross]), holding it under the
  /// view point it sits at now - wheel, pinch, trackpad and keyboard zoom.
  ///
  /// Two spaces meet here. The pointer is fixed in view space, but the
  /// content under it lives in list space and moves whenever the layout zoom
  /// changes: pages relay out bigger or smaller and re-centre on the cross
  /// axis. So the content's view point is read first, the layout zoom moves
  /// (the scroll absorbs the main axis), the content is remapped to where the
  /// relayout puts it, and the transform puts it back under the view point.
  ///
  /// At or below fit the zoom is all layout and a zoomed-in transform is
  /// dropped; a sub-fit transform belongs to a gesture still in flight and is
  /// left for its settle ([settled]) to fold. With [clampCross] false the
  /// cross axis is left free for a touch pan's rubber band.
  PdfViewportFrame zoomedTo(
    double zoom, {
    required double listMain,
    required double listCross,
    required PdfLayoutZoomAxis axis,
    required double mainView,
    required double crossView,
    bool clampCross = true,
  }) {
    final atMain = viewMainOf(listMain);
    final atCross = viewCrossOf(listCross);
    if (zoom <= 1) {
      final unzoomed = scale > 1
          ? PdfViewportFrame(scroll: scroll, layoutZoom: layoutZoom)
          : this;
      // the anchor is where the content must land once the transform is
      // gone: its view point, not the list point it maps to today
      return unzoomed.withLayoutZoom(zoom,
          axis: axis, anchor: atMain, content: listMain);
    }
    var at = this;
    var main = listMain;
    var cross = listCross;
    if (layoutZoom < 1) {
      at = withLayoutZoom(1, axis: axis, anchor: atMain, content: listMain);
      main = axis.remapMain(listMain, layoutZoom, 1);
      cross = axis.remapCross(listCross, layoutZoom, 1);
    }
    return PdfViewportFrame.zoomedAbout(
      scroll: at.scroll,
      listMain: main,
      listCross: cross,
      scale: zoom,
      atMain: atMain,
      atCross: atCross,
      mainView: mainView,
      crossView: crossView,
      clampCross: clampCross,
    );
  }

  /// A finished zoom gesture settled into the two regimes. The gesture left
  /// all of its zoom in the transform; the settle moves it where it belongs:
  ///
  /// - a total at or below fit becomes layout zoom (at least [minZoom]) and
  ///   the transform goes;
  /// - above fit over a zoomed-out layout, the layout factor folds into the
  ///   transform and the list relays out at fit;
  /// - otherwise the transform stays, its main axis clamped.
  ///
  /// Whatever the gesture zoomed around survives only in the translation, so
  /// both folds carry it: a fold is a pure scale, so pinning the content
  /// under one view point pins every other one - the main axis' centre. The
  /// cross axis is scaled about the view centre, where the layout centres
  /// every page, and is left unclamped for the spring-back to animate.
  PdfViewportFrame settled({
    required PdfLayoutZoomAxis axis,
    required double mainView,
    required double crossView,
    required double minZoom,
  }) {
    final total = scale * layoutZoom;
    final anchor = mainView / 2;
    final content = scale <= 0 ? scroll + anchor : listMainAt(anchor);
    if (total <= 1) {
      return PdfViewportFrame(scroll: scroll, layoutZoom: layoutZoom)
          .withLayoutZoom(total.clamp(minZoom, 1.0).toDouble(),
              axis: axis, anchor: anchor, content: content);
    }
    if (layoutZoom < 1) {
      final fold = layoutZoom;
      final at =
          withLayoutZoom(1, axis: axis, anchor: anchor, content: content);
      if (total <= 1.01) return PdfViewportFrame(scroll: at.scroll);
      // the main translation is whatever the scroll jump could not absorb
      // once the extents clamp it
      final main =
          anchor - total * (axis.remapMain(content, fold, 1) - at.scroll);
      return PdfViewportFrame(
        scroll: at.scroll,
        scale: total,
        mainTranslate: main.clamp(mainView * (1 - total), 0.0).toDouble(),
        crossTranslate: crossTranslate + scale * crossView / 2 * (1 - fold),
      );
    }
    if (scale <= 1.01) return PdfViewportFrame(scroll: scroll);
    return PdfViewportFrame(
      scroll: scroll,
      scale: scale,
      mainTranslate:
          mainTranslate.clamp(mainView * (1 - scale), 0.0).toDouble(),
      crossTranslate: crossTranslate,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfViewportFrame &&
      other.scroll == scroll &&
      other.scale == scale &&
      other.mainTranslate == mainTranslate &&
      other.crossTranslate == crossTranslate &&
      other.layoutZoom == layoutZoom;

  @override
  int get hashCode =>
      Object.hash(scroll, scale, mainTranslate, crossTranslate, layoutZoom);

  @override
  String toString() => 'PdfViewportFrame(scroll: $scroll, scale: $scale, '
      't: ($mainTranslate, $crossTranslate), layoutZoom: $layoutZoom)';
}

/// Where each page sits in a viewer's list space, at the current layout zoom:
/// what [capturePdfViewport] and [placePdfViewport] need to know about the
/// page set.
abstract interface class PdfViewportLayout {
  int get pageCount;

  /// The page under list point ([listMain], [listCross]) - the last one past
  /// the end.
  int pageAt(double listMain, double listCross);

  /// The list-space leading edge of [page] along each axis.
  double mainStartOf(int page);
  double crossStartOf(int page);

  /// [page]'s laid-out size along each axis.
  double mainExtentOf(int page);
  double crossExtentOf(int page);
}

/// The resolution-independent viewport [frame] shows over [layout]: the page
/// under the view's leading corner and the fractions into it. Fractions are
/// layout-zoom independent - numerator and page size scale together - and
/// the zoom is the frame's effective [PdfViewportFrame.zoom].
PdfViewport capturePdfViewport(
    PdfViewportFrame frame, PdfViewportLayout layout) {
  final main = frame.listMainAt(0);
  final cross = frame.listCrossAt(0);
  final page = layout.pageAt(main, cross);
  final mainExtent = layout.mainExtentOf(page);
  final crossExtent = layout.crossExtentOf(page);
  return PdfViewport(
    page: page,
    top: mainExtent <= 0 ? 0 : (main - layout.mainStartOf(page)) / mainExtent,
    left: crossExtent <= 0
        ? 0
        : (cross - layout.crossStartOf(page)) / crossExtent,
    zoom: frame.zoom,
  );
}

/// The frame that puts [viewport]'s point of [page] at the view's leading
/// corner, at [scale] (the transform zoom: 1 at or below fit) over a
/// [layout] already laid out at [layoutZoom] (see
/// [PdfViewportFrame.zoomParts]). Below fit the cross position is the
/// layout's (pages are centred), so only the scroll follows the viewport.
PdfViewportFrame placePdfViewport(
  PdfViewport viewport,
  int page,
  PdfViewportLayout layout, {
  required double scale,
  double layoutZoom = 1,
  required double mainView,
  required double crossView,
  required double maxScroll,
}) =>
    PdfViewportFrame.showing(
      listMain:
          layout.mainStartOf(page) + viewport.top * layout.mainExtentOf(page),
      listCross: layout.crossStartOf(page) +
          viewport.left * layout.crossExtentOf(page),
      scale: scale,
      mainView: mainView,
      crossView: crossView,
      maxScroll: maxScroll,
      layoutZoom: layoutZoom,
    );

/// The list's layout below fit, as far as a change of layout zoom needs it:
/// each slot's main-axis extent at layout zoom 1, the fixed [spacing] between
/// slots, and the [crossView] pages centre in.
///
/// Page sizes scale with the layout zoom but the spacing does not, so a plain
/// ratio drifts by one gap per page ahead of the point - a whole page's worth
/// deep into a long document. These remaps walk the slots instead.
class PdfLayoutZoomAxis {
  const PdfLayoutZoomAxis({
    required this.slotCount,
    required this.unitExtentOf,
    required this.spacing,
    required this.crossView,
  });

  final int slotCount;
  final double Function(int slot) unitExtentOf;
  final double spacing;
  final double crossView;

  /// Maps a main-axis list coordinate from layout zoom [from] to [to]. A
  /// point keeps its fraction into its slot (or its distance into the gap
  /// before it).
  double remapMain(double main, double from, double to) {
    if (from <= 0 || to == from) return main;
    final ratio = to / from;
    if (spacing == 0 || slotCount == 0) return main * ratio;
    var oldStart = 0.0;
    var newStart = 0.0;
    for (var i = 0; i < slotCount; i++) {
      final extent = unitExtentOf(i);
      final oldMain = extent * from;
      if (main < oldStart + oldMain || i == slotCount - 1) {
        return newStart + (main - oldStart) * ratio;
      }
      oldStart += oldMain + spacing;
      newStart += extent * to + spacing;
    }
    return main * ratio;
  }

  /// Maps a cross-axis list coordinate from layout zoom [from] to [to]:
  /// every page is centred on the cross axis and scales about that centre.
  double remapCross(double cross, double from, double to) {
    if (from <= 0 || to == from) return cross;
    final centre = crossView / 2;
    return centre + (cross - centre) * (to / from);
  }

  /// The scroll offset that, after relaying out from layout zoom [from] to
  /// [to], puts [content] (a main-axis list coordinate at [from]) at view
  /// main [anchor] - never negative; the far end clamps once the new extents
  /// exist.
  double scrollKeeping(double content,
          {required double from, required double to, required double anchor}) =>
      math.max(0, remapMain(content, from, to) - anchor);
}
