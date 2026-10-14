import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'web_safe_area_stub.dart'
    if (dart.library.js_interop) 'web_safe_area_web.dart' as platform_impl;

/// Lets the web app draw under a phone's status bar, notch and home
/// indicator, as the native apps do.
///
/// Flutter web leaves the page's viewport at the safe rectangle and always
/// reports zero padding, so the browser paints the strip above the app
/// itself - from the page background, which is white. Here the page opts into
/// `viewport-fit=cover`, the browser's `env(safe-area-inset-*)` insets are
/// added to [MediaQueryData.padding] (the app bar then pads its controls
/// below the status bar and fills the strip with its own colour), and the
/// page background follows the app bar's colour for any strip the browser
/// still paints. Everywhere but the web this is just [child].
class WebSafeArea extends StatefulWidget {
  const WebSafeArea({
    super.key,
    required this.child,
    this.host = WebSafeAreaHost.platform,
  });

  final Widget child;

  /// The page this runs in; tests stand in a fake.
  final WebSafeAreaHost host;

  @override
  State<WebSafeArea> createState() => _WebSafeAreaState();
}

class _WebSafeAreaState extends State<WebSafeArea> {
  EdgeInsets _insets = EdgeInsets.zero;
  void Function()? _unsubscribe;

  WebSafeAreaHost get _host => widget.host;

  @override
  void initState() {
    super.initState();
    if (!_host.supported) return;
    _host.coverViewport();
    _insets = _host.readInsets();
    _unsubscribe = _host.onInsetsChanged(_refresh);
    // the cover viewport may only take effect once the browser reflows
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    if (!mounted) return;
    final insets = _host.readInsets();
    if (insets != _insets) setState(() => _insets = insets);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_host.supported) return;
    final theme = Theme.of(context);
    _host.setPageBackground(
        theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface);
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_insets == EdgeInsets.zero) return widget.child;
    return MediaQuery(
      data: withSafeAreaInsets(MediaQuery.of(context), _insets),
      child: widget.child,
    );
  }
}

/// The page hooks [WebSafeArea] drives: the browser's on the web, no-ops
/// elsewhere.
class WebSafeAreaHost {
  const WebSafeAreaHost({
    required this.supported,
    required this.coverViewport,
    required this.readInsets,
    required this.onInsetsChanged,
    required this.setPageBackground,
  });

  static const platform = WebSafeAreaHost(
    supported: platform_impl.supported,
    coverViewport: platform_impl.coverViewport,
    readInsets: platform_impl.readInsets,
    onInsetsChanged: platform_impl.onInsetsChanged,
    setPageBackground: platform_impl.setPageBackground,
  );

  /// Whether there is a page to draw under the unsafe area at all.
  final bool supported;

  /// Lets the page extend under the status bar, notch and home indicator.
  final void Function() coverViewport;

  /// The unsafe area's insets, in logical pixels.
  final EdgeInsets Function() readInsets;

  /// Calls the listener when the insets may have changed; returns the
  /// unsubscribe.
  final void Function() Function(void Function() listener) onInsetsChanged;

  /// Paints the page behind the app.
  final void Function(Color color) setPageBackground;
}

/// [data] with the browser's safe-area [insets] added to its view padding.
///
/// [MediaQueryData.padding] is the view padding less what the keyboard
/// already covers, as the engine computes it natively.
@visibleForTesting
MediaQueryData withSafeAreaInsets(MediaQueryData data, EdgeInsets insets) {
  final viewPadding = data.viewPadding + insets;
  final viewInsets = data.viewInsets;
  return data.copyWith(
    viewPadding: viewPadding,
    padding: EdgeInsets.fromLTRB(
      math.max(0, viewPadding.left - viewInsets.left),
      math.max(0, viewPadding.top - viewInsets.top),
      math.max(0, viewPadding.right - viewInsets.right),
      math.max(0, viewPadding.bottom - viewInsets.bottom),
    ),
  );
}
