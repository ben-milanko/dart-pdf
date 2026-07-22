# Text-box resize preview: re-wrap embedded-font boxes too

## Symptom

Dragging a free-text (text box) resize handle **stretched the glyphs** in
the live drag preview while the eventual commit re-wrapped the text at a
constant font size. The preview disagreed with the result: the text
appeared to scale, then snapped back to wrapped on release.

## What was already there

The overlay already previews the re-wrap for **base-14** free text:
`_textResizeStyle` (editing_overlay.dart) suppresses the stretch ghost and
floats a live Flutter `Text` widget (`_wrappedTextBox`) that wraps at the
committed point size into the dragged rect, over a "lifted" clean page
render (the page drawn without the box). The commit side already re-wraps
both base-14 and embedded boxes: `PdfAnnotationBehavior.resizeBehavior`
returns `reflowText` when the box has *either* a `standardTextFont` *or*
`hasEmbeddedTextFont` (annotation_behavior.dart).

The gap was preview-only: `_textResizeStyle` bailed to `null` (→ stretch
ghost) whenever `standardTextFont == null`, i.e. for every embedded/bundled
font box - the common case when the editor's active font is a loaded TTF.

## Fix

Reuse the inline editor's embedded-font preview machinery. That path
(`_ensureEmbeddedFontPreview` / `_embeddedPreviewFamilies` /
`_textEditUiFamily`) already registers an embedded font's outline bytes
with the engine under a synthetic `pdfedit-<key>` family via
`ui.loadFontFromList`, so Flutter can lay the real font out.

- `_textResizeStyle` now falls back to the box's embedded face
  (`standardTextFont ?? _resizeEmbeddedFontOf(annotation)`); its record's
  `font` widened from `PdfStandardFont` to `PdfTextFont`. Same for
  `_afterText` (the frozen post-commit afterimage) so an embedded resize
  also freezes wrapped, not stretched.
- `_wrappedTextBox` takes a `PdfTextFont`, kicks off
  `_ensureEmbeddedFontPreview` for embedded faces, resolves its family
  through `_textEditUiFamily` (embedded-aware) instead of the base-14-only
  `_uiFamily` (removed - the inline editor's field now shares
  `_textEditUiFamily` too), and gates bold/italic on `is PdfStandardFont`.
- Until the async font load lands, `_textEditUiFamily` returns null and the
  preview wraps in a fallback face - still wrapped, never stretched - then
  rebuilds to the real face. Matches the inline editor's existing
  fallback-face-while-loading behaviour.

## Gotchas / why it's shaped this way

- The embedded font program can't be recovered cheaply -
  `PdfEmbeddedFont.fromFreeText` decodes the /FontFile program - and
  `_textResizeStyle` is read every drag frame from `build`. So the parse is
  cached in the overlay against the **annotation instance identity**
  (`_resizeEmbeddedFontOf`), which is stable within a revision (page
  `annotations` and `PdfAnnotation.behavior` are both cached), giving one
  parse per selection rather than per frame.
- The cache lives in the overlay, **not** on `PdfAnnotationBehavior`:
  `annotation.dart` sits below `font_embedder.dart` in the layering
  (font_embedder imports annotation, not vice-versa), so referencing
  `PdfEmbeddedFont` from `annotation_behavior.dart` would introduce a
  circular import. `hasEmbeddedTextFont` stays the cheap COS-only gate on
  the behavior; the actual parse is the editor's job.

## Test

`editing_text_edit_test.dart` -> "resizing an embedded-font box previews
the re-wrap too": loads DejaVuSans, adds a box, drags a handle, and asserts
the `pdf-text-resize-preview` widget shows the real text at the committed
size mid-drag (previously it found nothing and the stretch ghost took
over). The existing base-14 preview and shape-stretch tests still pass.
