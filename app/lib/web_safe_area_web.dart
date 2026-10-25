import 'dart:js_interop';

import 'package:flutter/painting.dart';
import 'package:web/web.dart' as web;

const supported = true;

/// Adds `viewport-fit=cover` to the viewport tag the Flutter engine writes,
/// so the page extends under the status bar and reports its insets.
void coverViewport() {
  final meta = web.document.querySelector('meta[name="viewport"]')
      as web.HTMLMetaElement?;
  if (meta == null) {
    web.document.head?.append(web.HTMLMetaElement()
      ..name = 'viewport'
      ..content = 'width=device-width, initial-scale=1.0, viewport-fit=cover');
    return;
  }
  if (meta.content.contains('viewport-fit')) return;
  meta.content = '${meta.content}, viewport-fit=cover';
}

web.HTMLElement? _probe;

/// The browser's `env(safe-area-inset-*)`, in CSS pixels (Flutter's logical
/// pixels on the web), read through an invisible element padded by them.
EdgeInsets readInsets() {
  final probe = _probe ??= (web.HTMLDivElement()
    ..style.cssText = 'position:fixed;top:0;left:0;width:0;height:0;'
        'visibility:hidden;pointer-events:none;'
        'padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) '
        'env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)');
  if (!probe.isConnected) web.document.documentElement?.append(probe);
  final style = web.window.getComputedStyle(probe);
  double px(String value) => double.tryParse(value.replaceAll('px', '')) ?? 0;
  return EdgeInsets.fromLTRB(
    px(style.paddingLeft),
    px(style.paddingTop),
    px(style.paddingRight),
    px(style.paddingBottom),
  );
}

/// Calls [listener] when the insets may have changed (rotation, resize);
/// returns the unsubscribe.
void Function() onInsetsChanged(void Function() listener) {
  final callback = ((web.Event _) => listener()).toJS;
  web.window.addEventListener('resize', callback);
  web.window.addEventListener('orientationchange', callback);
  return () {
    web.window.removeEventListener('resize', callback);
    web.window.removeEventListener('orientationchange', callback);
  };
}

/// Paints the page behind the app in [color]: what a browser shows in any
/// strip outside the app, and what Safari tints its bars from.
void setPageBackground(Color color) {
  final css = 'rgb(${(color.r * 255).round()}, ${(color.g * 255).round()}, '
      '${(color.b * 255).round()})';
  (web.document.documentElement as web.HTMLElement?)?.style.backgroundColor =
      css;
  web.document.body?.style.backgroundColor = css;
}
