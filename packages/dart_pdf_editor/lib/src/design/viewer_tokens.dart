// The one place the viewer's canvas tokens fall back to their stock values.
// Package-private (not exported): painters and overlays read the resolved
// getters instead of repeating `?? const Color(...)` literals.

import 'package:flutter/widgets.dart';

import '../theme.dart';

/// Stock canvas colours.
abstract final class PdfViewerDefaults {
  /// The editing chrome blue (selection boxes, handles, marquee, crop).
  static const chrome = Color(0xFF1E88E5);

  /// The content tool's element-selection orange.
  static const elementChrome = Color(0xFFFB8C00);

  /// The sidebar zoom-to attention pulse.
  static const flash = Color(0xFFFFB300);

  /// The canvas behind the pages under a light / dark theme.
  static const canvasLight = Color(0xFF404347);
  static const canvasDark = Color(0xFF202124);

  /// Text selection: wash and handles.
  static const selection = Color(0x4D2196F3);
  static const selectionHandle = Color(0xFF2196F3);

  /// Search match washes.
  static const searchMatch = Color(0x66FFEB3B);
  static const currentSearchMatch = Color(0x88FF9800);

  /// The form-field highlight wash.
  static const formFieldHighlight = Color(0x2E4D90FE);

  /// Smart alignment guides.
  static const alignmentGuide = Color(0xFFE91E63);

  /// Redaction marks.
  static const redactionHatch = Color(0xFFD32F2F);

  /// Readout chips.
  static const chip = Color(0xE6202124);
  static const chipForeground = Color(0xFFFFFFFF);

  /// Selection handle diameter at 100% zoom.
  static const handleSize = 8.0;

  /// Comparison diff accents.
  static const diffInserted = Color(0xFF2E7D32);
  static const diffDeleted = Color(0xFFE53935);
  static const diffReplaced = Color(0xFFF57C00);
}

/// [PdfViewerThemeData]'s tokens with the stock fallbacks applied. Tokens
/// whose stock value comes from the ambient colour scheme take it as
/// [primary] / [surface] / [onSurface] arguments.
extension PdfViewerTokens on PdfViewerThemeData {
  Color get chrome => annotationChromeColor ?? PdfViewerDefaults.chrome;
  Color get elementChrome =>
      elementChromeColor ?? PdfViewerDefaults.elementChrome;
  Color get flash => flashColor ?? PdfViewerDefaults.flash;
  Color get marquee => marqueeColor ?? chrome;
  Color canvas(Brightness brightness) =>
      canvasColor ??
      (brightness == Brightness.dark
          ? PdfViewerDefaults.canvasDark
          : PdfViewerDefaults.canvasLight);
  Color get selection => selectionColor ?? PdfViewerDefaults.selection;
  Color get selectionHandle =>
      selectionHandleColor ?? PdfViewerDefaults.selectionHandle;
  Color get inlineSelectionHandle =>
      inlineSelectionHandleColor ??
      selectionHandleColor ??
      annotationChromeColor ??
      PdfViewerDefaults.selectionHandle;
  Color get searchMatch => searchMatchColor ?? PdfViewerDefaults.searchMatch;
  Color get currentSearchMatch =>
      currentSearchMatchColor ?? PdfViewerDefaults.currentSearchMatch;
  Color get formFieldHighlight =>
      formFieldHighlightColor ?? PdfViewerDefaults.formFieldHighlight;
  Color snapGrid(Color primary) =>
      snapGridColor ??
      (annotationChromeColor ?? primary).withValues(alpha: 0.22);
  Color get alignmentGuide =>
      alignmentGuideColor ?? PdfViewerDefaults.alignmentGuide;
  Color get redactionHatch =>
      redactionHatchColor ?? PdfViewerDefaults.redactionHatch;
  Color rulerBackground(Color surface) => rulerBackgroundColor ?? surface;
  Color rulerForeground(Color onSurface) => rulerForegroundColor ?? onSurface;
  Color rulerAccent(Color primary) =>
      rulerAccentColor ?? annotationChromeColor ?? primary;
  Color get chip => chipColor ?? PdfViewerDefaults.chip;
  Color get chipForeground =>
      chipForegroundColor ?? PdfViewerDefaults.chipForeground;
  double get handleDiameter => handleSize ?? PdfViewerDefaults.handleSize;
  Color get diffInserted => diffInsertedColor ?? PdfViewerDefaults.diffInserted;
  Color get diffDeleted => diffDeletedColor ?? PdfViewerDefaults.diffDeleted;
  Color get diffReplaced => diffReplacedColor ?? PdfViewerDefaults.diffReplaced;
  Color scrollbarMarker(Color primary) => scrollbar?.markerColor ?? primary;
}
