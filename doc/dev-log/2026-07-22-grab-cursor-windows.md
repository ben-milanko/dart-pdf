# 2026-07-22 - Grab cursor invisible on Windows

## Symptom

On Windows the "drag here to pan" affordance was invisible: hovering the
document (or an off-page area) showed a plain arrow instead of the open-hand
grab cursor, and starting a grab-pan didn't switch to the closed-hand grabbing
cursor either. macOS, Linux, and the web all showed it correctly.

## Cause

Flutter's Windows embedder maps `MouseCursor`s to Win32 `IDC_*` handles, and
there is no native handle for the open-/closed-hand grab cursors. Any
`SystemMouseCursors.grab` / `grabbing` therefore falls back to the default
`IDC_ARROW`, so nothing on the page hinted that a drag would pan. The other
targets render grab natively - macOS (open/closed hand), GTK/Linux, and CSS
`grab`/`grabbing` on the web - which is why the bug was Windows-only.

## Fix

Added `lib/src/platform_cursors.dart` with `grabCursor` / `grabbingCursor`
getters. They return the real `SystemMouseCursors.grab` / `grabbing` everywhere
except Windows, where they substitute `SystemMouseCursors.move` (the four-way
`IDC_SIZEALL` arrows) - a supported cursor that reads as "drag to pan". Web is
excluded from the substitution via `kIsWeb` since the browser renders grab
natively regardless of the reported platform.

Routed every grab-cursor site through the helper:

- `pdf_viewer.dart` - the hover cursor over a pannable page / off-page area
  (`_onHover`), the grabbing cursor while a mouse grab-pan is in progress, and
  the grab cursor restored when the drag ends.
- `editing_overlay.dart` - the grab cursor shown over a polygon vertex handle
  in select mode.

Existing widget tests assert `SystemMouseCursors.grab` under the default test
platform (Android), so they keep passing unchanged. New coverage in
`test/platform_cursors_test.dart` pins the Windows substitution and the native
cursor on every other platform.
