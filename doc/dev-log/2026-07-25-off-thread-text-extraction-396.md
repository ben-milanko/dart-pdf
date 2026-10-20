# Off-thread text extraction for search (#396 part 2)

Search extracted every page's text on the UI thread: `_searchAllPages` →
`_extractText` → `PdfTextExtractor.extract`, a full content walk (100–420 ms on a
heavy page) per page. Part 3 (#575) yielded per page so a keystroke could bail,
but each page still froze a frame. This moves the extraction itself to the render
worker. Isolate-first, exactly like #530 — the web twin follows.

## The codec

`PdfPageText` is plain data — a page index, the page text, and a list of runs,
each `(text, startIndex, mcid?, PdfMatrix, width, PdfRect, isRightToLeft)`. So it
crosses the worker→UI boundary as a compact byte buffer, not a graph copy.
`serializePageText` / `deserializePageText` (`render_command_codec.dart`, reusing
its `_Writer`/`_Reader`/matrix/rect helpers) do that; the search quads/rects a
match needs are recomputed from the runs on read, so they aren't serialized.

## The worker job

A new `extractText(pageIndex)` job, mirroring `buildRegionIndex` (#389, the
precedent the ticket names):

- `PdfRenderWorker.extractText` — base declines (null); `PdfPooledRenderWorker`
  routes by page; `PdfCachingRenderWorker` delegates.
- The isolate backend adds a `_RequestKind.extractText`, a `_PendingRequest`
  factory, a `_pump` send, and a worker-side handler that runs
  `_extractTextForWorker` (`PdfTextExtractor.extract` + `serializePageText`).
  Synchronous — extract has no cancellation seam — but it runs on the worker
  isolate, so a heavy page no longer freezes a frame; a superseded search just
  discards the result.

## Viewer wiring

`_extractText` now calls `_extractPageText`, which routes through
`_effectiveRenderWorker.extractText` when a worker is active and falls back to a
local extraction otherwise (web today, and any host that opted out). The worker
is kept in step with the current revision by part 1's `_syncDefaultWorker` (and
the shell for a host worker), so an edit session extracts current text, not
stale. Hover keeps its synchronous `_pageText` path — already gated by content
size, so a heavy page never extracts on hover.

## Isolate-only, bundle unchanged

The web worker entry is untouched, so the web backend inherits the base `null`
and web search falls back to a local extraction (unchanged). Crucially, the codec
functions live in `render_command_codec.dart` (reachable from the web bundle) but
are **unused** by the web worker entry, so dart2js tree-shakes them: a rebuild of
`pdf_render_worker.dart.js` is byte-identical, so no bundle change and CI's
`worker-bundle` stays green with no token needed. The web twin (an `extractText`
message in `render_worker_web_entry.dart`) is the follow-up.

## Tests

- `page_text_codec_test.dart` — a synthetic and a real-extraction `PdfPageText`
  round-trip field-for-field, and a search over the restored text lands the same
  quads.
- `render_worker_extract_text_test.dart` — a real isolate worker's `extractText`
  matches a local `PdfTextExtractor.extract` (text + run count + search hits),
  and a bad index declines to null.
- Existing search/text-cache suites pass (in tests the default worker is off, so
  the local fallback runs — unchanged behavior); analyze clean.

Files: `render_command_codec.dart`, `render_worker.dart`,
`render_worker_isolate.dart`, `pdf_viewer.dart`, + two new tests.
