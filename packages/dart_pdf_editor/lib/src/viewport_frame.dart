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
