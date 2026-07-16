# Rich-text styling for content text edits (#206)

Issue #206 asked for editing already-drawn page text *with formatting* -
apply colour, size, bold, italic while correcting the words. Content
editing until now (`PdfEditor.replaceText`) only re-typed a run in its own
existing appearance. This session adds a uniform style override to the
replacement.

## Core (`pdf_document`)

- New `PdfTextStyle` value class (`content_editor.dart`): nullable
  `color` (0xRRGGBB fill), `fontSize`, `family` (sans/serif/mono), `bold`,
  `italic`. A null field keeps the run's existing value, so
  `PdfTextStyle(color: …)` recolours without touching the face/size.
  `isEmpty` is the "plain replacement" sentinel.
- `family`/`bold`/`italic` all drive `_styledVariant`, which substitutes a
  base-14 face (`PdfStandardFont.styled`): `family` picks the family
  outright (else the run's own, else sans), bold/italic layer on top. So a
  family change works exactly like a weight change - even against an
  embedded run - and there is **no** "text box" to resize: page content
  text is absolutely-positioned glyphs, not a framed box, so size + the
  existing paragraph reflow are the only "make it bigger/re-fit" levers.
- `PdfTextStyle.embeddedFont` (a `PdfEmbeddedFont`) draws the replacement in
  an arbitrary embedded face, embedded into the page as an Identity-H
  composite. `_rewriteStyledTextRun` emits the replacement as 2-byte glyph
  ids in a new `Emb…` /Font resource (via `encodeHex`), restores the
  original `Tf`, and the resource is flushed once after all runs
  (`buildResource`, reusing the Type0 fallback machinery). It takes
  precedence over family/bold/italic. Because it draws by glyph id, the
  replacement need **not** be Latin-1: the run gate loosened to
  `findBytes != null` (find must still be Latin-1 to locate it in the simple
  run, but replace can be any Unicode the embedded font carries - Cyrillic,
  Greek, …). When the font can't draw a non-Latin-1 replacement and there's
  no base-14 fallback, the run is left untouched.
- `replaceText(..., PdfTextStyle? style)` + convenience
  `replaceStyledText(index, find, replace, style)`. When `style` is
  non-empty the simple-font run goes through the new
  `_rewriteStyledTextRun` instead of `_rewriteTextRun`; an empty/absent
  style keeps the exact old byte path (so existing tests and Ghent
  baselines are untouched).
- `_rewriteStyledTextRun` draws each matched span as its **own** show op
  bracketed by style operators and then restores state for whatever
  follows on the line:
  - colour: emit `r g b rg`, then re-emit the run's prior nonstroking
    colour afterwards. The prior colour is tracked in the main
    `replaceText` walk (`restoreColorOps`, watching `rg/g/k/sc/scn`, with
    a preceding `cs` remembered for `sc/scn`); it defaults to black
    (`0 0 0 rg`) when the run set no colour.
  - size / weight: emit `/Font size Tf`, then `/Font origSize Tf` to
    restore. Bold/italic substitutes a **base-14 variant**
    (`PdfStandardFont.styled(family, …)`, family inferred from the run's
    /BaseFont, defaulting to sans) allocated as a page /Font resource
    (`_standardFontResource`, WinAnsi Type1, reusing a matching entry).
    This is why weight/slant works even against an embedded face with no
    bold cut.
  - width compensation: the replacement is re-measured against the styled
    font/size and a `[kern] TJ` adjustment is inserted **in the restored
    (original-size) context**, so following text keeps its position. The
    kern converts the new width back to original-size em units:
    `newWidthEm * styledSize/fontSize - oldWidthEm`.
- Style operators can't go inside a `TJ` array, so the styled path emits
  its own show ops (`_emitSimpleCells` coalesces the untouched cells back
  into `Tj`/`TJ`). `q`/`Q` are illegal between `BT`/`ET`, which is why we
  restore by re-emitting operators rather than saving graphics state.

### Scope / limits

- Styling applies to **simple-font** (non-/Type0) runs only. A composite
  run is still corrected (glyphs re-encoded as before) but keeps its
  colour/size/face - `_rewriteStyledTextRun` bails on Type0. Extending
  the styling to the Type0 path is the obvious follow-up.
- `'` / `"` show operators aren't restyled (Tj/TJ only). Both strings
  still Latin-1 for the simple path, same as `replaceText`.

## UI (`dart_pdf_editor`)

- `text_style_prompt.dart`: `showPdfStyledTextPrompt` -> a dialog that
  **reuses the toolbar's text-box style controls** (Ben's review ask on
  #207): the shared `FontStyleToggles` (Bold/Italic), a font-size slider,
  and a `PdfColorSwatchRow` for the fill, above a text field. Returns
  `PdfStyledTextEdit(text, style)`. Overrides are opt-in - size/style/fill
  stay null (keep the run's value) until touched, so an untouched dialog is
  a plain replacement. `FontStyleToggles` reports a whole font, so touching
  the style sets both bold and italic absolutely.
- To share the colour row, `PdfColorSwatchRow` (+ its `_NoneSlashPainter`)
  moved into `editing_font_controls.dart`; the toolbar's `_boxColorRow`
  (Text fill / Text border / Shape fill) now delegates to it, so the popup
  and the dialog render the exact same swatch row. Same keys
  (`pdf-text-fill-*` etc.) - existing tune-popup tests unchanged.
- The dialog's **Font** row uses the editor's *normal* font menu
  (`showPdfFontMenu`) rather than a bespoke control: the toolbar passes a
  `pickFont` callback (`PdfStyledFontPicker`) that opens the shared menu
  with `onSelected` (so it doesn't disturb the controller's own default
  font) and returns the chosen `PdfTextFont`. A standard pick sets
  family/bold/italic; an embedded pick sets `embeddedFont` (precedence).
  When no `pickFont` is supplied (standalone `showPdfStyledTextPrompt`), the
  row falls back to a Sans/Serif/Mono dropdown so the dialog still works
  without a controller.
- Controller: `replaceStyledSelectedElementText(text, style,
  {fallbackFonts})` mirrors `replaceSelectedElementText`.
- Toolbar: a new `pdf-style-element-text` button ("Edit text & style",
  `format_color_text`) on the desktop element strip next to Replace
  text/Reflow. The **mobile** dock is width-constrained (380px in tests),
  so its existing single edit button (`pdf-replace-element-text`) now
  opens the styled editor instead of the plain prompt - the styled dialog
  is a superset (leaving all overrides untouched = a plain replacement),
  so nothing is lost and the dock doesn't overflow.
- `PdfEditingToolbar.styledTextPrompt` is injectable, defaulting to
  `showPdfStyledTextPrompt`, like `textPrompt`.

## Tests

- `pdf_document/test/content_edit_test.dart` "styled replacement" group:
  recolour + colour restore (default black and an existing run colour),
  size Tf switch + restore, bold base-14 variant allocation, width
  compensation, and empty-style == plain path.
- `dart_pdf_editor/test/editing_text_style_test.dart`: controller recolour
  / bold-variant / no-selection, the toolbar button opening the injected
  prompt and applying it (+ cancel is a no-op), and a dialog smoke test.
