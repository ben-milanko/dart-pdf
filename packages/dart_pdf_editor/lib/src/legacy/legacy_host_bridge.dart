// The one place the library touches the legacy design libraries
// (package:flutter/material.dart and package:flutter/cupertino.dart). The
// editor's chrome is built with material_ui, whose Theme, ScaffoldMessenger
// and CupertinoTheme are different types from the legacy ones, so a host on a
// legacy MaterialApp (or CupertinoApp) would otherwise lose its colours and
// notices at the editor's edge. This bridge reads just enough of the legacy
// host to carry them across:
//
// * the host's legacy `ThemeData` -> a material_ui `ThemeData` (all colour
//   scheme roles, the text theme, icon theme, platform, visual density and
//   Material 3 flag), cached per host theme;
// * a legacy CupertinoApp's primary colour and brightness;
// * a notice shown as a SnackBar on the host's legacy ScaffoldMessenger.
//
// Component themes and ThemeExtensions do not cross: a host that wants them
// in the editor wraps it in a material_ui Theme (or uses PdfEditorThemeData).
//
// Size discipline. Each public entry point is an expression guarded by the
// const [kPdfLegacyMaterialBridge] (`flag ? _impl() : null`), so `--dart-define=PDF_LEGACY_MATERIAL_BRIDGE=false`
// folds it to a constant and the implementation, and every legacy class it
// mentions, drops out. tool/check_legacy_bridge_dce.sh proves that build is
// byte-identical to one without the bridge. Keep the guard in exactly that
// form: a statement guard (`if (!flag) return null; ...`) or `flag && ...`
// also strips the legacy code, but only after dart2js has counted it, and
// the changed inlining decisions leave ~1 KB of difference.
// With the define on, the reads stay lean: `findAncestorWidgetOfExactType`
// plus `Theme.maybeBrightnessOf` for the rebuild dependency. Never call the
// legacy `Theme.of`: it pulls in `ThemeData.fallback()` and with it most of
// the legacy theme code (~67 KB of JS). The compiler cannot prove a
// material_ui host never builds a legacy Theme, so the bridge costs such a
// host ~11 KB of JS unless the define turns it off.
//
// tool/check_design_imports.dart allows legacy imports only under
// lib/src/legacy/. When the SDK removes flutter/material, this file goes and
// the define becomes a no-op.

import 'package:flutter/cupertino.dart' as legacy_cupertino;
import 'package:flutter/material.dart' as legacy;
import 'package:material_ui/material_ui.dart';

/// Whether the legacy-host bridge is compiled in: true unless the app is
/// built with `--dart-define=PDF_LEGACY_MATERIAL_BRIDGE=false`.
///
/// The bridge lets the editor (built on material_ui) take its theme from a
/// host on the legacy `package:flutter/material.dart` `MaterialApp`/`Theme`
/// (or `package:flutter/cupertino.dart` `CupertinoApp`) and show its notices
/// on that host's `ScaffoldMessenger`. Turn it off when no host of the
/// editor uses those: the editor then ignores a legacy host's theme and
/// messenger, and the bridge costs nothing.
const bool kPdfLegacyMaterialBridge =
    bool.fromEnvironment('PDF_LEGACY_MATERIAL_BRIDGE', defaultValue: true);

/// The material_ui theme matching the legacy `Theme` above [context], or
/// null when there is none (or the bridge is compiled out). [context]
/// rebuilds when the host theme changes.
ThemeData? pdfLegacyHostTheme(BuildContext context) =>
    kPdfLegacyMaterialBridge ? _hostTheme(context) : null;

ThemeData? _hostTheme(BuildContext context) {
  final host = context.findAncestorWidgetOfExactType<legacy.Theme>()?.data;
  if (host == null) return null;
  // the dependency: any change to the host theme rebuilds the editor's
  legacy.Theme.maybeBrightnessOf(context);
  return _bridged[host] ??= _bridgeTheme(host);
}

final _bridged = Expando<ThemeData>('pdfLegacyHostTheme');

/// [data] - a legacy host's `IconTheme` - with a legacy default icon colour
/// swapped for material_ui's own; any other colour is kept.
///
/// material_ui's `IconButton` (like its `Tab` and `SearchAnchor`) tells "no
/// custom icon colour" by *identity*: `identical(IconTheme.of(context).color,
/// kDefaultIconDarkColor)`. Both libraries declare that colour as a `final`
/// (not `const`) global, so the legacy host's default is a different object
/// and reads as a custom colour: every toolbar `IconButton` then draws in
/// that one colour whatever its state, and the selected tool loses its
/// primary tint (and the 200 ms tint transition when it changes).
IconThemeData pdfLegacyHostIconTheme(IconThemeData data) =>
    kPdfLegacyMaterialBridge ? _materialIconTheme(data) : data;

IconThemeData _materialIconTheme(IconThemeData data) {
  final color = data.color;
  if (identical(color, legacy.kDefaultIconDarkColor)) {
    return data.copyWith(color: kDefaultIconDarkColor);
  }
  if (identical(color, legacy.kDefaultIconLightColor)) {
    return data.copyWith(color: kDefaultIconLightColor);
  }
  return data;
}

ThemeData _bridgeTheme(legacy.ThemeData host) {
  final c = host.colorScheme;
  final t = host.textTheme;
  return ThemeData(
    useMaterial3: host.useMaterial3,
    platform: host.platform,
    visualDensity: VisualDensity(
      horizontal: host.visualDensity.horizontal,
      vertical: host.visualDensity.vertical,
    ),
    iconTheme: _materialIconTheme(host.iconTheme),
    textTheme: TextTheme(
      displayLarge: t.displayLarge,
      displayMedium: t.displayMedium,
      displaySmall: t.displaySmall,
      headlineLarge: t.headlineLarge,
      headlineMedium: t.headlineMedium,
      headlineSmall: t.headlineSmall,
      titleLarge: t.titleLarge,
      titleMedium: t.titleMedium,
      titleSmall: t.titleSmall,
      bodyLarge: t.bodyLarge,
      bodyMedium: t.bodyMedium,
      bodySmall: t.bodySmall,
      labelLarge: t.labelLarge,
      labelMedium: t.labelMedium,
      labelSmall: t.labelSmall,
    ),
    colorScheme: ColorScheme(
      brightness: c.brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primaryContainer,
      onPrimaryContainer: c.onPrimaryContainer,
      primaryFixed: c.primaryFixed,
      primaryFixedDim: c.primaryFixedDim,
      onPrimaryFixed: c.onPrimaryFixed,
      onPrimaryFixedVariant: c.onPrimaryFixedVariant,
      secondary: c.secondary,
      onSecondary: c.onSecondary,
      secondaryContainer: c.secondaryContainer,
      onSecondaryContainer: c.onSecondaryContainer,
      secondaryFixed: c.secondaryFixed,
      secondaryFixedDim: c.secondaryFixedDim,
      onSecondaryFixed: c.onSecondaryFixed,
      onSecondaryFixedVariant: c.onSecondaryFixedVariant,
      tertiary: c.tertiary,
      onTertiary: c.onTertiary,
      tertiaryContainer: c.tertiaryContainer,
      onTertiaryContainer: c.onTertiaryContainer,
      tertiaryFixed: c.tertiaryFixed,
      tertiaryFixedDim: c.tertiaryFixedDim,
      onTertiaryFixed: c.onTertiaryFixed,
      onTertiaryFixedVariant: c.onTertiaryFixedVariant,
      error: c.error,
      onError: c.onError,
      errorContainer: c.errorContainer,
      onErrorContainer: c.onErrorContainer,
      surface: c.surface,
      onSurface: c.onSurface,
      surfaceDim: c.surfaceDim,
      surfaceBright: c.surfaceBright,
      surfaceContainerLowest: c.surfaceContainerLowest,
      surfaceContainerLow: c.surfaceContainerLow,
      surfaceContainer: c.surfaceContainer,
      surfaceContainerHigh: c.surfaceContainerHigh,
      surfaceContainerHighest: c.surfaceContainerHighest,
      onSurfaceVariant: c.onSurfaceVariant,
      outline: c.outline,
      outlineVariant: c.outlineVariant,
      shadow: c.shadow,
      scrim: c.scrim,
      inverseSurface: c.inverseSurface,
      onInverseSurface: c.onInverseSurface,
      inversePrimary: c.inversePrimary,
      surfaceTint: c.surfaceTint,
    ),
  );
}

/// The primary colour, its contrasting colour and the brightness of a
/// legacy `CupertinoTheme` above [context] (a `package:flutter/cupertino.dart`
/// `CupertinoApp`), or null. [context] rebuilds when it changes.
({Color primary, Color onPrimary, Brightness? brightness})?
    pdfLegacyCupertinoHost(BuildContext context) =>
        kPdfLegacyMaterialBridge ? _cupertinoHost(context) : null;

({Color primary, Color onPrimary, Brightness? brightness})? _cupertinoHost(
    BuildContext context) {
  final inherited = context.dependOnInheritedWidgetOfExactType<
      legacy_cupertino.InheritedCupertinoTheme>();
  if (inherited == null) return null;
  final data = inherited.theme.data.resolveFrom(context);
  return (
    primary: data.primaryColor,
    onPrimary: data.primaryContrastingColor,
    brightness: data.brightness,
  );
}

/// Shows [message] as a SnackBar on the legacy `ScaffoldMessenger` above
/// [context] - a host on a legacy `MaterialApp`/`Scaffold` - and returns
/// true, or returns false when there is none (or the bridge is compiled
/// out). [undoLabel]/[onUndo] add an action; [replaceCurrent] clears the
/// SnackBars showing first.
bool pdfLegacyHostNotice(
  BuildContext context, {
  Key? key,
  required String message,
  required bool floating,
  EdgeInsetsGeometry? margin,
  required Duration duration,
  required bool showClose,
  required bool replaceCurrent,
  String? undoLabel,
  VoidCallback? onUndo,
}) =>
    kPdfLegacyMaterialBridge
        ? _hostNotice(context,
            key: key,
            message: message,
            floating: floating,
            margin: margin,
            duration: duration,
            showClose: showClose,
            replaceCurrent: replaceCurrent,
            undoLabel: undoLabel,
            onUndo: onUndo)
        : false;

bool _hostNotice(
  BuildContext context, {
  required Key? key,
  required String message,
  required bool floating,
  required EdgeInsetsGeometry? margin,
  required Duration duration,
  required bool showClose,
  required bool replaceCurrent,
  required String? undoLabel,
  required VoidCallback? onUndo,
}) {
  final messenger = legacy.ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return false;
  if (replaceCurrent) messenger.clearSnackBars();
  messenger.showSnackBar(legacy.SnackBar(
    key: key,
    content: Text(message),
    behavior: floating ? legacy.SnackBarBehavior.floating : null,
    margin: margin,
    duration: duration,
    showCloseIcon: showClose ? true : null,
    action: onUndo == null || undoLabel == null
        ? null
        : legacy.SnackBarAction(label: undoLabel, onPressed: onUndo),
  ));
  return true;
}
