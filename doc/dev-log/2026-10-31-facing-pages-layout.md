# Two-page (facing) view - issue #1217

`PdfPageLayout.facing({scrollAxis = Axis.vertical, coverPage = false})`
pairs consecutive pages into side-by-side spreads (an open notebook) and
scrolls continuously through them along either axis. The editor shell
exposes it as **View options -> Two-page view** (+ **Show cover page
separately** once it is on), persisted as `PdfEditingPreferences.twoPageView`
/ `twoPageCoverPage`, also in the command palette (`view-two-page`,
`view-two-page-cover`). `PdfEditorView`/`PdfReader` apply the pref to the
host's layout via `PdfPageLayout.withFacing`, so a host that chose a
horizontal layout gets horizontal spreads.

## Geometry: slots, not pages

The scroll list (`ExactExtentListView`) is now a run of **slots**: one per
page in a continuous layout (slot == page index, nothing changed there), one
per spread in a facing one. Everything that walks the main axis goes slot by
slot - `_remapMain`, `_updateCurrentPage`, `_captureViewport`,
`_pagePointAt`, `_pageContainsListPoint`, `_preserveReadingAnchor`, the
outline markers' total, the item extents. The helpers (pdf_viewer.dart,
"spreads" block): `_slotCount`, `_slotOf`, `_slotFirstPage`/`_slotLastPage`,
`_slotMain(slot, [zoom])`, `_mainInSlot(page)`, `_slotPageNear`,
`_pageMainStarts()` (used by the two preview/raster warm loops, which also
stopped measuring a horizontal layout by page *height*). `_mainOffsetOf(page)`
= slot start + leading spacing + `_mainInSlot`, so every caller of it
(`_jumpToPage`, destinations, search, outline ticks, `_placeViewport`) is
spread-correct for free.

- **Vertical spreads** fit `2 x` the widest page across the viewport
  (`_maxCrossPoint`), the spine sits on the viewport's centre line
  (`_crossInsetOf`: a left page ends there, a right page starts there), and a
  shorter page is centred on its spread's height. The spine staying on the
  centre line is what keeps `_remapCross` (scale about the centre) exact.
- **Horizontal spreads** fit the tallest page to the height as before; the
  two pages of a spread touch and `pageSpacing` separates spreads.
- Pages meet with no gutter - the "open notebook" look the issue asked for.
- Sides: without a cover, even indices are left pages; with one, odd indices
  are. A lone page keeps its side (cover on the right, unpaired last page on
  the left).

A facing slot builds a `Stack(clipBehavior: Clip.none)` of `Positioned`
pages at the exact offsets the helpers report, each wrapped in
`_editingReach` directly (Positioned already sizes it to the page; the
unclipped Stack spans the slot the way `Center` does in the continuous item).
The slot is keyed by its first page's identity; `findChildIndexCallback`
maps any page identity to its slot.

## Current page and navigation

`currentPage` is the page of the spread under the viewport's cross-axis
centre - so at fit it is the spread's **left** page (`_slotPageNear` uses
`<=` at the spine). Jumping to a right page shows its spread and reports the
left one. Next/Prev-page named actions step by spread (`_steppedPage`):
stepping one page would land on the other half of the spread already on
screen, scroll nowhere, and leave `currentPage` unchanged - a stuck button.

## Not done

- Right-to-left spreads (`/Direction /R2L` in ViewerPreferences) and reading
  the document's `/PageLayout` (`TwoColumnLeft`/`TwoPageRight`, ...) to pick
  the default.
- The two new strings are abstract getters on `DartPdfEditorLocalizations`,
  which the release notes should call out for custom localization subclasses.

Tests: `packages/dart_pdf_editor/test/pdf_facing_layout_test.dart` (layout,
cover, unpaired page, jump/current page, overlays + taps on a right page,
viewport capture/restore, search, Fit.page, horizontal spreads, runtime
layout switch, zoom-out relayout, drawing a rectangle on a right page) plus
the shell menu test in `pdf_shell_test.dart`.
