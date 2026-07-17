# One shared TextBoxAppearance builder (issue #316)

Wrap/baseline/quadding for a clipped text box was implemented three times -
variable-text form fields (`form_editor.dart`), free-text annotations
(`annotation_editor.dart`), and the visible signature box
(`signature_editor.dart`) - each with its own greedy word-wrapper, its own
first-baseline-from-ascent maths (the magic `0.718` / `font.ascent/1000`
recurred in all three), its own quadding alignment, and its own clip. A fix to
one copy silently skipped the other two.

## What landed

New standalone library `lib/src/text_box_appearance.dart` (exported from
`pdf_document.dart`, so it is unit-testable on its own):

- `pdfWrapText(text, maxWidth, measure, {tolerance})` - the one greedy
  word-wrapper. Replaces `_wrapWith` (form), `_wrap` (annotation), and
  `_wrapSignatureLine` (signature). Callers pass a size-bound `measure`
  closure so measurement source (base-14 metrics, `/Widths`, or an embedded
  font) stays theirs. The `tolerance` param carries the annotation
  auto-size rounding slack (`_wrapTolerance`); the others pass 0.
- `writePdfTextBox(...)` - the shared "clip, `BT`, place first baseline from
  the font ascent, align each line by quadding, `Td` deltas, `ET`, optional
  underlines" core. Vertical placement is a `PdfTextBoxVAlign`
  (`top` / `centerBlock` / `centerLine`) so all three anchoring styles are one
  code path. Call sites inject their specifics as hooks: `measureLine`
  (char-spacing / horizontal-scale aware widths), `writeColor` (a raw `/DA`
  fragment, or `rg` + `Tc`/`Tz`), `emitLine` (bidi reorder + glyph encoding for
  embedded/composite fonts), and `underlineColor`.
- `pdfTextBoxLineX` / `PdfTextUnderline` + `pdfDrawUnderlines` - the alignment
  and underline helpers, shared with the rich free-text path too.
- `writePdfCounterRotation(w, cx, cy, rotation)` - the counter-rotation `cm`
  matrix that form (widget space, centre `w/2,h/2`) and annotation (page space,
  rect centre) both emit; they were byte-identical matrices with different
  centres. `_beginWidgetOrientation` and `_orientedCounterRotation` now call it.

## Gotchas / decisions

- **Byte-preserving migration.** The three sites disagreed on incidental
  details, so the builder is parameterised to reproduce each exactly: line-height
  multiplier (`1.15` form / `1.3` signature / `lineSpacing` free-text), padding
  (`2` / `0` / `3`), alignment clamping (form pins overflowing centre/right lines
  to the left pad; the others don't - `clampAlign`), and whether a `TL` is
  emitted (free-text asserts `24 TL`; form/signature don't). The existing
  form/annotation/signature suites are behavioural (they assert shown text,
  clip, orientation, and `Tj` counts, not baseline numbers) and stay green.
- **Form clip inset.** Form clips a rect inset 1 unit from the box, not by the
  text padding, so it emits that clip itself and calls the builder with
  `clip: false`.
- **Form font seam.** The builder consumes a `PdfTextFont`. Embedded `/DR`
  fonts already are one (`PdfEmbeddedFont`); the base-14/`CosDictionary` path
  gets `_DaFieldFont`, a thin adapter reporting the `/DA` resource name + the
  mapped standard-font ascent while delegating measurement to the field's own
  `/Widths`. One behaviour change falls out: embedded-font form fields now place
  the baseline from the real font ascent instead of the hardcoded `0.718`
  (Helvetica is unchanged at 718/1000).
- **Not folded in:** `_wrapRich` (the char-by-char, multi-style rich free-text
  wrapper) is a genuinely different shape and stays put; it does reuse the
  shared `pdfTextBoxLineX` / underline helpers.

New unit tests in `test/text_box_appearance_test.dart` cover the wins the issue
called out: greedy wrap + paragraph/overflow/tolerance, quadding x placement
(incl. clamp), each vertical anchor's baseline, leading, the paint/encode hooks,
underline emission, and the rotation matrices.
