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
// **You cannot try this on the stable channel** - the repo's pinned SDK
// (`.fvmrc`) is stable, so on a normal checkout the affordances are hidden by
// design, not broken. `windowingFeature` in flutter_tools declares
// `master: FeatureChannelSetting(available: true)` and nothing for beta/stable
// (unspecified channels default to `available: false`), and `isEnabled` returns
// early on availability *before* reading any setting. So all three routes are
// dead ends on stable:
//
//   * `flutter config --enable-windowing` - writes the value, never takes effect
//   * `--dart-define=FLUTTER_ENABLED_FEATURE_FLAGS=windowing` - the tool
//     rejects this outright ("used by the framework and cannot be set using
//     --dart-define")
//   * the `FLUTTER_WINDOWING` env override - same availability gate
//
// Trying it therefore needs a master-channel SDK (e.g. `fvm install master`,
// then run with that SDK directly so `.fvmrc` stays pinned). Two things block
// it there as of 2026-07-25, both verified:
//
//   1. This file does not compile against master. The API was renamed/reshaped
//      after it was written: `RegularWindowController(preferredSize:)` ->
//      `WindowController(size:)`, `RegularWindow` -> `Window`,
//      `RegularWindowControllerDelegate` -> `WindowControllerDelegate`, and
//      `WindowManager({child})` -> `WindowManager({initialWindows})` (the
//      manager now renders each registered entry itself, so the primary window
//      becomes the first `WindowEntry`). The stable and master shapes are
//      mutually exclusive - porting breaks the build on stable, and therefore CI.
//   2. Even ported, it crashes at launch on macOS:
//      "Multiview can only be enabled before adding any view controllers."
//      `WindowController(...)` asks the engine to enable multiview, but
//      `macos/Runner/MainFlutterWindow.swift` has already created a
//      `FlutterViewController` from the NIB. Making this run needs the macOS
//      embedding reworked to own a `FlutterEngine` directly and rehost every
//      method channel + `RegisterGeneratedPlugins` on it. That native work is
//      NOT part of this feature, so multi-window has never actually run - the
//      tests cover only the Dart-side wiring.
//
// The API is documented as unstable ("Flutter will make breaking changes to
// this API, even in patch versions") - it broke within 8 days of this file
// being written - which is why this stays behind the flag and is not wired
// into any released build. Revisit when windowing reaches beta/stable. See
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
