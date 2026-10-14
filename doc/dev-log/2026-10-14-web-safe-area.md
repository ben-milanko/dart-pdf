# Web: no white strip above the app on phones

**Symptom.** On a phone browser the web app sat below a white strip where the
status bar is; the native apps fill that strip with the app bar.

**Cause.** Flutter web's full-page embedding writes its own viewport tag
(`width=device-width, initial-scale=1.0, maximum-scale=5.0`) with no
`viewport-fit=cover`, and the engine always reports zero view padding. The
browser therefore keeps the page out of the unsafe area and paints it from
the page background, which nothing set (white). A phone-sized widget test with
a 47pt status-bar inset confirms the Flutter layout itself is right: the app
bar extends under the inset in its own colour.

**Fix.** `WebSafeArea` (`app/lib/web_safe_area.dart`, web half in
`web_safe_area_web.dart`, a no-op stub elsewhere) wraps the MaterialApp
builder:
- appends `viewport-fit=cover` to the engine's viewport tag;
- reads `env(safe-area-inset-*)` from a hidden padded probe element (re-read on
  resize/orientationchange) and adds it to `MediaQueryData.viewPadding` and
  `.padding` (keyboard-covered bottom inset dropped, as natively), so
  `AppBar`/`SafeArea` pad exactly as on iOS/Android;
- paints `<html>`/`<body>` in the app bar's colour, for any strip the browser
  still paints itself (and what Safari tints its bars from).

Checked in headless Chromium with `Emulation.setSafeAreaInsetsOverride`
(top 47, bottom 34), light and dark. The iOS standalone status-bar meta is
untouched (`black` is not translucent, so its top inset stays 0).
