// The editor's design tokens: widgets-layer values only (colours, text
// styles, lengths), so they read the same under a Material, Cupertino or
// plain widgets host and survive the 6.0 switch to material_ui unchanged.

import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'editor_presenter.dart' show PdfEditorScope;

/// Below this width the stock shells go compact: side panels become bottom
/// sheets, the header's trailing controls collapse into a Controls sheet,
/// and the editing toolbar docks below the viewer as a solid bar. Override
/// it per editor with [PdfEditorThemeData.compactWidth].
const double pdfShellCompactWidth = 700;

/// Design tokens for the editor's chrome (header, toolbar, panels, sheets
/// and notices) plus the viewer's canvas tokens ([viewer]). Every field is
/// optional; a null keeps the stock look.
///
/// Provide it through [PdfEditorView.theme] or a `PdfEditorScope(theme:)`
/// above the editor widgets:
///
/// ```dart
/// PdfEditorView(
///   controller: controller,
///   theme: const PdfEditorThemeData(
///     danger: Color(0xFFB00020),
///     compactWidth: 600,
///     viewer: PdfViewerThemeData(annotationChromeColor: Color(0xFF00897B)),
///   ),
/// )
/// ```
///
/// Read the effective tokens with `PdfEditorThemeData.of(context)`, which
/// fills every null with [fallback].
@immutable
class PdfEditorThemeData {
  /// Tokens; nulls keep the stock values.
  const PdfEditorThemeData({
    this.viewer,
    this.success,
    this.warning,
    this.danger,
    this.info,
    this.sectionLabel,
    this.compactWidth,
    this.toastLift,
  });

  /// The stock tokens: the values the editor used before tokens existed.
  /// [sectionLabel] and [viewer] stay null - their stock looks derive from
  /// the ambient colour scheme and [PdfViewerThemeData]'s own fallbacks.
  static const PdfEditorThemeData fallback = PdfEditorThemeData(
    success: Color(0xFF4CAF50),
    warning: Color(0xFFFF9800),
    danger: Color(0xFFF44336),
    info: Color(0xFF2196F3),
    compactWidth: pdfShellCompactWidth,
    toastLift: 96,
  );

  /// Canvas tokens (selection, chrome, guides, rulers, ...). Installed as
  /// the editor's [PdfViewerTheme] beneath any ambient one; a widget's own
  /// `viewerTheme` argument still wins.
  final PdfViewerThemeData? viewer;

  /// A good outcome: a trusted signature, an accepted review state.
  final Color? success;

  /// A caution: an unverified or self-signed signature, a cancelled review.
  final Color? warning;

  /// A failure: an invalid or revoked signature, a rejected review.
  final Color? danger;

  /// Neutral information: a marked review state.
  final Color? info;

  /// The small upper-case section labels in sheets and toolbar strips,
  /// merged over each label's stock style (set only a colour to recolour
  /// them, say).
  final TextStyle? sectionLabel;

  /// The width below which the shells go compact ([pdfShellCompactWidth]).
  final double? compactWidth;

  /// How far floating notices are lifted above the bottom edge, clearing
  /// the editing toolbar's dock (the device's bottom inset is added).
  final double? toastLift;

  /// The tokens in effect at [context]: the nearest [PdfEditorScope]'s
  /// theme with every null filled from [fallback]. With [listen] false,
  /// [context] does not rebuild when the scope changes (for callbacks).
  static PdfEditorThemeData of(BuildContext context, {bool listen = true}) =>
      fallback.merge(PdfEditorScope.maybeOf(context, listen: listen)?.theme);

  /// This theme with [other]'s non-null fields taking precedence ([viewer]
  /// merges field by field).
  PdfEditorThemeData merge(PdfEditorThemeData? other) {
    if (other == null) return this;
    return PdfEditorThemeData(
      viewer: viewer == null ? other.viewer : viewer!.merge(other.viewer),
      success: other.success ?? success,
      warning: other.warning ?? warning,
      danger: other.danger ?? danger,
      info: other.info ?? info,
      sectionLabel: sectionLabel == null
          ? other.sectionLabel
          : sectionLabel!.merge(other.sectionLabel),
      compactWidth: other.compactWidth ?? compactWidth,
      toastLift: other.toastLift ?? toastLift,
    );
  }

  /// A copy with the given fields replaced.
  PdfEditorThemeData copyWith({
    PdfViewerThemeData? viewer,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    TextStyle? sectionLabel,
    double? compactWidth,
    double? toastLift,
  }) =>
      PdfEditorThemeData(
        viewer: viewer ?? this.viewer,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        info: info ?? this.info,
        sectionLabel: sectionLabel ?? this.sectionLabel,
        compactWidth: compactWidth ?? this.compactWidth,
        toastLift: toastLift ?? this.toastLift,
      );

  /// Interpolates between [a] and [b] (for animated theme changes).
  static PdfEditorThemeData lerp(
      PdfEditorThemeData? a, PdfEditorThemeData? b, double t) {
    if (identical(a, b) && a != null) return a;
    return PdfEditorThemeData(
      viewer: PdfViewerThemeData.lerp(a?.viewer, b?.viewer, t),
      success: Color.lerp(a?.success, b?.success, t),
      warning: Color.lerp(a?.warning, b?.warning, t),
      danger: Color.lerp(a?.danger, b?.danger, t),
      info: Color.lerp(a?.info, b?.info, t),
      sectionLabel: TextStyle.lerp(a?.sectionLabel, b?.sectionLabel, t),
      compactWidth: lerpDouble(a?.compactWidth, b?.compactWidth, t),
      toastLift: lerpDouble(a?.toastLift, b?.toastLift, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfEditorThemeData &&
      other.viewer == viewer &&
      other.success == success &&
      other.warning == warning &&
      other.danger == danger &&
      other.info == info &&
      other.sectionLabel == sectionLabel &&
      other.compactWidth == compactWidth &&
      other.toastLift == toastLift;

  @override
  int get hashCode => Object.hash(viewer, success, warning, danger, info,
      sectionLabel, compactWidth, toastLift);
}

/// The compact-layout width in effect at [context]
/// ([PdfEditorThemeData.compactWidth], else [pdfShellCompactWidth]).
double pdfCompactWidthOf(BuildContext context) =>
    PdfEditorThemeData.of(context).compactWidth ?? pdfShellCompactWidth;
