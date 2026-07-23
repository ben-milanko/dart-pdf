# Paste-location hover indicator on the thumbnail strip

The docked thumbnail strip (`PdfThumbnailSidebar`) now marks where a page
paste will land while the mouse hovers it: with pages on the shared
`PdfPageClipboard`, the tile under the cursor grows a slim primary-colored
insertion bar (`_PasteInsertionMarker`) along its bottom edge, so the
destination of the next ⌘/Ctrl+V reads ahead of the keystroke.

## Where the mark shows (`editing_thumbnails.dart`)

- `_PdfThumbnailSidebarState._pasteInsertionPage` is the hovered page when
  the clipboard has pages **and** the platform has reliable hover
  (`pdfPanelControlsRevealOnHover()` - desktop only; touch has no hover).
  It's `null` otherwise, which hides the mark.
- The tile owns the paint: `_PageTile.showPasteIndicator` overlays the
  `_PasteInsertionMarker` (an `IgnorePointer` dot-line-dot bar) at
  `bottom: 0` in a `Stack`, so it never reserves layout space, never eats a
  pointer (tap/drag still work), and reads as "insert after this page".
  Keyed `pdf-thumbnail-paste-indicator-$page` for tests.
- Gotcha that bit once: `_pasteInsertionPage` must be computed **inside**
  the `ListenableBuilder(listenable: controller)` builder, not in
  `_buildFrame`. Filling/clearing the clipboard is a controller
  notification that only rebuilds that inner builder; the outer frame keeps
  its stale (empty-clipboard) value, so a mark hovered *before* the copy
  would never appear. `rangePreview` stays in `_buildFrame` because it's
  driven by `setState` (Shift/hover), not the controller.

## Paste follows the mark

`_pastePages` now aims at `_pasteInsertionPage` first, falling back to the
old selection / keyboard-page anchor when nothing is hovered. So ⌘/Ctrl+V
drops the pages exactly where the bar shows, and the indicator never lies.
The header-menu and right-click-menu paste paths are unchanged (they carry
their own explicit target - current page / right-clicked page).

Scoped to the strip only, as asked. The full-area grid (`PdfThumbnailView`)
leaves `showPasteIndicator` at its `false` default - its inserts are
horizontal between tiles, a different affordance.

Tests: `editing_page_clipboard_test.dart` gains a
`PdfThumbnailSidebar paste indicator` group - the mark appears only with a
filled clipboard, follows the cursor, clears on exit, and ⌘/Ctrl+V lands
after the hovered tile rather than the selection. Both pin
`debugDefaultTargetPlatformOverride = macOS` (reset in a `finally`, since
`testWidgets` verifies foundation invariants before tearDown runs) so hover
is treated as reliable.
