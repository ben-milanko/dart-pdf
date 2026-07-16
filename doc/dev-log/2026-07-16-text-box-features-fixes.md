# 2026-07-16 — Free-text box: styling features and editing fixes

Branch `claude/text-box-features-fixes-3ad025`. A batch of free-text
(FreeText annotation) reports from using the editor: four bugs and four
new box styling controls. They share plumbing, so they landed together.

## The appearance layer (pdf_document)

`PdfFreeTextRun` grew a per-run `underline`. `_freeTextContent` and
`_freeTextRichContent` (annotation_editor.dart) now take box-level
`lineSpacing` (a leading multiplier), `charSpacing` (Tc, points) and
`horizontalScale` (Tz, per cent), plus underline (per-box for the flat
path, per-run for rich). New `ContentWriter.charSpacing`/`horizontalScale`
emit `Tc`/`Tz`.

Key detail: **advance width has to account for Tc and Tz** or wrapping and
right/centre alignment drift. `_advanceWidth(font, text, size, charSpacing,
horizontalScale)` returns `(natural + Tc*count) * hScale/100` and every
wrap/align site goes through it (`_wrap`, `_wrapRich`, the per-line width).
Td translations are *not* scaled by Tz (only the glyph-drawing matrix is),
so the line-x math stays in unscaled text space and the advance already
carries the Tz factor — consistent.

Underline is a **filled rectangle drawn after `ET`** (path artwork can't sit
inside a text object), collected during the line loop into `_UnderlineRun`s
and flushed by `_drawUnderlines`, still inside the box clip.

Persistence: these four have no standard PDF representation, so they ride
vendor dictionary keys (`kPdfFreeText*Key` in annotation.dart —
`LineSpacing`/`CharSpacing`/`HScale`/`TextUnderline`), written only when
non-default (a plain box's dict is unchanged) and read back by
`freeTextStyle`. Rich underline additionally rides `/RC`'s
`text-decoration:underline` span style so per-run underline round-trips.

## Bug 1 — backspace ate bold from the line below

The inline editor's `_RichTextEditingController._ranges` were absolute
UTF-16 offsets that never moved when text changed, so after a backspace a
bold run kept its old numbers and appeared to slide one char per keystroke.
Fix: override `set value`, diff old→new by common prefix/suffix, and remap
every range (`_shiftRanges`). `seedRuns` sets `_remapRanges=false` while it
assigns text+ranges together (they're already correct). Text inserted
*inside* a run extends it; text in a replaced span collapses to the span
start.

## Bug 2 — resize stretched embedded-font (and rich) boxes

`_resizeBehavior` only allowed `reflowText` when `standardTextFont != null`,
so any box switched to a bundled/custom font fell to the §12.5.5 stretch.
Added a cheap COS probe `hasEmbeddedTextFont` (Type0 + FontFile in the AP
resources — no font-program parse) to the gate, and the regenerator now
recovers the real face with `PdfEmbeddedFont.fromFreeText` and re-wraps in
it. It also **preserves rich runs on resize** (`preserveRich`, true for
resize, false for a colour restyle which still flattens) by regenerating
through `_freeTextRichContent`.

The live drag preview (`_textResizeStyle` → `_wrappedTextBox`) can only draw
base-14 faces, so embedded boxes fall back to the stretch ghost *during the
drag* — the commit still re-wraps correctly.

## Bug 5 — alignment "reset to left" after a resize

The committed appearance always kept `/Q` (the regenerator reads it), but
the resize preview and post-commit afterimage (`_wrappedTextBox`, used for
both) were hard-coded `TextAlign.start` / `topStart`, so a centred/right box
visibly snapped left during the drag and only settled back once the raster
caught up. Threaded the box alignment (and underline + line spacing) through
`_textResizeStyle`, the `_afterText` record and `_wrappedTextBox`.
`_textEditAlign` is nullable — null means "follow the text direction", which
maps to `TextAlign.start` so RTL boxes still hug the right edge.

## Bug 4 — font picker stuck on "Sans" after a font change

The chip read `selectedTextStyle.font`, which only parses a base-14 face
from `/DA`, so an embedded box read back Helvetica → "Sans". New
`selectedTextFont` returns `_freeTextFontOf().font` (the recovered embedded
face, else the standard one); the tune popup and properties panel use it.

## Bug 8 — line spacing wrong in the popup until it closed

The inline `TextField` took its line height from each run's own font, so
changing a run's family nudged the lines until the font-independent PDF
leading re-laid on commit. Pinned the preview with a `StrutStyle`
(`forceStrutHeight: true`, size = the box's max run size, height =
`lineSpacing`), matching the committed leading. The base style also carries
`height`/`letterSpacing` now, and `buildTextSpan` threads
`previewLineHeight`/`previewLetterSpacing` into each run.

## New controls (features 3/6/7)

Box-level line spacing, character spacing and font width sliders plus an
underline toggle live in the tune popup and the properties panel. They set
creation defaults (`controller.lineSpacing/charSpacing/fontWidth/
textUnderline`, session-only — the font program-adjacent spacing isn't worth
persisting) and, on a selected box, `setSelectedTextBoxStyle` regenerates it
(preserving rich runs; whole-box underline maps onto every run). It **skips
the rewrite while the inline editor is open** (would swap the document under
the editor) — the change rides the creation defaults and lands at commit;
`_onControllerChanged` mirrors the defaults into the live preview for a
new box.

Underline is a per-character format like bold: the inline style chip's
underline button and Cmd/Ctrl+U toggle it on the selection (or the whole box
when nothing is selected), so an underlined box commits as rich `/RC`.

## Follow-up — the chip deselected the box on mobile

A tap on the inline style chip (underline, size, …) on touch devices blurred
the `TextField`, and `_onTextEditFocus` treats any focus loss as a commit —
so the box committed and deselected out from under the tap. Desktop was fine
because the chip's `Focus(canRequestFocus:false, descendantsAreFocusable:
false)` keeps the field focused; a mobile tap drops it anyway.

Fix: wrap the chip in a `Listener` that begins the controller's
`beginEditingTextFocusHold()` on pointer-down (the same hold the tune popup
already uses, which `_onTextEditFocus` honours) and releases it on pointer-up.
The release is deferred to a post-frame callback — pointer-up fires *before*
the button's `onPressed`, so re-focusing synchronously there collapsed the
selection before the style could apply. It's also cleared in `dispose` so the
hold counter can't leak.

Note this is not reproducible in `flutter_test`: a synthetic tap never blurs a
non-focusable button, so the harness can't exercise the focus drop. The chip
underline button's *action* is tested by invoking its handler directly (the
scaled/translated chrome also makes a synthetic tap's hit-test unreliable).

## Left open

- Horizontal scaling (Tz) has no Flutter `TextField` equivalent, so it isn't
  previewed live in the inline editor — it shows once the raster lands.
- Mixed per-*line* font sizes over-space slightly in the strut-pinned
  preview (single strut height); the committed rich appearance is exact.
- Embedded-font resize previews use the stretch ghost during the drag (only
  the commit re-wraps); a real embedded preview would need the registered
  synthetic family the inline editor already loads.
