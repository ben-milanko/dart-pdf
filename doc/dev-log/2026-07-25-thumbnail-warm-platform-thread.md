# Thumbnail warm: budget the record to the tile, and stop competing for the platform thread (#603)

A ~20.8 s capture of scrolling a 62-page / 24 MB book (web release, 3
render workers) totalled **~6.7 s of main-thread `replay`** across the
background thumbnail warm — more, per tile, than the pages those tiles
preview (`build=44–472 ms` against `replay=376–860 ms`). The warm's
existing throttles are all on the *worker* side (priority 3 vs 2, decline
the UI-thread fallback), and none of them reach the half of a thumbnail
that runs on the platform thread: `PdfPageRenderer.pictureFromCommands`
plus the rasterize.

Three things were wrong, and they are three separate fixes.

## 1. The page image budget was a multiple of the wrong raster

`serializeCommands`' page image budget bounds the *total* decoded image
pixels a buffer may carry, because a sheet layered from dozens of
overlapping raster tiles sums to many times the page raster even when
every individual image is capped to its own on-screen footprint. The
budget was `imageBudgetFactor × _maxImagePixels`, and `_maxImagePixels`
(1 << 24, ~17 MP) is documented as "the viewer's full-page raster cap, so
it is also the natural unit for the page image budget."

It is the *cap*, not the raster. A 256px-wide tile of a Letter page
rasterizes ~85 000 pixels. Budgeting it 17 MP is 200× what it can ever
show — which is how a warm thumbnail ended up producing ~10 MB records
(`page=49 … 9955392B`), and how the main thread ended up building
`ui.Image`s for every one of those pixels at replay.

So `serializeCommands` gained `pageRasterPixels`: how many pixels the
raster this buffer is drawn into actually has. The budget becomes
`min(factor × 17 MP, headroom² × factor × pageRasterPixels)`.

- `headroom` is `cappedImagePixelSize`'s own 2× linear headroom, squared.
  That makes the new term a **no-op for a single full-bleed image** — a
  lone underlay a page render legitimately wants at 2× is never scaled
  by the page budget. It only bites where the per-image cap can't help:
  many images summing past the raster.
- It is a floor under the 17 MP cap, never a raise. `pageRasterPixels:
  1 << 30` serializes byte-identically to passing nothing.

**No wire change.** Both worker entries already know the page and the
ratio, so they compute it themselves via the new
`pdfPageRasterPixels(page.cropBox, imagePixelRatio)` and pass it to their
`serializeCommands` calls (`render_worker_isolate.dart`'s one-shot,
resumable-final and partial paths; `render_worker_web_entry.dart`'s
`_recordPageAsync`). The strip-detail paths are left alone — an
`imageDecodeRegion` already derives its own budget from the region.

Measured on `buildSyntheticRasterUnderlaySheet` (3 × 1400×1000 underlays
with soft masks), recorded at the tile ratio:

| tile | record bytes | decoded pixels |
| --- | --- | --- |
| 256px | 2 312 080 → 830 320 (−64%) | 556 032 → 185 592 |
| 128px | 643 984 → 274 432 (−57%) | 139 008 → 46 620 |

The record does not shrink by the full decoded delta because the source
streams are still written beside the pixels to key the decode by content
— that floor is #451's, not this one's.

## 2. The thumbnail replay decoded declined images at native size

`rasterizeThumbnail` passed `imagePixelRatio: ratio` to the worker but
called `pictureFromCommands` with no `maxImagePixelRatio`. Any image the
worker's codec declined (`declined=57(decodeNull:7,notDct:50)` in the
capture) arrives un-decoded, so it decoded at its **native** resolution —
on the platform thread — to fill a 256px tile. `PdfPageView` had always
passed the cap on this path; the thumbnail never did.
`pictureFromCommands` gained the parameter (it only existed on
`pictureFromCommandsWithPlan`) and the thumbnail passes its own ratio.

## 3. The warm competed with the viewer, and nothing said so

`PdfThumbnailCache`'s warm loop yielded on `_foregroundBusy` — but that
only tracks *thumbnail tile* tasks. Across the capture the warmer walked
pages 29→53 while the user scrolled 27→41, and the visible page's `wait=`
ran 244–938 ms over fourteen pages.

`PdfPageRenderScheduler` now exposes `busy` (a hold is up, or pages are
queued for their first interpret) and `activity` (a bare `Listenable`
pinged whenever `busy` may have moved). `PdfViewerController` republishes
them as `isPageRenderBusy` / `pageRenderActivity`, and both thumbnail
panels bind them into the shared cache with
`PdfThumbnailCache.bindForegroundGate`. The warm now returns before
starting a page while the viewer is rendering, and the activity ping —
not a frame poll — is what resumes it.

**The trap: `parked` ≠ `holding`.** `PdfViewer.active: false` sets
`holding = true` forever, and the full-area page grid (`PdfEditorView`'s
`showThumbnailView`) overlays the viewer with exactly that. Gating on
`holding` alone would have deadlocked the grid's own warm behind a hold
that never lifts. So the scheduler carries a separate `parked` flag, set
alongside every `holding = … || !widget.active`, and `busy` is
`!parked && (holding || pending)`. `render_scheduler_test.dart` and a
widget test in `editing_thumbnail_cache_test.dart` (a strip beside an
`active: false` viewer must still warm all pages) pin it.

The controller-side listenable is a `_PdfForwardingListenable`: the
controller outlives the viewer state, so a gate subscribed directly to a
live scheduler would be left holding a disposed object when the host
reparents the viewer. Swapping its `source` moves the subscription and
fires once.

Finally, the replay is wrapped in its own `TimelineTask` slice
(`thumbnail replay`, tagged page + reason), so a DevTools capture
attributes a stolen frame to the thumbnail that stole it instead of
leaving it indistinguishable from foreground work — the issue's "nothing
currently attributes it."

## What is deliberately not here

- **Command culling for a thumbnail-grade record** (the issue's first
  direction). Checked before writing it: the pages in the capture are
  1400–1800 commands of *book text*, and 9 pt text at the tile's 0.42
  ratio is still ~3.8 device pixels — nothing sub-pixel to drop. Culling
  would pay an O(commands) bounds pass to save approximately nothing on
  the document that filed the bug. It is the right tool for a CAD sheet,
  not for this.
- **Deriving the thumbnail from an existing page raster** (direction 2).
  The viewer's page rasters live in `PdfPageView`'s tile store, not
  anywhere the thumbnail panels can reach; wiring that across is a
  larger change than these three.
- **Not shipping the source stream beside decoded pixels.** That is the
  remaining floor under the record size, and it is #451.
