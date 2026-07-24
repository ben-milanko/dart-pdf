# Tune popup keeps the free-text selection visible

## Symptom

With a run of text selected inside an open free-text editor, opening the tune
popup (the toolbar's Stroke/opacity/font gear, rendered as the font chip for a
selected text box) dropped the selection highlight, and applying an option
(font/size/colour/underline) dropped it again — so the user couldn't see what
they were about to restyle, nor keep restyling the same run.

## Cause

The inline editor is a plain `TextField`, and Flutter's `TextField` hard-gates
its selection highlight on focus:

```dart
// material/text_field.dart
selectionColor: focusNode.hasFocus ? selectionColor : null,
```

Opening the tune popup can blur the field on desktop/web (the popup's controls
take focus on tap), and each control tap blurs it again. The existing
`beginEditingTextFocusHold()` the popup already used keeps the *session* alive
(`_onTextEditFocus` won't commit while held) but never brought focus back, so the
highlight blanked for as long as the popup was open.

## Fix

Keep the field focused for the whole popup session and reclaim focus the instant
a control steals it, so the highlight never blanks:

- `PdfEditingController.shouldKeepEditingTextFocused` — a reference-counted window
  (`beginKeepEditingTextFocused()`/`endKeepEditingTextFocused()`), only live while
  a text editor is open. The tune popup's `_StyleMenu` opens/closes it alongside
  its existing commit-hold.
- `EditingPageOverlay._onTextEditFocus` — while the window is open, a blur
  reclaims focus for the field instead of committing, **unless** the primary
  focus is a real text input (a popup value field the user tapped to type an
  exact number — `_primaryFocusIsEditable`, which checks the focused node's own
  widget so a bare `FocusScopeNode` from a plain unfocus doesn't count).
- The reclaim runs on a **microtask** (`_reclaimEditingTextFocus`), so focus is
  restored before the next paint — no one-frame flash.

Two framework facts make this safe: a top-level `MenuAnchor` doesn't close when
focus leaves its scope (only `SubmenuButton` does), and Material `Slider` doesn't
request focus on pointer drag (`_startInteraction` never calls `requestFocus`),
so dragging the popup's sliders won't blur the field.

This is deliberately kept off the inline style chip's own commit-hold: the chip
must *not* reclaim focus mid-press (a re-focus there collapses the selection
before its button's style applies — see 2026-07-16-text-box-features-fixes.md),
so it uses the plain hold, not the keep-focused window.

## Test

`test/editing_tune_focus_test.dart`: with the window open, repeated simulated
blurs (standing in for control taps) each reclaim focus with the selection range
intact and never commit; the window is inert with no editor open; and opening the
real tune trigger turns the window on, closing it turns it off. The blur/reclaim
isn't reproducible from a synthetic tap alone (the harness doesn't blur the field
on menu-open, same limitation noted for the chip), so the blur is simulated
explicitly.
