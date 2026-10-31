# iOS web: stop the whole page rubber-banding

Reported from a screen recording on iPhone (web build): scrolling to the last
page and pushing further slid the *entire app* (header, page bar and bottom
toolbar) up under the status bar, then sprang it back. The viewer's own
bottom bounce (platform `BouncingScrollPhysics`, `physics: null` in
`pdf_viewer.dart`) was happening too, but that part is the normal iOS feel.

## Cause

The browser document was scrolling, not Flutter. Flutter's
`FullPageEmbeddingStrategy` makes `<body>` `position: fixed; overflow:
hidden; touch-action: none`, but iOS Safari still rubber-bands the root
scroller when a drag isn't consumed - here, a drag past the end of the list.

## Fix

`app/web/index.html`:

- `html, body { height: 100%; overflow: hidden; overscroll-behavior: none; }`
- a document-level non-passive `touchmove` listener that calls
  `preventDefault()`. Flutter reads pointer events, and a cancelled
  `touchmove` doesn't suppress `pointermove` (checked in Chromium with CDP
  touch emulation: pointer moves keep arriving, `scrollY` stays 0). The only
  platform view (`web_page_surface_web.dart`) is a drawing surface with no
  native scrolling of its own, so nothing needs the browser's panning.
  `touchstart` is left alone so taps still focus the hidden text-input
  element and bring up the keyboard.

Needs a real iPhone to confirm; Chromium has no root rubber-band to
reproduce it.
