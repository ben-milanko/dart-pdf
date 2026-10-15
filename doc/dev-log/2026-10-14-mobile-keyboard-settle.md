# Mobile web: blank band after the keyboard closes

Symptom: on iOS (Safari/Brave), after dismissing the on-screen keyboard the
app sometimes stays short and a white band (the page body) shows below the
bottom toolbar until something else resizes the window.

Cause (Flutter 3.47.7 engine, `FullPageDimensionsProvider` +
`EngineFlutterView._handleBrowserResize`): the web engine re-measures only on
a `visualViewport` `resize` event. On iOS the physical size comes from
`documentElement.clientHeight` and the keyboard inset from
`visualViewport.height` while `textEditing.isEditing`. If the final resize of
a dismissal lands mid-animation, or before the field has blurred, the engine
keeps the intermediate physical size / inset and nothing triggers another
measurement. iOS can also leave the document scrolled for the focused input.

Fix (`app/web/index.html`, mobile only - coarse pointer or iOS UA): debounce
viewport `resize`/`scroll`, window `resize`/`orientationchange` and
`focusout`; at 120/360/800 ms after the last one, if no field is focused,
scroll the document back to 0,0 and re-dispatch `resize` on `visualViewport`
so Flutter measures the settled viewport. Self-dispatched events are ignored, so
there is no loop (checked in Chromium with iPhone emulation: one burst -> 3
re-measures, then quiet). Can't be reproduced off-device; verify on an iPhone.

## Hands off while a field is focused

The first cut also re-measured while a field was focused. On the PR preview
the keyboard then stopped opening for a new free-text box (caret plus the
"Paste" bubble, no keyboard). Opening an inline text box depends on a focus
handoff: the keyboard primer (2026-10-09-ios-web-keyboard-primer.md) takes
focus inside the tap, and Flutter's textarea takes it over a frame later.
Re-sent resizes landed across that handoff. The script now does nothing
while an input, textarea or contenteditable is focused. The engine's own
resize events already carry the keyboard inset in that state, and the bug
this fixes only shows once the field has blurred.

## Still reproducing: on-device readout

With the settle script in place the band still showed on an iPhone, so the
cause isn't (only) a missed final resize. To get facts from the device,
`?vpdebug` in the URL (before any `#`) turns on a readout in `index.html`. It
shows `innerHeight`, `documentElement.clientHeight`, the visual viewport
(height, offsetTop, scale), document scroll, the `flutter-view` and canvas
heights, the focused element, and the last 8 viewport/focus events with
timestamps. If the canvas is shorter than `client`, Flutter is holding a
stale size. If `client` itself is short, the browser is misreporting. If
`scroll`/`top` are non-zero, the page was left scrolled.
