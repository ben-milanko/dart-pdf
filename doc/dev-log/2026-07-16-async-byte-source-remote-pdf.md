# 2026-07-16 — Asynchronous byte-source API for progressive remote loading (#325)

Branch `claude/async-byte-source-remote-pdf-b97wkm`. #325 asks for a random-
access, possibly-async PDF byte source so a host need not download a whole
remote file before the parser can begin — plus an HTTP adapter that uses Range
requests, forwards auth, supports cancellation/progress, and degrades to a full
download when ranges are unavailable. The public `open(Uint8List)` path and the
byte-based widgets stay untouched; this is purely additive.

## Constraint that shaped the design

The COS parser is **synchronous** end to end: `CosDocument`, `getObject`,
`resolve`, `decodeStreamData`, and every `pdf_document`/`pdf_graphics` caller
read `bytes[i]` off an in-memory `Uint8List`. Making resolution lazily async
would cascade an `await` through hundreds of call sites — out of scope and
risky. So rather than parse *from* the source, the loader **prefetches exactly
the byte ranges the synchronous parser will need** into a sparse buffer and
hands that to the existing `CosDocument.open`. Every byte the sync path reads is
already present; unfetched regions (free space, dead revisions, post-EOF junk)
stay zero-filled and are never touched.

## Core (`pdf_cos/src/byte_source.dart`)

- `PdfByteSource` — `Future<int?> get length` + `Future<Uint8List>
  readRange(start, endExclusive)` + optional `close()`. Network-agnostic.
- `PdfBytesByteSource` — an in-memory implementation (tests, and adapting
  already-downloaded bytes).
- `openCosDocumentFromSource(...)` / `CosDocument.openSource(...)` /
  `PdfDocument.openSource(...)` — the entry points, with a
  `PdfSourceLoadOptions` (head/tail/xref window sizes, coalescing gap, download
  chunk, `onProgress`).

The `_ProgressiveLoader`:

1. Fetches a small **header probe** (settles the `%PDF-` offset shift) and a
   **tail window** (`startxref` + newest xref section).
2. **Walks the xref chain** newest-to-oldest with ranged reads, following
   `/Prev` and `/XRefStm`, parsing tables and cross-reference streams to
   collect the absolute offsets of every in-use object. Compressed objects need
   no offset — their container `ObjStm` is itself an in-use object in the chain.
3. **Fetches the live objects' byte ranges**, each bounded by the next object
   offset *and* the surrounding xref sections (object bodies never cross an
   xref section), coalescing ranges within `coalesceGap` into one request.
4. Opens the populated buffer with the ordinary `CosDocument.open` — so
   encryption, object streams, recovery, `/Prev`, and everything else work
   unchanged.

### Why truncated reads can't corrupt silently

An xref section parse only *succeeds* when its terminator (`trailer` for a
table; `endstream`/`endobj` for a stream) is reached over real bytes. Beyond the
fetched window the buffer is zero-filled, and `0x00` is PDF whitespace, so the
lexer skips it and hits EOF — every truncation **throws** rather than returning
a plausible-but-wrong offset. The loader therefore just widens the window
geometrically and retries on any failure, giving up to the full-download
fallback only once the whole remaining file has been fetched. A successful parse
is authoritative, which also guarantees the loader's xref view matches what the
final `CosDocument.open` re-derives from the same bytes.

### Fallbacks

Unknown length, a broken cross-reference chain, or a ranged read that fails all
unwind (`_FallbackToFullDownload`) to a plain sequential download — chunked
until a short read signals EOF when the length is unknown — then the normal
`open` (with its own scan-recovery) takes over. A non-range-capable server thus
still works, just without the bandwidth savings.

## HTTP adapter (`dart_pdf_editor/src/http_byte_source.dart`)

`PdfHttpByteSource` (new `http: ^1.2.0` dep — cross-platform, VM + web fetch, no
`dart:io` in our code). One one-byte ranged GET (`Range: bytes=0-0`) probes both
length (from `Content-Range`) and range support:

- **206** → ranges work; reads issue `Range` GETs.
- **200** → server ignored Range (or a web CORS response hid the headers); the
  full body is kept and every later range is served from memory.
- **416** → empty/past-end.
- other status / transport failure → `PdfHttpException`.

`headers` carry auth (`Authorization`, cookies via a caller-supplied
`BrowserClient()..withCredentials`), a `PdfCancelToken` aborts in-flight and
future reads with `PdfHttpCancelledException`, and `onProgress` reports bytes
received. CORS is documented: cross-origin progressive loading needs the server
to expose `Content-Range`/`Accept-Ranges` via `Access-Control-Expose-Headers`,
else it falls back to a full download. `close()` only closes a client the source
created itself.

## Tests

- `pdf_cos/test/byte_source_test.dart` (17): classic table, xref-stream +
  object-stream, multi-page, header/tail as separate ranges (not one blob),
  `/Prev` chain from an incremental update, tiny-window growth, progress
  monotonicity, unknown-length + chunked fallback, broken-`startxref` recovery,
  cancellation, non-PDF, corrupted body, encrypted (owner password + wrong
  password), and `PdfBytesByteSource` clamping.
- `dart_pdf_editor/test/http_byte_source_test.dart` (13): probe shape, mid-range
  reads, `openSource` integration, multi-revision doc, auth-header forwarding,
  progress, range-less full-download fallback + memory-served slices, error
  status, wrapped transport failure, cancel-before and cancel-mid-load, and
  client-ownership on `close()`, all via `http`'s `MockClient` — no real network.
- `pdf_document/test/open_source_test.dart` (4): page-tree/attributes, page
  count, content bytes, unknown-length fallback.

`dart analyze` clean; full `pdf_cos` (217) and `pdf_document` (665) suites pass.

## Left open / scope

Because the sync core needs all referenced bytes present before it runs, the
loader still fetches *all* live objects (skipping only free space, superseded
revisions, and the trailing junk past the last xref). True first-page-only
rendering for linearized PDFs — fetch the linearization dict + first-page
objects, render, then stream the rest — needs an **async** resolve path in the
core and is the natural follow-up now that `PdfByteSource` exists to build on.
No new viewer widget was added; a host wires remote loading with
`PdfDocument.openSource(PdfHttpByteSource(uri))` and rebuilds the viewer with
the resulting document.
