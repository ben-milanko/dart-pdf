import 'package:flutter/material.dart';

/// Shows a Material dialog inside the current Flutter view.
///
/// Flutter's experimental desktop windowing feature promotes [showDialog]
/// calls to native dialog windows. Those windows are not yet reliable enough
/// for editor workflows: on macOS they can be registered as an off-screen
/// sheet that blocks its parent without accepting input. DartPDF still uses
/// native [RegularWindow]s for real multi-window editing, while its modal
/// prompts stay attached to the navigator that opened them.
Future<T?> showPdfDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  bool? requestFocus,
  AnimationStyle? animationStyle,
}) {
  assert(debugCheckHasMaterialLocalizations(context));

  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final themes = InheritedTheme.capture(
    from: context,
    to: navigator.context,
  );

  return navigator.push<T>(
    DialogRoute<T>(
      context: context,
      builder: builder,
      barrierColor: barrierColor ??
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      settings: routeSettings,
      themes: themes,
      anchorPoint: anchorPoint,
      traversalEdgeBehavior:
          traversalEdgeBehavior ?? TraversalEdgeBehavior.closedLoop,
      requestFocus: requestFocus,
      animationStyle: animationStyle,
      fullscreenDialog: fullscreenDialog,
    ),
  );
}
