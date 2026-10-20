# iOS web: no keyboard when a text box opens

Reported from Brave on iPhone: drawing or tapping a free-text box opened the
inline editor with a caret, but no keyboard came up. The page was laid out
for one (a blank band where it should have been). Tapping the caret only
showed the "Paste" bubble.

## Why

WebKit only raises the soft keyboard for a `focus()` made while a user
gesture is being handled. Every iOS browser is WebKit. `_openTextEditor`
builds the field with `setState` and focuses it in a post-frame callback,
because the gesture's pointer-down put primary focus on the viewer's own node
and `autofocus` won't fire into a focused scope. By then the tap has been
handled. The engine's `focus()` on its textarea is outside the gesture, so
iOS gives the field a caret and no keyboard.

## Fix

`pdfPrimeSoftKeyboard()` (`soft_keyboard_primer.dart`, with a web
implementation and a no-op stub for native and VM) focuses a hidden 1px
`<input>` synchronously. `_openTextEditor` calls it first thing on iOS. Every
user path into `_openTextEditor` (the tap/pan-end handlers, the selection
chip's Edit button) runs inside the pointer event's dispatch, so that focus
counts as a gesture and the keyboard comes up. When Flutter's textarea
focuses a frame later, iOS moves the focus across and keeps the keyboard up.
The primer removes itself on blur. If nothing takes focus within 1s (an
editor that never opened), it blurs itself so a stray keyboard goes away.

Notes on the primer input:
- `position: fixed` at 0,0 and `preventScroll` keep focusing it from
  scrolling the page.
- `font-size: 16px` keeps iOS from zooming in on focus.
- `pointer-events: none`, `aria-hidden` and `tabIndex = -1` keep it out of
  hit testing, accessibility and tab order.

Test seam: `debugPdfPrimeSoftKeyboard` in editing_overlay.dart. The test
`opening a text box primes the iOS keyboard inside the tap` checks it runs
once, before the field exists, on iOS, and not on Android.

Not verified on a device from the session. The PR preview build is the place
to try it.
