# Off-thread text extraction on the web worker (#396 part 2, web twin)

#580 added the `extractText(pageIndex)` worker job on the isolate backend
(isolate-first, no bundle change). This brings it to the web worker, so web search
extracts off the UI thread too instead of falling back to a local extraction.

Mirrors #580's isolate plumbing on the web side:

- `render_worker_web.dart` (the main-side `_WebRenderWorker`): a
  `_WebRequestKind.extractText`, a `_WebPending.extractText` factory, and an
  `extractText` method that posts the request and `deserializePageText`s the
  reply. The `_pump` message builder already emits `kind/id/page` for every kind,
  so no request-specific fields are needed.
- `render_worker_web_entry.dart` (the worker that runs inside the Web Worker):
  a `kind == 'extractText'` branch that runs `PdfTextExtractor.extract` +
  `serializePageText` and posts the result. Extraction is synchronous (no
  cancellation seam) but lands off the UI thread, which is the point; a cancel
  targeting it is a no-op.

The codec (`serialize/deserializePageText`) and the base/pool/caching interface
came with #580, so nothing new is needed there.

## Bundle

Unlike the isolate side, this changes the web worker entry, so the checked-in
`pdf_render_worker.dart.js` is rebuilt. The `dart compile js` build is the real
check for web-worker code (`.toJS` conversions the analyzer misses); it compiled
clean. With `WORKER_REGEN_TOKEN` set, CI can auto-regen if a rebuild is ever
missed, but the committed rebuild is the primary path.

## Testing

The web worker can't run under `flutter test` (it needs a browser), so its
coverage is: the `dart compile js` build passing, and #580's
`render_worker_extract_text_test` proving the identical extraction+serialization
logic on the isolate. The wire codec round-trip (`page_text_codec_test`) is
platform-independent and already gates the serialization both twins share.

## Stacking note

Branched on #580 (not yet merged), so its diff includes #580's isolate changes
until that lands; the web-twin-specific files are `render_worker_web.dart`,
`render_worker_web_entry.dart`, and the regenerated bundle.

Files: `render_worker_web.dart`, `render_worker_web_entry.dart`,
`packages/dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js`.
