# 2026-07-16 — Bound the render worker record cache by entry count (#283)

Branch `claude/text-box-features-fixes-3ad025`. Issue #283: on web, tab memory
grows ~20 MB per page scrolled and is never released, even after the page
leaves the viewport and a forced GC. The growth appears unbounded in the page
count, which is the real worry — a long document (or a mobile browser with a
lower ceiling) plausibly hits the wall.

## What was ruled out

The per-page widget lifecycle is clean. The list is a plain lazy
`ExactExtentListView` with no `AutomaticKeepAlive`, so a page's
`_PdfPageViewState` is disposed once it scrolls past the 250 px cache extent,
and `dispose()` releases everything it holds: `_picture`/`_slugPicture`
(`_dropPicture`), the retained `_scene` (`_setScene(null)` →
`PdfRetainedScene.dispose`, which disposes its decoded `ui.Image`s), and
`_image`/`_detailImage`/`_preview`. `PdfPageRenderSession` holds no pixels.

The two named caches are already bounded: `PdfPagePreviewCache` (300 previews
at ~125 KB + a 32 MB full-raster budget) and the per-worker
`PdfWorkerTranscriptCache` (LRU cap 4). `PdfImageCache` is a byte-bounded LRU
(64–128 MB on web).

## The unbounded structure

`PdfCachingRenderWorker._cache` (`render_worker.dart`) is one map on the main
isolate wrapping the whole worker pool. It is keyed by
`(pageIndex, annotations, decodeImages, ratioBucket, commandLimit, region)`
and is *designed* to outlive the disposed page widget so a recycled/rebuilt
page is served without a re-decode. It was bounded only by decoded-image bytes
(`pdfRenderWorkerCacheBudgetBytes`, 96 MB), and eviction (`_oldestHeavyKey`)
**only ever removed entries with `weight > 0`.**

`_weigh` counts decoded RGBA only. So every image-free page and every
vector-first prefetch pass (`decodeImages: false`) produces a **weight-0**
record that the byte budget cannot see and the eviction loop never touches —
and there was no cap on the entry *count*. On a long scroll those pile up one
(or more, across ratio/region key variants) per page for the whole life of the
worker: retention keyed by page index that only grows. That is the piece that
makes the growth unbounded in the page count.

## The fix

Add a second bound to `_store`: after the byte-budget loop, evict the
least-recently-used records — weight-0 or not — until the map is back under a
maximum entry count (`pdfRenderWorkerCacheMaxEntries`, default 64), never
evicting the entry just inserted. The byte-budget semantics are unchanged (it
still bounds decoded pixels and still prefers to keep the cheap weight-0
buffers *within* the count budget); the count cap only stops the weightless
tail from growing without limit. 64 sits well above the on-screen + preview
warm working set (`previewWindow` ≤ 10 each side), so ordinary back-and-forth
revisits still hit. On-screen and recently-touched pages are the most-recently
used, so they are never the LRU victim.

Tests in `render_worker_test.dart`: the count is bounded across a 10-page
weight-0 scroll (cap 3); count eviction is LRU (a touched page survives, the
untouched LRU page is dropped); evicting a heavy LRU record decrements the byte
total; and the runtime default / explicit-override plumbing.

## Left open / scope

- This bounds the unbounded *Dart-side* main-isolate retention. The bulk of the
  ~1.9 GB the issue measured on a 62-page scroll is CanvasKit's wasm heap,
  which (as `performance_policy.dart` already notes) never shrinks back after
  `ui.Image.dispose()` on web — an engine characteristic, mitigated by the
  existing `imagePixelRatioCap` tiers, not fixable from Dart. For the reported
  62-page document the entry cap is a modest saving; its real value is the long
  document / high-page-count case the issue is most worried about, where the
  old behaviour was unbounded.
- The viewer's per-page maps (`_textCache` / `_annotCache` /
  `_visibleAnnotCache` / `_fieldRectCache` in `pdf_viewer.dart`) also grow one
  small entry per page visited and are cleared only on a document/revision
  swap. They hold text/annotation objects, not pixels, so the footprint is
  minor; bounding them is a possible follow-up.
