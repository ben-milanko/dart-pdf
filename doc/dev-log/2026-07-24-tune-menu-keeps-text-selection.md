# Tune popup keeps the free-text selection visible

## Symptom

With a run of text selected inside an open free-text editor, opening the tune
popup (the toolbar's Stroke/opacity/font gear, rendered as the font chip for a
selected text box) dropped the selection highlight. The controls still applied
to the selected run, but the user could no longer *see* what they were about to
restyle.

## Cause

The inline editor is a plain `TextField`; Flutter only paints its selection
highlight while the field holds focus. Opening the tune popup can blur the field
on desktop/web (tapping a non-text widget / the menu overlay taking over). The
existing `beginEditingTextFocusHold()` the popup already used keeps the *session*
alive — `_onTextEditFocus` won't commit while the hold is up — but it never
brought focus back, so the highlight vanished for as long as the popup was open.

The overlay already re-focuses the field when that hold is *released*
(`editingTextFocusHoldRevision`, `_onControllerChanged`), which is what keeps the
box in edit mode after the popup closes. It just did nothing on open.

## Fix

A dedicated one-shot signal rather than overloading the commit-hold, so the
inline style chip's own hold (which must *not* re-focus mid-press — a synchronous
re-focus there collapses the selection before the button's style applies, see
2026-07-16-text-box-features-fixes.md) is untouched:

- `PdfEditingController.refocusEditingText()` bumps `refocusEditingTextRevision`
  (no-op when no editor is open).
- `_StyleMenu.toggle()` calls it right after `menu.open()`.
- `EditingPageOverlay._onControllerChanged` watches the revision and, if the
  editor is open and unfocused, reclaims focus in a post-frame callback — the
  same shape as the release path.

A top-level `MenuAnchor` doesn't close when focus leaves its scope (only
`SubmenuButton` does that), so re-focusing the field keeps the popup open. And
Material `Slider` doesn't request focus on pointer drag (`_startInteraction`
never calls `requestFocus`), so dragging the popup's sliders won't re-blur the
field; only tapping a numeric readout deliberately moves focus, as expected.

## Test

`test/editing_tune_focus_test.dart`: with the hold up, a simulated blur keeps the
editor open; `refocusEditingText()` then restores focus with the selection range
intact; and tapping the real tune trigger bumps the revision while the popup
opens. The focus-reclaim is not reproducible from a synthetic tap alone (the test
harness doesn't blur the field on menu-open, the same limitation noted for the
chip), so the blur is simulated explicitly.
