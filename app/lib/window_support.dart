// Flutter's desktop windowing API remains experimental in 3.47. Keep every
// internal import and lifecycle assumption quarantined in this file so the
// rest of the app has a small, replaceable surface when Flutter publishes the
// API. Production remains single-window unless the process explicitly opts in
// with DARTPDF_EXPERIMENTAL_WINDOWING=1 and Flutter enables its own windowing
// feature.

// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async' show unawaited;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'window_support_environment.dart';

const Size _defaultWindowSize = Size(1100, 800);
final _windowLifetime = _WindowLifetime();

bool get _desktopPlatform => switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };

/// Whether this process can expose DartPDF's experimental multi-window UI.
///
/// Requiring both flags is deliberate: Flutter's flag makes the internal API
/// available, while DartPDF's process flag selects the matching native runner
/// bootstrap. A normal Store/release launch therefore stays on [runApp] even
/// when a developer has enabled Flutter windowing globally.
bool get multiWindowSupported =>
    dartPdfWindowingRequested &&
    isWindowingEnabled &&
    !kIsWeb &&
    _desktopPlatform;

/// Starts DartPDF with an explicit primary native window when the experimental
/// path is enabled, otherwise uses the unchanged single-window bootstrap.
void runDartPdfApp(Widget root) {
  if (!multiWindowSupported) {
    runApp(root);
    return;
  }

  try {
    final registry = _DartPdfWindowRegistry();
    final closeCoordinator = DartPdfWindowCloseCoordinator();
    late final _DartPdfWindowEntry entry;
    _windowLifetime.opened();
    final controller = RegularWindowController(
      size: _defaultWindowSize,
      title: 'DartPDF',
      delegate: _RegisteredWindowDelegate(
        onUnregister: () => registry.unregister(entry),
        closeCoordinator: closeCoordinator,
        onDestroyed: _windowLifetime.closed,
      ),
    );
    entry = _DartPdfWindowEntry(
      controller: controller,
      builder: (_) => DartPdfWindowCloseScope(
        coordinator: closeCoordinator,
        child: root,
      ),
    );
    registry.register(entry);
    runWidget(_DartPdfWindowHost(registry: registry));
  } on UnsupportedError {
    _windowLifetime.abandonOpen();
    // A platform may compile the experimental framework API without providing
    // a backing window implementation. Keep DartPDF usable in that case.
    runApp(root);
  }
}

/// Opens a new top-level window and returns whether it was registered.
///
/// Returning a result matters for tab handoff: the source tab is removed only
/// after the destination window exists, so a platform failure cannot lose an
/// unsaved document.
bool openRegularWindow(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  Size size = _defaultWindowSize,
}) {
  if (!multiWindowSupported) return false;
  final registry = _DartPdfWindowRegistryScope.maybeOf(context);
  if (registry == null) return false;

  try {
    late final _DartPdfWindowEntry entry;
    final closeCoordinator = DartPdfWindowCloseCoordinator();
    _windowLifetime.opened();
    final delegate = _RegisteredWindowDelegate(
      onUnregister: () => registry.unregister(entry),
      closeCoordinator: closeCoordinator,
      onDestroyed: _windowLifetime.closed,
    );
    final controller = RegularWindowController(
      size: size,
      title: title,
      delegate: delegate,
    );
    entry = _DartPdfWindowEntry(
      controller: controller,
      builder: (context) => DartPdfWindowCloseScope(
        coordinator: closeCoordinator,
        child: builder(context),
      ),
    );
    registry.register(entry);
    return true;
  } on UnsupportedError {
    _windowLifetime.abandonOpen();
    return false;
  }
}

/// Keeps the window registry outside every native view.
///
/// Flutter's stock [WindowManager] is designed to sit inside an existing view.
/// DartPDF's engine-owned runner deliberately has no implicit view, and putting
/// the manager inside the primary window would make every secondary window a
/// descendant of that primary view. This root host lets the primary close while
/// a secondary remains alive and treats every regular window as an equal view.
class _DartPdfWindowHost extends StatelessWidget {
  const _DartPdfWindowHost({required this.registry});

  final _DartPdfWindowRegistry registry;

  @override
  Widget build(BuildContext context) {
    return _DartPdfWindowRegistryScope(
      registry: registry,
      child: ListenableBuilder(
        listenable: registry,
        builder: (context, _) => ViewCollection(
          views: [
            for (final entry in registry.entries)
              RegularWindow(
                key: ObjectKey(entry.controller),
                controller: entry.controller,
                child: entry.builder(context),
              ),
          ],
        ),
      ),
    );
  }
}

class _DartPdfWindowRegistry extends ChangeNotifier {
  final List<_DartPdfWindowEntry> _entries = [];

  List<_DartPdfWindowEntry> get entries => List.unmodifiable(_entries);

  void register(_DartPdfWindowEntry entry) {
    _entries.add(entry);
    notifyListeners();
  }

  void unregister(_DartPdfWindowEntry entry) {
    if (_entries.remove(entry)) notifyListeners();
  }
}

class _DartPdfWindowEntry {
  const _DartPdfWindowEntry({
    required this.controller,
    required this.builder,
  });

  final RegularWindowController controller;
  final WidgetBuilder builder;
}

class _DartPdfWindowRegistryScope extends InheritedWidget {
  const _DartPdfWindowRegistryScope({
    required this.registry,
    required super.child,
  });

  final _DartPdfWindowRegistry registry;

  static _DartPdfWindowRegistry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_DartPdfWindowRegistryScope>()
      ?.registry;

  @override
  bool updateShouldNotify(_DartPdfWindowRegistryScope oldWidget) =>
      !identical(registry, oldWidget.registry);
}

/// Per-window close handshake used by [EditorScreen] without exposing
/// Flutter's internal controller classes outside this file.
class DartPdfWindowCloseCoordinator {
  Object? _owner;
  Future<bool> Function()? _handler;

  void register(Object owner, Future<bool> Function() handler) {
    _owner = owner;
    _handler = handler;
  }

  void unregister(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _handler = null;
  }

  Future<bool> requestClose() => _handler?.call() ?? Future<bool>.value(true);
}

class DartPdfWindowCloseScope extends InheritedWidget {
  const DartPdfWindowCloseScope({
    super.key,
    required this.coordinator,
    required super.child,
  });

  final DartPdfWindowCloseCoordinator coordinator;

  static DartPdfWindowCloseCoordinator? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DartPdfWindowCloseScope>()
      ?.coordinator;

  @override
  bool updateShouldNotify(DartPdfWindowCloseScope oldWidget) =>
      !identical(coordinator, oldWidget.coordinator);
}

/// Removes a secondary window from the registry exactly once as it closes.
///
/// The close-request path unregisters before destroying the controller, as the
/// 3.47 API contract requests. [onWindowDestroyed] is a fallback for a window
/// the platform destroys without first issuing a close request.
class _RegisteredWindowDelegate with RegularWindowControllerDelegate {
  _RegisteredWindowDelegate({
    this.onUnregister,
    required this.closeCoordinator,
    required this.onDestroyed,
  });

  final VoidCallback? onUnregister;
  final DartPdfWindowCloseCoordinator closeCoordinator;
  final VoidCallback onDestroyed;
  bool _unregistered = false;
  bool _closePending = false;
  bool _destroyed = false;

  void _unregister() {
    if (_unregistered) return;
    _unregistered = true;
    onUnregister?.call();
  }

  @override
  void onWindowCloseRequested(RegularWindowController controller) async {
    if (_closePending || _destroyed) return;
    _closePending = true;
    final allowed = await closeCoordinator.requestClose();
    _closePending = false;
    if (!allowed || _destroyed) return;
    _unregister();
    controller.destroy();
  }

  @override
  void onWindowDestroyed() {
    if (_destroyed) return;
    _destroyed = true;
    _unregister();
    onDestroyed();
    super.onWindowDestroyed();
  }
}

class _WindowLifetime {
  int _count = 0;

  void opened() => _count++;

  void abandonOpen() {
    if (_count > 0) _count--;
  }

  void closed() {
    if (_count > 0) _count--;
    if (_count == 0) {
      // The headless runners have no template view/window to end their event
      // loop. System.exitApplication is implemented by all three desktop
      // embedders (unlike SystemNavigator.pop on Windows) and gives each engine
      // a clean required-exit path after every window has confirmed closure.
      unawaited(
        ServicesBinding.instance.exitApplication(ui.AppExitType.required),
      );
    }
  }
}
