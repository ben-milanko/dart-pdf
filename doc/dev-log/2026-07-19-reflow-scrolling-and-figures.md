# Reflow reading view: lazy scrolling, navigation, saved position, figure viewer

Reworked the text reflow reading view (`PdfReflowView`,
`dart_pdf_editor/src/pdf_reflow_view.dart`) so it holds up on large books,
and wired it into the shell chrome as a first-class reading mode. Five
strands, all triggered by "scrolling a 600-page book in reflow is
horrifically slow, the panels don't work there, and mobile can't reach
it".

## 1. Lazy layout (the actual perf fix)

The old view walked **every** page's content stream up front in `_load`
(`PdfTextExtractor.reflowPage` × pageCount), pre-decoded **every** image
in the book, then laid every page out non-lazily in a
`SingleChildScrollView` + `Column` (a deliberate choice for exact scroll
extent - see the removed comment). On a 600-page book that is tens of
thousands of `SelectableText`s built and laid out at once, plus the whole
book's decoded pixels resident - so scrolling crawled.

Now:

- **Lazy widgets**: a plain `ListView.builder`, so only the pages near the
  viewport build. Scroll extent is estimated (it wobbles slightly as
  mixed-height pages enter/leave the build window) - the accepted trade
  for not freezing. `ExactExtentListView` is *not* usable here: it needs
  each item's extent up front, but a reflow page's height depends on text
  wrap and image aspect, unknown without laying it out.
- **Lazy reflow**: `_pageAt(i)` extracts + caches per page on demand.
- **Lazy images**: each page item (`_ReflowPageItem`) decodes its own
  figures when it scrolls into the build window and disposes the decoded
  clones when it scrolls out - only the visible pages hold pixels.
- **Empty-state without a full pass**: `_probeContent` scans for the first
  non-empty page and stops (a real doc resolves on page 0), so the "No
  extractable content" message stays correct without walking all pages.

`_settle` in the test now pumps a few extra frames after the spinner
clears, because image decode is per-item async now, not part of `_load`.

## 2. Navigation panels work in reflow

The panels were gated off whenever `altView` (reflow **or** page grid) was
active. The nav panels (Pages, Bookmarks) now stay available in reflow;
only the full-area page grid still hides them, and the canvas-bound panels
(search results, annotations, properties) still yield since they have no
page to act on.

To make them actually drive the reading view without a mounted
`PdfViewer`, `PdfViewerController` gained an **additive** reflow backend
(`PdfReflowBackend` in `pdf_viewer.dart`). A mounted viewer (`_state`)
always wins; the controller only consults `_reflow` when there is no page
canvas. `jumpToPage`/`animateToPage`/`showDestination`/`captureViewport`/
`restoreViewport`/`visiblePageRegion` fall through to it, and the reflow
view reports `currentPage`/`pageCount`/`viewportChanges` back. So the
thumbnail strip (taps + current-page highlight + viewport indicator) and
bookmarks navigate the reading view for free. Gotcha fixed along the way:
the deferred-notify guards in `_bumpViewport`/`_notifySafely` checked
`_state != null` and would drop notifications in reflow - now
`_state != null || _reflow != null`.

Jump-to-page in a lazy list (no `scrollable_positioned_list` dep): estimate
the offset from the average built-item extent, `jumpTo`, then align
precisely via the target item's `GlobalKey` once the frame builds it
(`_correctTo`, a few retries). Approximate for far jumps but converges for
the fairly uniform pages of a book.

## 3. Saved reading position

Reflow implements `captureViewport`/`restoreViewport` as `PdfViewport`
{page, fraction-into-page}, so the shells' existing `PdfViewportMemory`
persists and restores the reading position per document with **zero** new
plumbing. **Gotcha that cost the most time**: `reflowRestoreViewport`
first only did `addPostFrameCallback` - which never fires on its own if
nothing scheduled a frame, so the restore ran at teardown
(`mounted=false`). `jumpToPage` worked because its synchronous
`_scroll.jumpTo` schedules the frame. Fix: apply the restore eagerly when
the list has clients (the jump schedules the frame the corrections ride
on), and `scheduleFrame()` when we must defer for first layout.

## 4. Mobile bottom-sheet reflow toggle

Reflow was reachable on phones only via Controls → Settings → Reflow text.
Added a one-tap `pdf-shell-reflow-toggle` tile to the compact Controls
sheet in both shells (`PdfEditorView`, `PdfReader`) - it mirrors the
Settings toggle (turning reflow on clears the page grid in the editor).

## 5. Tap a figure → fullscreen viewer

Tapping a decoded figure in reflow opens a fullscreen
`_FullscreenReflowImage`: dark backdrop, `InteractiveViewer` (pan +
pinch/scroll zoom), close, and - when a host `onShareImage` handler is
supplied - a save/share action that renders the figure to PNG. The route
holds its **own clone** of the `ui.Image`, so it survives the source page
scrolling out and disposing its decode. Threaded as
`PdfReflowView.onShareImage` → `PdfEditorView.onShareReflowImage` /
`PdfReader.onShareReflowImage`; the example app wires it to its existing
`_saveImageBytes` (share sheet on phones, save dialog on desktop, download
on web). No handler → fullscreen view still works, just no share action.

Tests: `test/pdf_reflow_view_test.dart` (lazy build, controller
jump+track, capture/restore, fullscreen tap+share, share-absent) and an
updated `pdf_shell_test.dart` reflow expectation (the Pages strip now stays
in reflow). The old "scroll extent stays stable" test is gone - exact
extent was the very thing making it slow.
