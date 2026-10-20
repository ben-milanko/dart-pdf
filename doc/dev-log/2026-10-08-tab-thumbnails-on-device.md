# Tab overview thumbnails from the device store

The mobile tab grid (and the desktop tab hover card) painted a generic
"PDF" icon for every tab without an edit session - tabs restored from the
last session (`DocumentTab.deferredPath`), batch-opened tabs not yet visited
(`deferred`), and progressive first paints (`preview`). With a dozen restored
tabs most of the grid was placeholders.

`_TabPreview` now falls back to `_TabStoredPreview`, which asks the existing
device-persisted `RecentThumbnailCache` (the Recent files store, keyed by
`RecentFile.id`) via `_tabThumbnailEntry(tab)` - the same
`path ?? cachePath ?? title` identity, so a tab and its Recent entry share one
image. A miss renders once off the UI thread (worker record) from the tab's
`deferredBytes` when it holds them (`thumbnailFor(entry, bytes:)`), else from
its read path, and stores it. The icon stays only while that resolves or when
nothing can be rendered.

Keeping it fresh:
- A live tab's page-1 preview is written back (`RecentThumbnailCache.put`)
  when it looks like a fresh render would: unrotated, white paper,
  annotations on, not dirty. So the next launch already has the thumbnail.
- A save calls `invalidate(entry)` (empty record = miss), so restored tabs and
  Recent files re-render the saved revision rather than the stale one.
- `retain` (prune) also keeps open tabs' keys, so a tab that fell off the
  20-entry Recent list keeps its thumbnail.

Gotcha: rendering through `PdfRenderWorker` from a save path leaves a 30 s
timeout timer pending in widget tests; that's why save invalidates rather
than re-rendering.
