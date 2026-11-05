import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'viewport.dart';

/// Where a [PdfViewer] is looking, as one value: the scroll offset along the
/// main (scroll) axis plus the zoom transform's scale and translation, in
/// axis terms rather than x/y.
///
/// Above fit, zoom rides a scale + translation transform over the fit-laid-out
/// list, so a view-space point unprojects to list space as `(p - t) / s`, plus
/// the scroll offset along the main axis. Below fit the list itself lays out
/// smaller and the transform is the identity (`scale` 1). Every capture,
/// placement and framing is that projection or its inverse; this is the one
/// place it is written.
@immutable
class PdfViewportFrame {
  const PdfViewportFrame({
    required this.scroll,
    this.scale = 1,
    this.mainTranslate = 0,
    this.crossTranslate = 0,
  });

  /// The list's scroll offset.
  final double scroll;

  /// The transform's scale (1 at or below fit).
  final double scale;

  /// The transform's translation along the main and cross axes (view
  /// pixels, at most 0).
  final double mainTranslate;
  final double crossTranslate;

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
  /// inside a [mainView] x [crossView] viewport.
  factory PdfViewportFrame.showing({
    required double listMain,
    required double listCross,
    required double scale,
    required double mainView,
    required double crossView,
    required double maxScroll,
    double atMain = 0,
    double atCross = 0,
  }) {
    final s = scale < 1 ? 1.0 : scale;
    final scroll = (listMain - atMain).clamp(0.0, maxScroll).toDouble();
    if (s == 1) return PdfViewportFrame(scroll: scroll);
    return PdfViewportFrame(
      scroll: scroll,
      scale: s,
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
  }) {
    if (scale <= 1.01) return PdfViewportFrame(scroll: scroll);
    final mainTranslate = atMain - scale * (listMain - scroll);
    final crossTranslate = atCross - scale * listCross;
    return PdfViewportFrame(
      scroll: scroll,
      scale: scale,
      mainTranslate: mainTranslate.clamp(mainView * (1 - scale), 0.0),
      crossTranslate: clampCross
          ? crossTranslate.clamp(crossView * (1 - scale), 0.0)
          : crossTranslate,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfViewportFrame &&
      other.scroll == scroll &&
      other.scale == scale &&
      other.mainTranslate == mainTranslate &&
      other.crossTranslate == crossTranslate;

  @override
  int get hashCode => Object.hash(scroll, scale, mainTranslate, crossTranslate);

  @override
  String toString() => 'PdfViewportFrame(scroll: $scroll, scale: $scale, '
      't: ($mainTranslate, $crossTranslate))';
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
/// layout-zoom independent - numerator and page size scale together - so
/// [zoom] is recorded as given.
PdfViewport capturePdfViewport(PdfViewportFrame frame, PdfViewportLayout layout,
    {required double zoom}) {
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
    zoom: zoom,
  );
}

/// The frame that puts [viewport]'s point of [page] at the view's leading
/// corner, at [scale] (the transform zoom: 1 at or below fit). Below fit the
/// cross position is the layout's (pages are centred), so only the scroll
/// follows the viewport.
PdfViewportFrame placePdfViewport(
  PdfViewport viewport,
  int page,
  PdfViewportLayout layout, {
  required double scale,
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
