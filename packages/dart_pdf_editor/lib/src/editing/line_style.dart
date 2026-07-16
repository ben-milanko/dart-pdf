import 'dart:math' as math;

/// The border line style for shape and line annotations: solid, or one of
/// a few dash patterns. Maps to a PDF `/BS /D` dash array scaled to the
/// pen width; `PdfAnnotation.borderDash` reads the array back.
enum PdfLineStyle {
  solid,
  dashed,
  dotted,
  dashDot;

  /// A short human label for menus and tooltips.
  String get label => switch (this) {
        PdfLineStyle.solid => 'Solid',
        PdfLineStyle.dashed => 'Dashed',
        PdfLineStyle.dotted => 'Dotted',
        PdfLineStyle.dashDot => 'Dash-dot',
      };

  /// The `/BS /D` dash array for this style, or null for [solid].
  ///
  /// The pattern size is driven by [scale] (a multiplier, 1 = the default
  /// look) *independently* of the pen [strokeWidth] - so a thin line can
  /// carry big dashes, or a heavy line tight ones. [strokeWidth] still sets
  /// a floor on each segment so the gaps stay visible under a heavy pen
  /// (round/projecting caps would otherwise swallow them). At `scale: 1`
  /// and the default 2pt pen the arrays match the historical
  /// width-proportional values.
  List<double>? dashArray(double strokeWidth, {double scale = 1}) {
    double u(double m) => math.max(strokeWidth, math.max(2, 2 * scale * m));
    return switch (this) {
      PdfLineStyle.solid => null,
      PdfLineStyle.dashed => [u(3), u(2)],
      PdfLineStyle.dotted => [u(1), u(2)],
      PdfLineStyle.dashDot => [u(3), u(2), u(1), u(2)],
    };
  }

  /// Classifies a stored dash array (from `PdfAnnotation.borderDash`) back
  /// to the closest style - so a style control can show the current value.
  /// Null/empty → [solid]; otherwise by segment count and dash:gap ratio.
  static PdfLineStyle ofDashArray(List<double>? dash) {
    if (dash == null || dash.isEmpty) return PdfLineStyle.solid;
    if (dash.length >= 4) return PdfLineStyle.dashDot;
    if (dash.length == 1) return PdfLineStyle.dashed;
    return dash.first < dash[1] ? PdfLineStyle.dotted : PdfLineStyle.dashed;
  }
}
