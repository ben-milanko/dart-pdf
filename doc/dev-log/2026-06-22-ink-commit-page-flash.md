# Fix: heavy CAD page flashes blank after an ink markup commit

## Symptom

On a heavy CAD page, finishing an ink markup made the **whole page flash
blank** for a moment before re-appearing with the stroke baked in. The
stroke itself was fine; the page content under it vanished and came back.

## Cause

`finishInk()` commits the strokes through `apply()`, which swaps in a new
`PdfDocument` and bumps the edited page's *render stamp*
(`pageRenderStamp`). The viewer passes that stamp to `PdfPageView` as
`contentStamp`, and `PdfPageView.didUpdateWidget` **nulled `_image`**
(dropped the on-screen raster) on every `contentStamp` change, then
re-interpreted the page. On a heavy page that re-interpret is slow, so for
its duration the page painted the blank paper placeholder while only the
committed-ink overlay stayed up - the flash.

The blanking was added for redaction safety: after a burn, keeping the old
raster would briefly show the *removed* content. But it fired for **every**
content edit, including purely additive ones (ink, highlights, shapes),
where the old raster is still correct for everything except the new mark -
and the new mark is already drawn on top by the editing overlay
(`committedInkOn` / `rasterCurrent`) until the fresh raster lands.

## Fix

Split the signal into additive vs destructive:

- `PdfEditingController` now tracks `pageDestructiveStamp` alongside
  `pageRenderStamp` (`_destructiveStamps` / `_destructiveStampEpoch`,
  `_bumpDestructiveStamps`). Only `applyRedactions` (`_resetTo`) bumps it.
- The viewer threads `destructiveStamp` through `_PdfViewerPage` into
  `PdfPageView`.
- `PdfPageView.didUpdateWidget` now blanks `_image`/`_preview` (and drops
  the detail patch) **only** when `pageEpoch` (structural slot reuse) or
  `destructiveStamp` changes. A plain `contentStamp` advance still
  re-interprets, but keeps the old raster painted until the new one
  replaces it (`_dropPicture` nulls `_rasteredRatio`, so `_renderNow` still
  re-rasters) - exactly the zoom-settle behavior. No blank flash.

This also matches the pre-existing comment on the epoch path: "a
same-geometry edit keeps the raster while the render holds."

## Notes / gotchas

- Content edits that *change* existing content (delete element, replace
  text) intentionally stay on the additive path: they go through `apply`,
  not `_resetTo`, so the old content lingers for a frame (smooth update)
  rather than flashing. Only a redaction burn - where lingering exposes
  deleted content - is treated as destructive.
- The detail (deep-zoom) patch is only force-dropped when we blank;
  otherwise it follows through `_updateDetail`'s generation guard, the same
  way the scale-change path already relied on it.

## Tests

- `test/pdf_page_view_test.dart`: additive `contentStamp` bump keeps the
  raster under a render hold; `destructiveStamp` bump drops it.
- `test/editing_redaction_test.dart`: ink commit advances the render stamp
  but not the destructive stamp; a burn advances the destructive stamp on
  every page.
