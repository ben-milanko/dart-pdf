# Render reuse: Type3 cell identity across the seam

Wave 2 of the measured perf pass. Each part replaces work that repeated
something the pipeline already had. Output is byte- or pixel-identical
throughout, with no GHENT_UPDATE.

## 1. Type3 cell identity across the worker seam (codec v11)

### What was wrong

`_drawType3Glyph` records a Type3 glyph once and stamps it once per
occurrence as a single-origin `PdfDrawTiledCellCommand`. Every stamp shares
the one recorded cell list (#535). Three places then threw that sharing away:

- The codec wrote `cellCommands` in full for every stamp, and the reader
  built a fresh list for each one. `CanvasPdfDevice._tiledCellPictures` is
  an Expando keyed by the cell list, so after the seam it missed on every
  stamp and re-recorded the glyph's picture per letter.
- `compactTranscriptSourceCommands.patch()` built a new list for every stamp
  of an image-bearing cell. The web worker serializes from the transcript's
  `sourceCommands` by default, and native detail records do too, so fixing
  only the codec left the bitmap-glyph pages (TeX PK fonts, each glyph a
  1-bit inline ImageMask) as fragmented as before.
- `PdfPageRenderer.collectImageRequests` walked every stamp. The UI isolate
  then built tens of thousands of requests just for `decodeImages` to dedup
  them by key.

On `test_corpora/dartpdf/type3-text-6p.pdf` that is 35,128 stamps of 156
cells. The worker's decoded record was 23.1 MB (v10), and the reader
produced 35,128 distinct cell lists.

### Fix

- **Codec v11** (`render_command_codec.dart`, `_writeTiledCellReference` /
  `_readTiledCell`). After `originsX`/`originsY`, a tiled cell writes a tag:
  - `1` means the body follows and takes the next id;
  - `2` means a u32 id of a cell already written in this record, and nothing
    else follows.

  The writer keys by list identity (`_Writer._cellIds`, an identity map).
  The reader reserves the slot with a sentinel before reading the body, so a
  cell nested inside another numbers after it, exactly as the writer counted.
  An out-of-range id, an id that names a slot still being read (a cycle), or
  an unknown tag throws `FormatException`, like the outline back-reference.

  A back-reference leaves the v10 paint-delta state (`_paintColor` /
  `_paintStroke` / `_paintAlpha`) untouched on both sides. The cell body
  advanced it once, where it was written, so a fill after a reference is
  still a delta against the last paint actually written.
- **Transcript patch memo** (`render_worker_transcript_cache.dart`). An
  identity map takes each wire cell to (patched list, first image index,
  image count). The recorder lists a cell's images again for every stamp, so
  on a revisit the memo advances `imageIndex` by the count. It checks that
  the `originalImages` range holds the same request objects as the first
  visit. If not, it throws `StateError`, which is the existing null
  (fall back to the source graph) path.
- **`collectImageRequests(distinctCells: true)`**, opt-in. It is used only by
  the decode-feeding callers: `pictureFromCommandsWithPlan` and
  `predecodeCommandImages` in renderer.dart, and the retained scene's
  `fromCommands` decode and its native-resolution check. `imageDrawPixels` (the
  motion-safe gate) and `decodedImageStats` still count every stamp, because
  changing them would change scheduling.

### Why the output is unchanged

Every stamp of a shared cell already serialized to the same commands: its
images carry the cell's own recorded transform and the page-wide budget
scale, and the decode filters (`_decodeImageInBackgroundIsolate`,
`_webWorkerImageDecodeFilter`) are stateless. The back-reference is the same
record without the repetition.

The per-occurrence `_imageBudgetScale` walk and the region plan are
untouched. Counting shared cells once there would change decode sizes
wherever the budget binds.

Re-serializing a decoded buffer gives the same bytes, which is the v10
idempotence contract; the test checks it on every page of the fixture. The
web browser-decode pass (`_withBrowserDecodedImages`) passes tiled cells
through unchanged, so web keeps the identity too.

### Tests

- `render_command_codec_test.dart` "tiled cell identity (v11)":
  - 50 stamps share one restored list, with content equal and bytes under
    a tenth of the unshared control;
  - nested slot order (B inside A, C holding both);
  - a fill and stroke after a back-reference whose cell's last paint differs;
  - out-of-range, cyclic and unknown-tag references throw `FormatException`;
  - type3-text-6p gives 156 restored cells and 35,128 stamps, under 2.4 MB,
    and re-serializes byte-identically.
- `render_worker_transcript_cache_test.dart`:
  - memo image alignment around three stamps of a two-image cell, with the
    divergent-images fallback;
  - a Type3 ImageMask glyph keeps one cell through the real transcript, and
    its record equals the native recording's.
- `image_stats_test.dart`: `distinctCells` lists a shared cell once, while
  `imageDrawPixels` still prices every stamp.

Mutation check: each test fails with the change undone. That was run for
four mutations: no writer back-reference, a reader that numbers a cell after
its body, a back-reference that resets the paint state, and no patch memo or
`distinctCells`.

### Measurements (type3-text-6p, 6 pages, ratio 2)

Deterministic:

| | v10 (main) | v11 |
| --- | ---: | ---: |
| decoded record, native | 23.08 MB | 2.26 MB |
| vector record, native | 12.90 MB | 2.21 MB |
| decoded record, web `sourceCommands` | 23.08 MB | 2.26 MB |
| restored distinct cell lists | 35,128 | 156 |

AOT, thread CPU, 6 interleaved ABAB rounds x 7 reps. Medians are ms per 6
pages; the ratio is the median of per-round ratios.

| phase | main | branch | ratio |
| --- | ---: | ---: | ---: |
| vector serialize | 43.9 | 11.3 | 0.24x |
| decoded serialize | 60.2 | 17.8 | 0.30x |
| deserialize vector | 57.5 | 13.9 | 0.25x |
| deserialize decoded | 26.2 | 12.3 | 0.48x |
| whole seam | 186.6 | 54.7 | 0.30x |

UI isolate, flutter_tester (debug JIT, so absolute times are inflated),
5 interleaved rounds x 5 reps. Each rep deserializes a fresh worker buffer,
then runs `pictureFromCommandsWithPlan` (image walk, decode, canvas replay).

| phase | main | branch | ratio |
| --- | ---: | ---: | ---: |
| deserialize | 109.3 | 14.0 | 0.12x |
| picture | 456.2 | 36.8 | 0.09x |
| raster + readback | 171.0 | 146.4 | flat |

Most of the picture gain is the canvas's cell-picture cache hitting again.

Scope: Type3 dominates only a small share of documents in a private
real-world corpus (TeX bitmap fonts, matplotlib output), but the gain for
that class is large.

Out of scope, and left alone:

- identity-aware `_weigh` and `retainedCommandGraphWeight`, so no
  record-cache capacity claim is made;
- the `_type3Cells` key hash;
- the deep-zoom first-occurrence region plan for images inside a cell.
