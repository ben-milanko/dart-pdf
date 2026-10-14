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
`focusout`; at 120/360/800 ms after the last one, scroll the document back to
0,0 when no field is focused and re-dispatch `resize` on `visualViewport` so
Flutter measures the settled viewport. Self-dispatched events are ignored, so
there is no loop (checked in Chromium with iPhone emulation: one burst -> 3
re-measures, then quiet). Can't be reproduced off-device; verify on an iPhone.
