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

## 2. Luminosity masks share one cached native decode

### What was wrong

`_decodeImageForCommand` sent luminosity-mask requests (the images an
`/SMask /S /Luminosity` group draws) around `PdfImageDecodeCache`:
`request.isLuminosityMask ? null : imageCache`. So every record re-decoded
every mask at native resolution and then downsampled or cropped it: the
full-page record, the thumbnail tile, each deep-zoom patch, and every page
that reuses the same mask stream. Magazine-style documents draw large gray
JPEG masks (1691x1293-class), several per page. The pure-Dart gray JPEG
decode was most of their worker record time.

### Fix

- `PdfImageDecodeCache.decode(..., luminosityMask:)` adds the flag to the
  key (`_Key`, in both `==` and `hashCode`). `get`/`put`, used by the web
  browser-codec path, stay ordinary.
- In `_decodeImageForCommand`, luminosity requests always go through one
  native-resolution entry (`_luminosityMaskPixels`), then get exactly the
  transform `decodePdfImage(luminosityMask: true)` applies (image_pixels.dart):
  - region: `cropDownsamplePdfDecodedPixels`;
  - target: `downsamplePdfDecodedPixels`;
  - neither: `_capImageResolution`, as before.

  The non-luminosity branches are unchanged: they read the same
  `imageCache` directly instead of through the old `decodeCache` alias, and
  they drop a `luminosityMask:` argument that was always false there.

### Why the output is unchanged

A luminosity decode ignores target and region for every format:
`decodePdfImage(luminosityMask: true)` is `decodePdfImagePixels(luminosityMask:
true)` followed by that same crop or downsample. Serving it from a retained
native decode is therefore the #451 reuse argument, which for ordinary images
holds only for DCT.

The flag is in the key because the two decodes of one stream are different
pictures. A luminosity decode reads the raw samples through a gray LUT,
while the ordinary decode of a DeviceGray image under a PDF/X OutputIntent
goes through the output profile.

The luminosity entry is at native size, like the DCT entries. The 64 MB
worker budget is unchanged; a 1691x1293 mask is about 8.7 MB of it.

### Tests

`image_decode_cache_test.dart`, group "luminosity masks":

- Cache level: a luminosity and an ordinary decode of one stream are two
  entries, and `get` serves only the ordinary one.
- A programmatic page under a CMYK PDF/X OutputIntent draws one gray JPEG
  both as page content and inside a luminosity group's form. Three records
  share one cache: full page (ratio 2), thumbnail (0.25), then a quarter-page
  detail patch (ratio 4). The test checks:
  - each record's bytes equal the uncached record's;
  - hit/miss counts go (0, 2), (2, 2), (4, 2), with two entries in the end;
  - the page draw and the mask ship different pixels (no aliasing);
  - the mask is 96x64, then downsampled, then a 48x32 crop.

Mutation check: dropping the flag from the key fails both tests, and
restoring the bypass fails the counters.

### Measurements

AOT, thread CPU, 5 interleaved ABAB rounds. Each rep starts a fresh
`PdfImageDecodeCache`, then does a full-page record (ratio 2) and a
thumbnail record (0.2) per page, through the native worker's decode filter.
Interpretation is outside the timing. Every record's bytes (past the
version byte) hash identically on main and the branch.

| workload | phase | main | branch | ratio |
| --- | --- | ---: | ---: | ---: |
| synthetic, 4 pages, one 1691x1293 gray JPEG mask each | full | 654.7 | 653.5 | 1.00x |
| | thumbnail | 610.2 | 20.1 | 0.033x |
| | total | 1270.5 | 673.9 | 0.53x |
| private magazine-class document, 12 pages | full | 2226.8 | 616.9 | 0.28x |
| | thumbnail | 2074.9 | 390.4 | 0.19x |
| | total | 4297.5 | 1008.3 | 0.23x |

Times are ms per pass. On the real document even the first full-page pass
gains, because the same mask streams recur across its pages. Hits go
29 -> 112 per pass, with 9 extra native luminosity entries.

Breadth: in a private real-world corpus, 1 document draws images inside
luminosity masks (153 DCT masks in its first 40 pages). Seven files in the
Ghent suite have small ones, which `ghent_render_test` exercises.

Deferred, as a separate maintainer-approved effort: the native libjpeg-turbo
accelerator (FFI build hook, per-platform packaging, pixel tolerance).
