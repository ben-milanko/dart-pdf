# Paste-location hover indicator in the page grid

Extends 2026-07-22-thumbnail-paste-indicator.md (strip only) to the
full-area grid (`PdfThumbnailView`). With pages on the shared
`PdfPageClipboard`, the cell under a desktop mouse grows the same
`_InsertionMarker` bar, standing **vertically along the cell's
reading-order end** (right in LTR, left in RTL) - the gap between it and
the next cell, where the pasted pages will land.

- `_PdfThumbnailViewState._pasteInsertionPage` mirrors the strip's rule
  (editable + clipboard non-empty + hovered + `pdfPanelControlsRevealOnHover()`)
  and is read inside the `ListenableBuilder(listenable: controller)` builder
  for the same reason as the strip: a clipboard fill is a controller
  notification, not a `setState`.
- `_GridPageCell` gains `showPasteIndicator` + `reversed` and hands
  `_PageTile` `scrollAxis: Axis.horizontal` - the tile's existing marker
  placement for a horizontal strip is exactly the grid's trailing edge, so
  no new paint code. (`scrollAxis` is only read by the paste marker.)
- `_pastePages` aims at the hovered cell first, falling back to the
  selection / keyboard page, so ⌘/Ctrl+V lands where the mark shows. The
  header-menu and right-click paste paths keep their explicit targets.

Tests: `PdfThumbnailView paste indicator` group in
`editing_page_clipboard_test.dart` (mark appears only with a filled
clipboard, sits on the cell's right edge, follows the cursor, clears on
exit; ⌘/Ctrl+V lands after the hovered cell rather than the selection).
