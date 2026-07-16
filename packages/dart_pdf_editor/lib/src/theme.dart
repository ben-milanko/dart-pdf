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

  /// This theme's fields, with [other]'s filling any nulls.
  PdfScrollbarThemeData mergeOnto(PdfScrollbarThemeData? other) {
    if (other == null) return this;
    return PdfScrollbarThemeData(
      thumbColor: thumbColor ?? other.thumbColor,
      thumbActiveColor: thumbActiveColor ?? other.thumbActiveColor,
      outlineColor: outlineColor ?? other.outlineColor,
      trackColor: trackColor ?? other.trackColor,
      trackActiveColor: trackActiveColor ?? other.trackActiveColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfScrollbarThemeData &&
      other.thumbColor == thumbColor &&
      other.thumbActiveColor == thumbActiveColor &&
      other.outlineColor == outlineColor &&
      other.trackColor == trackColor &&
      other.trackActiveColor == trackActiveColor;

  @override
  int get hashCode => Object.hash(
      thumbColor, thumbActiveColor, outlineColor, trackColor, trackActiveColor);
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

  /// Scrollbar colors, shared by the viewer's bars and the sidebars'.
  final PdfScrollbarThemeData? scrollbar;

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
      other.scrollbar == scrollbar;

  @override
  int get hashCode => Object.hash(
      canvasColor,
      selectionColor,
      selectionHandleColor,
      searchMatchColor,
      currentSearchMatchColor,
      annotationChromeColor,
      elementChromeColor,
      flashColor,
      formFieldHighlightColor,
      scrollbar);
}

/// Provides a [PdfViewerThemeData] to every dart_pdf_editor widget below it
/// (the viewer, its scrollbars, the sidebars' scrollbars, and the
/// editing overlay).
class PdfViewerTheme extends InheritedWidget {
  const PdfViewerTheme({super.key, required this.data, required super.child});

  final PdfViewerThemeData data;

  /// The nearest theme above [context], or an all-defaults one.
  static PdfViewerThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PdfViewerTheme>()?.data ??
      const PdfViewerThemeData();

  @override
  bool updateShouldNotify(PdfViewerTheme oldWidget) => data != oldWidget.data;
}
