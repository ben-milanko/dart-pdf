# Thumbnail strip: paste no longer scrolls back to the top

## Symptom

Pasting a page in the thumbnail strip (⌘/Ctrl+V, or the multi-selection
bar's paste button) scrolled the strip back to the top instead of
revealing where the pasted pages landed.

## Cause

The strip (`_PdfThumbnailSidebarState` in `editing_thumbnails.dart`)
follows the viewer: `_onViewerChanged` reveals the viewer's current page
whenever it changes (`followsViewer`, the default). A paste inserts pages,
which is a geometry-changing revision, so `PdfViewer._swapDocument`
(`pdf_viewer.dart`) resets its scroll to the top in a post-frame callback
(`_scroll.jumpTo(0)`). That fires `_onViewerChanged(0)`, and the following
strip dutifully revealed page 0 - scrolling to the top and burying the
pages that just landed.

`_pastePages` revealed the paste target synchronously, but the viewer's
later reset (and the resulting `_onViewerChanged(0)`) overrode it.

## Fix

Route the strip's `_pastePages` through `_jumpToInsertedPage` (the same
helper the tile context-menu and header page-actions paste paths already
use). It waits two `endOfFrame`s - past the viewer's scroll reset - then
`jumpToPage(at)`, so the viewer (and the strip that follows it) ends on the
pasted page instead of the top. Non-following strips keep the direct
`_revealPage(at)`, since they never chase the viewer's reset.

The menu/header paste paths were already immune because they navigate the
viewer via `_jumpToInsertedPage`; only the keyboard/selection-bar path was
missing it. The grid view (`_PdfThumbnailViewState`) never listens to the
viewer, so it was never affected.

## Test

`editing_page_ops_test.dart` -> "⌘V paste reveals the new page instead of
jumping to the top" mounts a real `PdfEditorView` (the strip test harness
alone mounts no viewer, so the reset that drives the bug can't fire there),
copies a page, selects a lower anchor, pastes with Ctrl+V, and asserts
`viewer.currentPage` lands on the pasted page rather than 0. It fails
against the pre-fix code (currentPage == 0) and passes with the fix.
