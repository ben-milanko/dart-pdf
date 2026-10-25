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

## The keyboard primer never ran inside the tap

The `?vpdebug` log from an iPhone (Brave) showed no `focusin input` at all
when a text box opened: focus went `flutter-view` -> `textarea`, so the
keyboard never came up and `vv` stayed full height. Reproduced in Chromium
with iPhone emulation (`navigator.platform` spoofed so Flutter picks iOS) and
a `focus()` hook. That run found two separate faults in the #1061 primer:

1. **Too late.** The primer's `focus()` ran ~290 ms after `touchend`. The
   free-text tap goes through `onTapUp`, which the viewer's double-tap zoom
   holds in the arena for `kDoubleTapTimeout`, so `_openTextEditor` runs from
   a timer, not from the touch. WebKit then doesn't treat the focus as part
   of the gesture. Fix: `_liftOpensTextEditor` primes from the overlay's raw
   `Listener.onPointerUp`, which runs inside the DOM `pointerup`. It covers
   the free-text/callout tools and a select-mode tap on the selected free
   text. The late call in `_openTextEditor` stays for paths that already run
   inside the gesture (the chip's Edit button) and is harmless otherwise.
2. **Focus stolen in between.** The primer was appended to `<body>`. When
   the framework focused the editor's node, `ViewFocusBinding.changeViewFocus`
   saw nothing inside the view holding focus and focused the `flutter-view`
   element, so focus went input -> div -> textarea, which closes the
   keyboard. The primer now lives inside `flutter-view`, so the engine leaves
   DOM focus alone and the textarea takes it straight from the primer.

After the fix the emulated run logs `focus() INPUT in:pointerup
parent:FLUTTER-VIEW`, then `focus() TEXTAREA`, with no view-element focus in
between, and typing lands in the box. The test now asserts the primer runs on
the lift of a plain tap, before the editor exists.

## Focus in `touchend`, not `pointerup`

The next device log (Brave, iPhone) showed the primer taking focus at the tap
(`focusin input`, then `focusin textarea` 40 ms later), but `vv` stayed full
height: the keyboard never opened, even for the primer. A `focus()` made in
`pointerup` takes focus, but WebKit didn't raise the keyboard for it. The
event it reliably treats as the user's gesture is `touchend`, which arrives
~15 ms after `pointerup`. `pdfPrimeSoftKeyboard(atTouchEnd: true)` (passed for
any non-mouse lift) prepares the primer in `pointerup` and focuses it from a
one-shot capture `touchend` listener, with a 250 ms fallback. A plain call
that arrives while that listener is pending (the drag path opens the editor
inside the same `pointerup`) defers to it, because a second `focus()` on an
already-focused input is a no-op and would waste the gesture. Emulated run:
`focus() INPUT in:touchend`. The `?vpdebug` log now also records `pointerup`
and `touchend`, and keeps 12 lines.
