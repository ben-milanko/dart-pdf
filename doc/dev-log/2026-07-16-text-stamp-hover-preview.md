# Text stamp: hover preview shows a 'TEXT' placeholder

The stamp tool already painted a live hover preview for an **active custom
stamp** (`_activeStampAfterimageAt` → `stampPreview`), so you could see the
auto-sized box a click would drop before committing. But the plain
**text-stamp fallback** — the mode with no active custom stamp, where a click
prompts for the caption — showed nothing on hover: `_onHover` returned `null`
when `activeStamp == null`, so the click target was invisible.

Fix (`editing_overlay.dart`): a small `_stampHoverAfterimageAt(position)`
helper that returns the active-stamp afterimage when one is selected, and
otherwise previews the text-stamp fallback via the existing
`_textStampAfterimageAt` with a `'TEXT'` placeholder caption
(`_textStampPreviewLabel`) in the toolbar `color`. Both `_onHover` and the
`_EditingPreviewPainter.stampPreview` wiring now call the helper instead of
`_activeStampAfterimageAt` directly.

The placeholder is preview-only: a click still opens the text prompt and
commits the entered caption (`placeTextStamp`), sized to the real text. The
preview box is sized for `'TEXT'`, so the ghost is an approximate footprint,
not the final width — good enough to show where the stamp lands.

Test: `editing_stamps_test.dart` gains "stamp hover previews a TEXT
placeholder without an active stamp" alongside the existing active-stamp
hover test — hover paints a `stampPreview` with `text == 'TEXT'` centered on
the pointer, nothing is committed, and moving off-page clears it.
