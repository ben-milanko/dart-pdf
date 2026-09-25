# Render-command wire format v10: paint dedup and path blocks

The render-command codec (`packages/pdf_graphics/lib/src/render_command_codec.dart`)
moves every worker record to the UI isolate: the worker serializes, the UI
deserializes, and on native the strip binner round-trips it once more. Format
9 had two costs on vector-heavy pages:

- **Paint repeated on every command.** Each fill and stroke carried its full
  colour (3 x f64), stroke (width, cap, join, miter, the dash array and phase)
  and alpha. That is 62 of a solid 2-point stroke's 85 bytes, and a CAD sheet
  strokes hundreds of thousands of paths with a handful of pens.
- **Paths went out one scalar at a time.** Each verb was interleaved with its
  float32 coordinates, and every scalar paid for `_ensure` plus a big-endian
  `ByteData` call. The reader made two passes, the first only to size the
  coordinate list. `_readPath` was 57-81% of UI-side deserialize on CAD pages.

## What changed

Format version 9 -> 10 (two commits, plus this note):

1. **The version byte is checked.** `deserializeCommands` and
   `deserializePageText` used to `assert` it, so a release build would read a
   buffer from another version as its own. Both now throw `FormatException`.
   This can happen in the field: a stale cached or self-hosted worker script,
   or `dart_pdf_editor` paired with an older `dart_pdf_editor_assets`. Every
   caller already catches and falls back to a local render.
2. **Paint dedup.** A fill or stroke now writes one flags byte before its
   paint: bit 0 new colour, bit 1 new stroke, bit 2 new alpha, and bits 4-5
   hold the fill rule. Only what changed since the previous fill or stroke
   follows. The writer compares by value, bit-exactly (`0.0` and `-0.0`
   differ, and NaN never matches, so it is resent), with an identity fast
   path. The reader hands back the previous `PdfColor` or `PdfStroke`
   instance. Both types are immutable and nothing keys on their identity or
   mutates `dashArray`. The state is sequential and starts fresh for each
   buffer, and nested soft-mask and tiled-cell lists advance it in write
   order, because both sides walk them depth-first inline.
3. **Path blocks.** Each path is written as: u32 verb count, the verb bytes,
   zero padding to a 4-byte boundary counted from the buffer start, then the
   coordinates as one contiguous float32 run in host byte order. Producer and
   consumer share a machine and nothing persists a buffer, so host order is
   safe.
   - The writer stores coordinates through a `Float32List` view of its own
     buffer. `writePdfPathBlock` in `path.dart` copies packed paths straight
     out of their typed storage. It is hidden from the package barrel
     (`export 'src/path.dart' hide writePdfPathBlock`), so `PdfPath`'s packed
     storage never becomes public API. It derives the coordinate count from
     the verbs, not from the storage length.
   - The reader builds one whole-buffer `Float32List` view per decode, and
     only when the buffer starts 4-byte aligned. It then copies each path
     with `setRange` at 64 or more coordinates and element-wise below that.
     An unaligned buffer (a view into a larger one) falls back to
     `ByteData.getFloat32`.
   - Verb tags and the derived coordinate count are validated in the same
     loop that copies the verbs, and bounds are checked before anything is
     allocated. A corrupt block still throws `FormatException` in the decoder
     (the #451 contract) rather than failing later in `PdfPathCursor` during
     replay.

The public `serializeCommands`/`deserializeCommands` API is unchanged.
Re-serializing a decoded buffer still yields the same bytes.

## Evidence

The A/B used AOT executables built from origin/main and from this branch,
with Dart 3.13.3. The two runs alternated ABAB (process order flipped each
round): 7 rounds x 9 reps on the checked-in corpus, 5 rounds on the heavy
sheets. Each figure is the median thread-CPU time over all pages of the
workload. The records use the worker's serialize options (`compactStateScopes`,
`imagePlaceholders`, ratio 2). The machine was heavily loaded (load average
60-90 on 10 cores), which is why every clock is thread CPU.

| workload | bytes | serialize | deserialize |
|---|---:|---:|---:|
| cad-wide (1 page, ~850k commands) | 0.649x | 325 -> 166 ms (0.51x) | 333 -> 253 ms (0.76x) |
| cad-sheet-8p | 0.839x | 3.55 -> 1.74 ms (0.49x) | 1.68 -> 1.01 ms (0.60x) |
| plan-set-16p | 0.836x | 36.3 -> 16.8 ms (0.46x) | 12.0 -> 7.9 ms (0.66x) |
| diagram-dense-3p | 0.836x | 21.6 -> 11.7 ms (0.54x) | 8.15 -> 5.91 ms (0.73x) |
| hatch-sections-4p | 0.998x | 0.95x | 0.99x |
| text-report-40p | 1.000x | 1.01x | 1.00x |
| letterhead-report-40p | 1.000x | 1.01x | 1.02x |
| private real CAD sheet A (1 dense page) | 0.538x | 118 -> 41 ms (0.35x) | 85 -> 53 ms (0.62x) |
| private real CAD set B (30 pages) | 0.881x | 275 -> 101 ms (0.37x) | 123 -> 48 ms (0.39x) |

Text and image pages are flat, and every vector page gains on both sides.
Paint dedup carries the stroke-dense sheets, while path blocks carry the
fill-dense and plan pages.

**dart2js** (the web main thread deserializes every worker record). This was
an in-process A/B: the origin/main codec was copied in as a second library,
compiled with `dart compile js`, run under node, interleaved, with 5 processes
x 9 reps. Numbers are the median paired ratio (v10/v9):

| workload | -O2 serialize | -O2 deserialize | -O4 serialize | -O4 deserialize |
|---|---:|---:|---:|---:|
| cad-sheet-8p | 0.91 | 0.91 | 0.86 | 0.87 |
| diagram-dense-3p | 0.92 | 0.89 | 0.80 | 0.84 |
| plan-set-16p | 0.90 | 0.99 | 0.85 | 0.91 |
| text-report-40p | 0.98 | 1.01 | 1.02 | 1.02 |
| private real CAD sheet A | 0.84 | 0.65 | 0.80 | 0.71 |

Web deserialize does not regress on any vector workload. The web gain is
smaller than native, because V8 already inlines `DataView.getFloat32`.

**Heap** (the shared profiler's `--alloc` live heap after a forced GC, one
decoded record of the dense real CAD sheet, ~285k commands). Total live heap
went from 222.3 to 192.7 MB. That total includes the parsed document and the
harness's own copy of the recording (133.1 MB in a control run that keeps
nothing). The decoded command graph itself went from 89.2 to 59.6 MB
(0.67x): decoded `PdfStroke` instances fell from ~231k to ~500, and ~230k
dash-array lists and ~285k `PdfColor`s went with them. This graph is what a
UI retained scene and the worker transcript cache hold.

**Identity.** The check tool records each page, serializes it with both
codecs, decodes each buffer, and re-encodes both decodes with the v9 encoder.
The bytes were identical on 1,226 pages of 296 documents: all of
`test_corpora` (ghent, pdfjs, reflow, dartpdf; the first 40 pages of each),
the private real-world corpus, and the generated perf-cache sheets. That
covers both the worker options and the plain lossless options. Twelve
documents could not be opened at all (password or parse errors), on either
version. v10's own decode -> encode is idempotent on all of them too. Total
wire bytes: 0.919x on `test_corpora` and 0.825x on the private corpus.

## Gotchas

- **dart2js hates per-path typed-array views.** An earlier variant wrote
  little-endian bytes and copied each path with `setRange` from a
  `Uint8List` view. That builds about three typed-array objects per path and
  regressed dart2js decode 1.1-1.9x on typical CAD and diagram pages. The
  fix is one whole-buffer view per decode, with element-wise copies for short
  paths. Keep the 64-coordinate threshold on both reader and writer.
- **The alignment pad is relative to the buffer start**, not the backing
  store. A buffer at an unaligned `offsetInBytes` still decodes correctly,
  just through `ByteData`. The region index copies its nested clip buffer
  to offset 0 (`r.bytes()`), so it takes the fast path.
- **Don't claim cache capacity.** Smaller wire bytes do not let
  `PdfWorkerTranscriptCache` or the strip binner's command cache hold more
  pages, because both are weighted by command slots, not bytes. The real
  memory win is the shared paint instances (above), plus a smaller
  `takeBytes` copy and transfer.
- **No replay speed-up from shared instances.** `CanvasPdfDevice`'s paint
  cache already compares by value, so identity hits change nothing there.
- **Prior art.** `2026-07-11-command-scope-compaction.md` notes a reverted
  "colour/stroke cache prototype". That was a hashed decode cache. This
  change uses a sequential same-as-previous flag with no hashing, and it
  measured faster on both AOT and dart2js.
- A version bump now matters at runtime. If the layout changes again, bump
  `_formatVersion`. A stale worker then falls back to a local render
  instead of misparsing.

## Not done here

- Suffix-only progressive partials (#564): each doubling partial still
  re-ships the whole prefix, so the UI decodes about 2x the final bytes on
  the densest sheets. That change is independent of the codec.
- Weighing the transcript cache by bytes, if the goal is more pages per
  cache.
- Tightening `dart_pdf_editor_assets`' constraint on `dart_pdf_editor` to
  lockstep. The version check makes a mismatch safe, but not fast.

## Pointers

- `packages/pdf_graphics/lib/src/render_command_codec.dart`: `_formatVersion`,
  `_checkFormatVersion`, `_writePath`/`_readPath`,
  `_writeFillPaint`/`_writeStrokePaint`/`_readPaint*`, `_Writer._floats`,
  `_Reader._floats`.
- `packages/pdf_graphics/lib/src/path.dart`: `writePdfPathBlock` (hidden from
  `pdf_graphics.dart`).
- `packages/pdf_graphics/test/render_command_codec_test.dart`: the
  version-mismatch test and the `wire format v10` group (dedup through
  soft-mask and tiled-cell nesting, bit-exact `-0.0`, spare packed
  coordinates, unaligned buffers, corrupt blocks failing at decode).
