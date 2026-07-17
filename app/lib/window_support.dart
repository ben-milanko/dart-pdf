// Multi-window support built on Flutter's *experimental* desktop windowing
// API. Everything that reaches into the unstable, `@internal` windowing surface
// is quarantined in this one file so the rest of the app never imports it
// directly and stays trivially testable.
//
// The windowing feature is off unless the build enables it, so every entry
// point here degrades gracefully:
//
//   * [multiWindowSupported] is `false` (no "New window" affordance appears),
//   * [runDartPdfApp] falls back to the classic single-window `runApp`, and
//   * [openRegularWindow] is a no-op.
//
// To try it, build/run with the windowing feature flag on:
//
//   fvm flutter config --enable-windowing        # once, persists in config
//   fvm flutter run -d macos                      # (or windows / linux)
//
// or pass it inline for a single run:
//
//   fvm flutter run -d macos \
//     --dart-define=FLUTTER_ENABLED_FEATURE_FLAGS=windowing
//
// The API is documented as unstable ("Flutter will make breaking changes to
// this API, even in patch versions"), which is why this stays behind the flag
// and is not wired into any released build. See
// https://github.com/flutter/flutter/issues/30701.

// The windowing API is @internal and lives under src/; importing it trips two
// lints that are expected here and nowhere else in the app.
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: implementation_imports

import 'package:flutter/widgets.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';

/// Whether the running build has Flutter's experimental windowing feature
/// enabled. When `false`, the app behaves exactly as it always has (one
/// window, `runApp`) and no multi-window UI is offered.
///
/// Reading the flag never throws; the guarded windowing calls below only run
/// when this is `true`.
bool get multiWindowSupported => isWindowingEnabled;

/// The initial size of a brand-new DartPDF window.
const Size _defaultWindowSize = Size(1100, 800);

/// Bootstraps the app. With windowing enabled we own the view tree explicitly
/// via [runWidget]: a [WindowManager] hosts the primary [RegularWindow] plus
/// any secondary windows registered later. Without it we use the ordinary
/// [runApp] path against the engine's implicit view.
///
/// [root] is the app's top-level widget (the same one either way), so the
/// widget tree below the window is identical in both modes.
void runDartPdfApp(Widget root) {
  if (isWindowingEnabled) {
    try {
      final controller = RegularWindowController(
        preferredSize: _defaultWindowSize,
        title: 'DartPDF',
      );
      // WindowManager provides the WindowRegistry and renders secondary windows
      // as sibling sub-views of the primary RegularWindow.
      runWidget(
        WindowManager(
          child: RegularWindow(controller: controller, child: root),
        ),
      );
      return;
    } on UnsupportedError {
      // The flag is on but the platform can't back it (e.g. mobile). Fall
      // through to the single-window path rather than failing to launch.
    }
  }
  runApp(root);
}

/// Opens [builder]'s content in a new top-level OS window and returns without
/// waiting. A no-op when windowing is unavailable, when [context] isn't hosted
/// under a [WindowManager], or when the platform rejects the request.
///
/// The window destroys itself when the user closes it, unregistering from the
/// shared [WindowRegistry] so its sub-view is torn down.
void openRegularWindow(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  Size preferredSize = _defaultWindowSize,
}) {
  if (!isWindowingEnabled) return;
  final registry = WindowRegistry.maybeOf(context);
  if (registry == null) {
    assert(false, 'openRegularWindow called outside a WindowManager');
    return;
  }
  try {
    late final WindowEntry entry;
    final controller = RegularWindowController(
      preferredSize: preferredSize,
      title: title,
      delegate: _UnregisterOnDestroy(() => registry.unregister(entry)),
    );
    entry = WindowEntry(controller: controller, builder: builder);
    registry.register(entry);
  } on UnsupportedError {
    // Platform declined to create the window; leave the app untouched.
  }
}

/// Drops the window's registry entry once the platform reports it destroyed,
/// so [WindowManager] stops rendering (and stops holding) the closed window.
class _UnregisterOnDestroy with RegularWindowControllerDelegate {
  _UnregisterOnDestroy(this.onDestroyed);

  final VoidCallback onDestroyed;

  @override
  void onWindowDestroyed() {
    onDestroyed();
    super.onWindowDestroyed();
  }
}
