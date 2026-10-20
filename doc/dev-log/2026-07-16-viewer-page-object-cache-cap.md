# 2026-07-16 — Bound the viewer's per-page object caches (#283)

Branch `claude/continue-283-286-axq6un`. Follow-up to #286, which capped the
render worker's record cache by entry count and closed the unbounded-in-page-
count *decoded/transcript* half of #283. #286's "notes for reviewers" flagged
the remaining unbounded-in-page-count structure on the Dart side and this
picks it up.

## The structure

`_PdfViewerState` keeps four maps keyed by page index in `pdf_viewer.dart`:

- `_textCache` — a page's extracted `PdfPageText` (used by selection, search,
  hit-testing text positions).
- `_annotCache` — the page's interactive (action-bearing) annotations.
- `_visibleAnnotCache` — the page's visible annotations, for host tap
  callbacks.
- `_fieldRectCache` — the page's form-field widget rects, for the field
  highlight.

Each was a plain `Map<int, …>` populated with `[index] ??= …` and cleared only
on a document/revision swap (`didUpdateWidget`). So every page ever visited
left one entry behind for the life of the viewer: retention keyed by the page
index that only grows, the same shape #283 measured. The entries hold
text/annotation *objects*, not decoded pixels, so the footprint is minor (as
#286 noted), but on a long scroll it is still unbounded in the page count.

## The fix

New `PdfPageObjectCache<V>` (`page_object_cache.dart`) — a bounded, LRU,
int-keyed cache. Insertion order is LRU order (a plain Dart map is
insertion-ordered), so the first key is the least-recently used and a
remove-then-reinsert on access moves an entry to the most-recently-used end —
exactly the technique the render worker's record cache already uses. `[]`
touches on read, `putIfAbsent` computes-once on a miss and evicts the LRU tail
past the cap (never the entry just inserted). `clear()` for the swap path.

The four maps become `PdfPageObjectCache` instances; the four `??=` sites
become `putIfAbsent`, and the one plain read (`_extractText`) already used
`[]`, which the class implements. The `.clear()` calls in `didUpdateWidget`
are unchanged.

Cap: `pdfViewerPageObjectCacheMaxEntries` (default 128), a runtime override
mirroring `pdfRenderWorkerCacheMaxEntries` so a memory-constrained host can
lower it once at startup. 128 sits far above the on-screen + preview-warm
working set (a page's objects are derived only when it is near the viewport —
hit-tested, selected, or searched; `previewWindow` ≤ 10 each side), so a page
in view is never the LRU victim and ordinary back-and-forth revisits still hit.

Full-document search (`_searchAllPages`) walks every page through
`_extractText`, using each page's text once and immediately, with no cross-page
reuse — so eviction behind the walk costs nothing, and a static document still
has the persistent `PdfViewer.textCache` behind the in-memory cap.

## Tests

`page_object_cache_test.dart`: the count is bounded across a 100-page fill
(cap 3, only the newest survive); the cap is never undershot while filling; a
lookup marks its page MRU so the untouched LRU page is the eviction victim; a
`putIfAbsent` hit returns the stored value without recomputing and refreshes
recency; `clear` empties; the runtime-default / explicit-override plumbing; and
the cap floors at 1. `dart analyze` is clean; `pdf_viewer_test.dart` and the
text-cache suites still pass.

## Left open / scope

This is the last of the *Dart-side* unbounded-in-page-count retention #283
named. The bulk of the memory the issue measured on a 62-page scroll remains
CanvasKit's wasm heap, which never shrinks back after `ui.Image.dispose()` on
web — an engine characteristic (already noted in `performance_policy.dart`),
mitigated by the `imagePixelRatioCap` tiers, not fixable from Dart.
