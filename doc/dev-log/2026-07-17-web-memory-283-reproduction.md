# 2026-07-17 — Reproducing the web tab-memory growth (#283)

Issue #283 (split from #281) reported that a web tab grows ~20 MB per page
scrolled and never releases it, running to ~2.3 GB over a 62-page image-heavy
document — with the decoded-image cache flat at its budget the whole time, so
the cache is not the source. It asked whether per-page retention (retained
scenes / `ui.Picture`s, worker transcripts, anything keyed by page index)
survives the page scrolling out of view and a GC.

This session set out to **reproduce the measurement on the current codebase**
(which already carries the #286 render-record cap and the #305 page-object
caps) and characterise the growth, before proposing any further change.

## What was already bounded (code audit)

Every per-page structure the issue named is bounded, and page state is
disposed when it scrolls out of the `ListView` build window:

- `PdfPagePreviewCache` — 300 previews + a 32 MB full-raster pixel budget, LRU,
  disposes evicted images (`preview_cache.dart`).
- `PdfWorkerTranscriptCache` / the worker's `_BinCommandCache` — ≤4 / ≤2
  entries plus a retained-command-weight cap, per worker
  (`render_worker_transcript_cache.dart`, `render_worker_isolate.dart`).
- `PdfCachingRenderWorker._cache` — 64 entries / 96 MB, byte- and count-bounded
  (`render_worker.dart`).
- `_textCache` / `_annotCache` / `_visibleAnnotCache` / `_fieldRectCache` —
  `PdfPageObjectCache` (LRU, cap 128) since #305 (`pdf_viewer.dart`).
- `PdfImageCache` — byte-budgeted, clone-on-take / dispose-on-evict.
- `_PdfPageViewState.dispose()` disposes `_scene` (the retained scene **and its
  decoded images**), `_image`, `_detailImage`, `_preview`, `_slugPicture`, and
  cancels the page's queued worker / scheduler work (`pdf_page_view.dart`). The
  viewer's `ListView` has **no** keep-alive requesters (nothing in
  `lib/src/` uses `AutomaticKeepAliveClientMixin` / `wantKeepAlive` /
  `KeepAliveNotification`), so a page past the 250 px cache extent is genuinely
  unmounted and disposed — retained scenes/pictures *are* dropped when a page
  leaves the viewport, including on web.

So the retained scenes the issue asks about are released; the question is
whether the *measured* growth is a Dart object leak or CanvasKit's WASM
linear-memory high-water mark (which never returns freed pages to the OS on
web — already noted in `performance_policy.dart`).

## Reproduction harness

The corpus is git-ignored and absent in a fresh checkout, so a self-contained
generator now builds a representative image-heavy document:

`packages/pdf_cos/tool/gen_image_pdf.dart` — writes an N-page PDF (via the
from-scratch `CosDocumentBuilder`) where each page draws one full-page RGB
image XObject, plus optional vector rectangles. The images differ per page
(the decoded-image cache can't dedup them) but are highly compressible (small
file, full decoded RGBA footprint), matching #283's doc shape (24 MB file,
~436 MB decoded). Defaults: 62 pages, 1240×1650 (~8.2 MB RGBA/page, ~507 MB
total).

```sh
# image-only pages
fvm dart run packages/pdf_cos/tool/gen_image_pdf.dart perf_images.pdf 62
# image + 4000 vector rects/page (print/CAD-like retained-scene weight)
fvm dart run packages/pdf_cos/tool/gen_image_pdf.dart perf_rich.pdf 62 1240 1650 4000
```

### Making `app/tool/perf/driver.mjs` measure memory headless

`performance.measureUserAgentSpecificMemory()` (the only probe that counts
CanvasKit's WASM heap) needs cross-origin isolation *and* the browser-process
PerformanceManager. Getting it to run headless on Linux CI took three fixes,
now folded into the tooling:

1. **New headless, not the shell.** `headless_shell` (old `--headless`) has no
   PerformanceManager, so the call throws `SecurityError: … is not available`
   even when `crossOriginIsolated === true`. `driver.mjs` now launches new
   headless (`headless: true`) — point `PERF_CHROME` at a **full** browser
   binary, not a `*_headless_shell` one.
2. **Local CanvasKit.** `build.sh` now passes `--no-web-resources-cdn`, so
   CanvasKit is bundled into `build/web/canvaskit` instead of fetched from
   gstatic.com — which a headless/offline run can't reach, and which the
   `credentialless` COEP the driver sends would block anyway.
3. **Locale.** A locale-less headless host makes Flutter's intl throw
   "Incorrect locale information provided" at boot; `driver.mjs` now passes
   `--lang=en-US --accept-lang=en-US`.

## Measured results (current code, 64 MB image-cache budget, fast pass off)

Chromium 1194 (Playwright build), new headless, `--expose-gc` forced GC before
each sample.

Image-only doc (1 image op/page):

| pages rendered | agent memory | image cache |
|---|---|---|
| 9  | 351 MB | 57 MB |
| 20 | 358 MB | 57 MB |
| 25 (of 62) | 371 MB | 59 MB |

≈ **0.4 MB/page** — essentially flat.

Image + 4000-vector-rects/page doc (print/CAD-like), all pages fully rendered:

| pages rendered | agent memory | image cache |
|---|---|---|
| 10 | 420 MB | 58 MB |
| 20 | 441 MB | 58 MB |
| 62 | 569 MB | 57 MB |

≈ **2.9 MB/page**; the image cache stays pinned at its budget throughout.

For contrast, #283's pre-cap numbers were 1122 MB (10 pages) → 2286 MB
(62 pages), ≈ **20 MB/page**.

## Conclusion

On the current codebase the unbounded-in-page-count Dart retention #283
measured is gone — the #286 and #305 caps closed it. Tab memory now tracks
per-page **content** weight, not page count: a trivial page costs ~0.4 MB of
creep, a vector-rich page ~2.9 MB, and the image cache never exceeds its
budget. That residual creep is CanvasKit's WASM high-water mark (peak
simultaneous decode + `ui.Picture`/scene + raster allocation, plus allocator
fragmentation that never shrinks back on web), scaling with render complexity —
consistent with the code audit above, where every per-page cache is bounded and
the page State + retained scene + rasters are disposed on scroll-out.

A real document's pages are heavier than these synthetic ones, so it will creep
more than 2.9 MB/page — but the growth is bounded per-page-content and no longer
unbounded per-page-count. Lowering the plateau further is a peak-allocation /
WASM-fragmentation problem (the lever the existing `imagePixelRatioCap` and
preview-window tiers already pull), not an un-freed Dart object; it needs the
real target document to tune against, which the harness above now makes
reproducible in a headless/CI run.
