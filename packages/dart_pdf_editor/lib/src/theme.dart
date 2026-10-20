import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

/// Colors for the viewer-style scrollbar ([PdfScrollbar] in the viewer
/// and both sidebars). Null fields fall back to the stock palette - a
/// light capsule with a dark outline, chosen to read against the dark
/// canvas, white pages, and light or dark panel surfaces alike.
@immutable
class PdfScrollbarThemeData {
  const PdfScrollbarThemeData({
    this.thumbColor,
    this.thumbActiveColor,
    this.outlineColor,
    this.trackColor,
    this.trackActiveColor,
    this.markerColor,
  });

  /// The thumb's fill at rest.
  final Color? thumbColor;

  /// The thumb's fill while hovered or dragged.
  final Color? thumbActiveColor;

  /// The hairline around the thumb (carries the contrast on light
  /// backgrounds, where the fill alone would wash out).
  final Color? outlineColor;

  /// The track scrim at rest.
  final Color? trackColor;

  /// The track scrim while hovered or dragged.
  final Color? trackActiveColor;

  /// The chapter markers on the track ([PdfScrollbarMarker]). Defaults to
  /// the ambient colour scheme's primary colour.
  final Color? markerColor;

  /// This theme's fields, with [other]'s filling any nulls.
  PdfScrollbarThemeData mergeOnto(PdfScrollbarThemeData? other) {
    if (other == null) return this;
    return PdfScrollbarThemeData(
      thumbColor: thumbColor ?? other.thumbColor,
      thumbActiveColor: thumbActiveColor ?? other.thumbActiveColor,
      outlineColor: outlineColor ?? other.outlineColor,
      trackColor: trackColor ?? other.trackColor,
      trackActiveColor: trackActiveColor ?? other.trackActiveColor,
      markerColor: markerColor ?? other.markerColor,
    );
  }

  /// This theme with [other]'s non-null fields taking precedence (the
  /// reverse of [mergeOnto]).
  PdfScrollbarThemeData merge(PdfScrollbarThemeData? other) =>
      other == null ? this : other.mergeOnto(this);

  /// A copy with the given fields replaced.
  PdfScrollbarThemeData copyWith({
    Color? thumbColor,
    Color? thumbActiveColor,
    Color? outlineColor,
    Color? trackColor,
    Color? trackActiveColor,
    Color? markerColor,
  }) =>
      PdfScrollbarThemeData(
        thumbColor: thumbColor ?? this.thumbColor,
        thumbActiveColor: thumbActiveColor ?? this.thumbActiveColor,
        outlineColor: outlineColor ?? this.outlineColor,
        trackColor: trackColor ?? this.trackColor,
        trackActiveColor: trackActiveColor ?? this.trackActiveColor,
        markerColor: markerColor ?? this.markerColor,
      );

  /// Interpolates between [a] and [b].
  static PdfScrollbarThemeData? lerp(
      PdfScrollbarThemeData? a, PdfScrollbarThemeData? b, double t) {
    if (a == null && b == null) return null;
    if (identical(a, b)) return a;
    return PdfScrollbarThemeData(
      thumbColor: Color.lerp(a?.thumbColor, b?.thumbColor, t),
      thumbActiveColor: Color.lerp(a?.thumbActiveColor, b?.thumbActiveColor, t),
      outlineColor: Color.lerp(a?.outlineColor, b?.outlineColor, t),
      trackColor: Color.lerp(a?.trackColor, b?.trackColor, t),
      trackActiveColor: Color.lerp(a?.trackActiveColor, b?.trackActiveColor, t),
      markerColor: Color.lerp(a?.markerColor, b?.markerColor, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfScrollbarThemeData &&
      other.thumbColor == thumbColor &&
      other.thumbActiveColor == thumbActiveColor &&
      other.outlineColor == outlineColor &&
      other.trackColor == trackColor &&
      other.trackActiveColor == trackActiveColor &&
      other.markerColor == markerColor;

  @override
  int get hashCode => Object.hash(thumbColor, thumbActiveColor, outlineColor,
      trackColor, trackActiveColor, markerColor);
}

/// Visual styling for [PdfViewer] and its companion widgets - the
/// scrollbars, text selection and search highlights, and the editing
/// overlay's selection chrome. Every field is optional; nulls keep the
/// stock look. Widget-level parameters ([PdfViewer.backgroundColor])
/// win over the theme.
///
/// Install it above the viewer with [PdfViewerTheme]:
///
/// ```dart
/// PdfViewerTheme(
///   data: PdfViewerThemeData(
///     canvasColor: Colors.blueGrey.shade900,
///     selectionColor: Colors.teal.withValues(alpha: 0.3),
///   ),
///   child: PdfViewer(...),
/// )
/// ```
@immutable
class PdfViewerThemeData {
  const PdfViewerThemeData({
    this.canvasColor,
    this.selectionColor,
    this.selectionHandleColor,
    this.searchMatchColor,
    this.currentSearchMatchColor,
    this.annotationChromeColor,
    this.elementChromeColor,
    this.flashColor,
    this.formFieldHighlightColor,
    this.marqueeColor,
    this.snapGridColor,
    this.alignmentGuideColor,
    this.redactionHatchColor,
    this.rulerBackgroundColor,
    this.rulerForegroundColor,
    this.rulerAccentColor,
    this.chipColor,
    this.chipForegroundColor,
    this.handleSize,
    this.inlineSelectionHandleColor,
    this.diffInsertedColor,
    this.diffDeletedColor,
    this.diffReplacedColor,
    this.scrollbar,
  });

  /// The canvas behind the pages. Defaults to a slate gray (or a darker
  /// one under a dark [Theme]); [PdfViewer.backgroundColor] overrides
  /// both.
  final Color? canvasColor;

  /// The text-selection highlight wash (translucent - it paints over
  /// the page text).
  final Color? selectionColor;

  /// The touch selection's drag handles (the lollipops at either end of
  /// a long-press text selection). Opaque; defaults to the stock blue.
  final Color? selectionHandleColor;

  /// The highlight wash over search matches.
  final Color? searchMatchColor;

  /// The highlight wash over the current search match.
  final Color? currentSearchMatchColor;

  /// The editing overlay's selection chrome: boxes, handles, marquee,
  /// and shape/ink previews' selection accents. Translucent fills are
  /// derived from it.
  final Color? annotationChromeColor;

  /// The content tool's element-selection chrome (distinct from the
  /// annotation chrome so selected page content reads differently).
  final Color? elementChromeColor;

  /// The attention pulse around an annotation the sidebar zoomed to.
  final Color? flashColor;

  /// The wash over form-field widgets while
  /// [PdfViewer.highlightFormFields] is on. Used as given (carry your
  /// own alpha - the default is translucent blue); the fields' hairline
  /// border derives from it.
  final Color? formFieldHighlightColor;

  /// The rubber-band selection marquee. Defaults to
  /// [annotationChromeColor].
  final Color? marqueeColor;

  /// The snap grid's lines (used as given - carry your own alpha).
  /// Defaults to [annotationChromeColor] (else the colour scheme's primary)
  /// at 22% opacity.
  final Color? snapGridColor;

  /// The smart alignment guides shown while dragging. Defaults to pink.
  final Color? alignmentGuideColor;

  /// The border and hatching of a region marked for redaction. The
  /// hatching uses it at 40% opacity. Defaults to red.
  final Color? redactionHatchColor;

  /// The page rulers' band. Defaults to the colour scheme's surface.
  final Color? rulerBackgroundColor;

  /// The page rulers' ticks and labels. Defaults to the colour scheme's
  /// onSurface.
  final Color? rulerForegroundColor;

  /// The page rulers' pointer and selection marks. Defaults to
  /// [annotationChromeColor] (else the colour scheme's primary).
  final Color? rulerAccentColor;

  /// The floating readout chips on the page (measurement and style
  /// readouts). Defaults to a near-black translucent fill.
  final Color? chipColor;

  /// The text on [chipColor]. Defaults to white.
  final Color? chipForegroundColor;

  /// The diameter, in logical pixels at 100% zoom, of the selection's
  /// resize handles. Defaults to 8.
  final double? handleSize;

  /// The drag handles of a text selection inside an in-place text editor
  /// (free text, content edits). Defaults to [selectionHandleColor], then
  /// [annotationChromeColor], then blue.
  final Color? inlineSelectionHandleColor;

  /// The document comparison's inserted-text accent. Defaults to green.
  final Color? diffInsertedColor;

  /// The document comparison's deleted-text accent. Defaults to red.
  final Color? diffDeletedColor;

  /// The document comparison's replaced-text accent. Defaults to orange.
  final Color? diffReplacedColor;

  /// Scrollbar colors, shared by the viewer's bars and the sidebars'.
  final PdfScrollbarThemeData? scrollbar;

  /// This theme with [other]'s non-null fields taking precedence
  /// ([scrollbar] merges field by field).
  PdfViewerThemeData merge(PdfViewerThemeData? other) {
    if (other == null) return this;
    return PdfViewerThemeData(
      canvasColor: other.canvasColor ?? canvasColor,
      selectionColor: other.selectionColor ?? selectionColor,
      selectionHandleColor: other.selectionHandleColor ?? selectionHandleColor,
      searchMatchColor: other.searchMatchColor ?? searchMatchColor,
      currentSearchMatchColor:
          other.currentSearchMatchColor ?? currentSearchMatchColor,
      annotationChromeColor:
          other.annotationChromeColor ?? annotationChromeColor,
      elementChromeColor: other.elementChromeColor ?? elementChromeColor,
      flashColor: other.flashColor ?? flashColor,
      formFieldHighlightColor:
          other.formFieldHighlightColor ?? formFieldHighlightColor,
      marqueeColor: other.marqueeColor ?? marqueeColor,
      snapGridColor: other.snapGridColor ?? snapGridColor,
      alignmentGuideColor: other.alignmentGuideColor ?? alignmentGuideColor,
      redactionHatchColor: other.redactionHatchColor ?? redactionHatchColor,
      rulerBackgroundColor: other.rulerBackgroundColor ?? rulerBackgroundColor,
      rulerForegroundColor: other.rulerForegroundColor ?? rulerForegroundColor,
      rulerAccentColor: other.rulerAccentColor ?? rulerAccentColor,
      chipColor: other.chipColor ?? chipColor,
      chipForegroundColor: other.chipForegroundColor ?? chipForegroundColor,
      handleSize: other.handleSize ?? handleSize,
      inlineSelectionHandleColor:
          other.inlineSelectionHandleColor ?? inlineSelectionHandleColor,
      diffInsertedColor: other.diffInsertedColor ?? diffInsertedColor,
      diffDeletedColor: other.diffDeletedColor ?? diffDeletedColor,
      diffReplacedColor: other.diffReplacedColor ?? diffReplacedColor,
      scrollbar: scrollbar == null
          ? other.scrollbar
          : scrollbar!.merge(other.scrollbar),
    );
  }

  /// A copy with the given fields replaced.
  PdfViewerThemeData copyWith({
    Color? canvasColor,
    Color? selectionColor,
    Color? selectionHandleColor,
    Color? searchMatchColor,
    Color? currentSearchMatchColor,
    Color? annotationChromeColor,
    Color? elementChromeColor,
    Color? flashColor,
    Color? formFieldHighlightColor,
    Color? marqueeColor,
    Color? snapGridColor,
    Color? alignmentGuideColor,
    Color? redactionHatchColor,
    Color? rulerBackgroundColor,
    Color? rulerForegroundColor,
    Color? rulerAccentColor,
    Color? chipColor,
    Color? chipForegroundColor,
    double? handleSize,
    Color? inlineSelectionHandleColor,
    Color? diffInsertedColor,
    Color? diffDeletedColor,
    Color? diffReplacedColor,
    PdfScrollbarThemeData? scrollbar,
  }) =>
      PdfViewerThemeData(
        canvasColor: canvasColor ?? this.canvasColor,
        selectionColor: selectionColor ?? this.selectionColor,
        selectionHandleColor: selectionHandleColor ?? this.selectionHandleColor,
        searchMatchColor: searchMatchColor ?? this.searchMatchColor,
        currentSearchMatchColor:
            currentSearchMatchColor ?? this.currentSearchMatchColor,
        annotationChromeColor:
            annotationChromeColor ?? this.annotationChromeColor,
        elementChromeColor: elementChromeColor ?? this.elementChromeColor,
        flashColor: flashColor ?? this.flashColor,
        formFieldHighlightColor:
            formFieldHighlightColor ?? this.formFieldHighlightColor,
        marqueeColor: marqueeColor ?? this.marqueeColor,
        snapGridColor: snapGridColor ?? this.snapGridColor,
        alignmentGuideColor: alignmentGuideColor ?? this.alignmentGuideColor,
        redactionHatchColor: redactionHatchColor ?? this.redactionHatchColor,
        rulerBackgroundColor: rulerBackgroundColor ?? this.rulerBackgroundColor,
        rulerForegroundColor: rulerForegroundColor ?? this.rulerForegroundColor,
        rulerAccentColor: rulerAccentColor ?? this.rulerAccentColor,
        chipColor: chipColor ?? this.chipColor,
        chipForegroundColor: chipForegroundColor ?? this.chipForegroundColor,
        handleSize: handleSize ?? this.handleSize,
        inlineSelectionHandleColor:
            inlineSelectionHandleColor ?? this.inlineSelectionHandleColor,
        diffInsertedColor: diffInsertedColor ?? this.diffInsertedColor,
        diffDeletedColor: diffDeletedColor ?? this.diffDeletedColor,
        diffReplacedColor: diffReplacedColor ?? this.diffReplacedColor,
        scrollbar: scrollbar ?? this.scrollbar,
      );

  /// Interpolates between [a] and [b] (for animated theme changes).
  static PdfViewerThemeData? lerp(
      PdfViewerThemeData? a, PdfViewerThemeData? b, double t) {
    if (a == null && b == null) return null;
    if (identical(a, b)) return a;
    return PdfViewerThemeData(
      canvasColor: Color.lerp(a?.canvasColor, b?.canvasColor, t),
      selectionColor: Color.lerp(a?.selectionColor, b?.selectionColor, t),
      selectionHandleColor:
          Color.lerp(a?.selectionHandleColor, b?.selectionHandleColor, t),
      searchMatchColor: Color.lerp(a?.searchMatchColor, b?.searchMatchColor, t),
      currentSearchMatchColor:
          Color.lerp(a?.currentSearchMatchColor, b?.currentSearchMatchColor, t),
      annotationChromeColor:
          Color.lerp(a?.annotationChromeColor, b?.annotationChromeColor, t),
      elementChromeColor:
          Color.lerp(a?.elementChromeColor, b?.elementChromeColor, t),
      flashColor: Color.lerp(a?.flashColor, b?.flashColor, t),
      formFieldHighlightColor:
          Color.lerp(a?.formFieldHighlightColor, b?.formFieldHighlightColor, t),
      marqueeColor: Color.lerp(a?.marqueeColor, b?.marqueeColor, t),
      snapGridColor: Color.lerp(a?.snapGridColor, b?.snapGridColor, t),
      alignmentGuideColor:
          Color.lerp(a?.alignmentGuideColor, b?.alignmentGuideColor, t),
      redactionHatchColor:
          Color.lerp(a?.redactionHatchColor, b?.redactionHatchColor, t),
      rulerBackgroundColor:
          Color.lerp(a?.rulerBackgroundColor, b?.rulerBackgroundColor, t),
      rulerForegroundColor:
          Color.lerp(a?.rulerForegroundColor, b?.rulerForegroundColor, t),
      rulerAccentColor: Color.lerp(a?.rulerAccentColor, b?.rulerAccentColor, t),
      chipColor: Color.lerp(a?.chipColor, b?.chipColor, t),
      chipForegroundColor:
          Color.lerp(a?.chipForegroundColor, b?.chipForegroundColor, t),
      handleSize: lerpDouble(a?.handleSize, b?.handleSize, t),
      inlineSelectionHandleColor: Color.lerp(
          a?.inlineSelectionHandleColor, b?.inlineSelectionHandleColor, t),
      diffInsertedColor:
          Color.lerp(a?.diffInsertedColor, b?.diffInsertedColor, t),
      diffDeletedColor: Color.lerp(a?.diffDeletedColor, b?.diffDeletedColor, t),
      diffReplacedColor:
          Color.lerp(a?.diffReplacedColor, b?.diffReplacedColor, t),
      scrollbar: PdfScrollbarThemeData.lerp(a?.scrollbar, b?.scrollbar, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfViewerThemeData &&
      other.canvasColor == canvasColor &&
      other.selectionColor == selectionColor &&
      other.selectionHandleColor == selectionHandleColor &&
      other.searchMatchColor == searchMatchColor &&
      other.currentSearchMatchColor == currentSearchMatchColor &&
      other.annotationChromeColor == annotationChromeColor &&
      other.elementChromeColor == elementChromeColor &&
      other.flashColor == flashColor &&
      other.formFieldHighlightColor == formFieldHighlightColor &&
      other.marqueeColor == marqueeColor &&
      other.snapGridColor == snapGridColor &&
      other.alignmentGuideColor == alignmentGuideColor &&
      other.redactionHatchColor == redactionHatchColor &&
      other.rulerBackgroundColor == rulerBackgroundColor &&
      other.rulerForegroundColor == rulerForegroundColor &&
      other.rulerAccentColor == rulerAccentColor &&
      other.chipColor == chipColor &&
      other.chipForegroundColor == chipForegroundColor &&
      other.handleSize == handleSize &&
      other.inlineSelectionHandleColor == inlineSelectionHandleColor &&
      other.diffInsertedColor == diffInsertedColor &&
      other.diffDeletedColor == diffDeletedColor &&
      other.diffReplacedColor == diffReplacedColor &&
      other.scrollbar == scrollbar;

  @override
  int get hashCode => Object.hashAll([
        canvasColor,
        selectionColor,
        selectionHandleColor,
        searchMatchColor,
        currentSearchMatchColor,
        annotationChromeColor,
        elementChromeColor,
        flashColor,
        formFieldHighlightColor,
        marqueeColor,
        snapGridColor,
        alignmentGuideColor,
        redactionHatchColor,
        rulerBackgroundColor,
        rulerForegroundColor,
        rulerAccentColor,
        chipColor,
        chipForegroundColor,
        handleSize,
        inlineSelectionHandleColor,
        diffInsertedColor,
        diffDeletedColor,
        diffReplacedColor,
        scrollbar,
      ]);
}

/// Provides a [PdfViewerThemeData] to every dart_pdf_editor widget below it
/// (the viewer, its scrollbars, the sidebars' scrollbars, and the
/// editing overlay).
class PdfViewerTheme extends InheritedWidget {
  const PdfViewerTheme({super.key, required this.data, required super.child});

  final PdfViewerThemeData data;

  /// The nearest theme above [context], or an all-defaults one.
  static PdfViewerThemeData of(BuildContext context) =>
      maybeOf(context) ?? const PdfViewerThemeData();

  /// The nearest theme above [context], or null when there is none.
  static PdfViewerThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PdfViewerTheme>()?.data;

  @override
  bool updateShouldNotify(PdfViewerTheme oldWidget) => data != oldWidget.data;
}
