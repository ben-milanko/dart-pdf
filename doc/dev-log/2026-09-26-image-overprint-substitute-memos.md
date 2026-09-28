# Image-overprint substitutes: spatial memo, cheap backdrop maps, per-sample tables

Follow-up to `2026-07-25-image-overprint-colorants.md` (#604), whose "Cost"
section was left waiting for numbers, and to #755, which added the spatial
backdrop (one colorant vector per source pixel) for rasters that straddle
more than one backdrop. Output is unchanged: recorded commands and substitute
bytes are byte-identical, and the Ghent render baselines pass untouched.

## Where the time went

`pdfImageOverprintStream` builds a **substitute** raster whose samples are
already composited in ink space. Three costs were out of proportion:

1. **The spatial build had no memo.** The uniform path memoises the composite
   per packed sample tuple. #755 had to turn that memo off for spatial
   backdrops, because a key made of the tuple alone is wrong once the backdrop
   varies per pixel. With nothing in its place, every pixel of a DeviceN or
   spot image over two backdrops ran the whole pipeline: ink reading,
   `over`, and `colorantsToSrgb` through the output profile. On GWG082 page 0
   that is 224,672 pixels (two 413x272 images) for a few hundred distinct
   answers. #963's device-colour memo made each conversion cheaper (GWG082's
   cold record went from about 370 to 167 ms in the same harness), but the
   build was still about 85% of what was left.
2. **The backdrop map was hashed per pixel on every walk.** `_spatialBackdrop`
   built a `_PaletteKey` (an `Object.hash` over `PdfColorants` and
   `PdfColor`) and probed a map for every source pixel. Then
   `PdfColorantBackdropMap._hash` did another `Object.hash` per pixel. This
   runs on every interpretation of the page (collect walk, paint walk, every
   re-record), even when the substitute is already memoised. It was most of a
   warm re-record.
3. **1-, 2- and 4-bit single-component rasters had no memo at all.**
   `canPackTuple` requires 8 bits, so a sub-byte gray, Separation or Indexed
   raster over a tinted backdrop converted every sample: 0.24-0.42 s per
   megapixel (AOT), one to two seconds at the 4 Mpx cap.

## The fix, one commit each

- **Map half** (`overprint_compositor.dart`, `colorants.dart`).
  `_spatialBackdrop` keeps an `Int32List` from page palette index to local
  index (-1 until seen) and consults the `_PaletteKey` map only on each palette
  entry's first sighting. Entries that share a key (bare paper and the
  transparent sentinel are both `PdfColorants.none` on white) still resolve
  through the map on their first sighting, so they keep sharing one local
  index and the map comes out identical. `_hash` folds the indices with an
  inline `h = 0x1fffffff & (h * 31 + index)`. Equality still compares every
  index. `h` stays under 2^29, so `h * 31 + index` is an exact integer in
  dart2js and `&` truncates to the same bits as on the VM. This half carries
  all of the warm gain.
- **Spatial memo** (`image_colorants.dart`). When the map matches the image
  pixel for pixel and `canPackTuple` holds, `_buildSubstitute` memoises per
  map entry: a `List<Map<int, int>?>` of buckets indexed by the entry, each
  keyed by the existing 32-bit packed tuple. Rules:
  - **Two keys, not one combined int.** Packing entry and tuple into one int
    with shifts wraps past 32 bits on the web, which is the aliasing #451
    removed from the image colour memo. Buckets keep every key at 32 bits.
  - **Unknown cells still decline.** A bucket is created only after `at()`
    has resolved its entry, and when the dimensions match, `at()` depends only
    on the entry. So entry 0 (unknown), or an entry past the palette, never
    finds a bucket: it reaches `at()` and returns null exactly as before. Hits
    skip `at()` and its record allocation.
  - **Cleared when `spots` grows.** A composite converted before the image
    added a new spot equivalent could convert differently afterwards, so the
    buckets are dropped. Separation, DeviceN and Indexed list the same spots
    for every sample, so in practice this happens only on the first miss.
  - The memo shares the `_maxTupleMemo` budget with the uniform path.

  This half carries all of the cold gain.
- **Per-sample table** (uniform path). When `components == 1 && bits <= 8`, an
  `Int32List(1 << bits)` indexed by the raw sample replaces the tuple map
  (direct byte read at 8 bits, `rawAt` below that), and the one backdrop is
  hoisted out of the loop. This covers every 8-bit gray, Separation and
  Indexed raster, where the map probe per pixel was most of the build, and
  gives sub-byte rasters a memo for the first time. The same clear-on-growth
  rule applies.

`compositeAt` (the per-miss body, formerly inline) is now a method on
`_ImageSamples`, shared by the three walks.

## Numbers

All against origin/main after #963 and #964. AOT (`dart compile exe`, Dart
3.13.4), thread CPU time, 6 rounds run interleaved base/fix (the order
alternates each round), each round the median of 5 reps. The machine had a
load average of 15-75 from other jobs. Figures are the base and fix medians
and the median per-round ratio with its range. "Cold" opens a fresh document
per rep, which is what a page's first paint on the render worker pays. "Warm"
re-records the same document. The record path is the worker's:
`RecordingPdfDevice` + `drawPage`.

| page 0 of | cold record | ratio | warm re-record | ratio |
|---|---|---|---|---|
| GWG082 DeviceN 4c | 167 -> 19.0 ms | 0.114 [0.111-0.127] | 25.1 -> 4.8 ms | 0.192 |
| GWG080 DeviceN 6c | 272 -> 32.7 ms | 0.119 [0.116-0.127] | 37.9 -> 16.9 ms | 0.443 |
| GWG081 DeviceN 5c | 246 -> 31.5 ms | 0.127 [0.122-0.131] | 35.6 -> 14.5 ms | 0.409 |
| V50 SPOT master | 520 -> 62.1 ms | 0.118 [0.114-0.126] | 64.2 -> 22.7 ms | 0.358 |
| V50 CMYK master | 219 -> 53.4 ms | 0.243 [0.223-0.252] | 49.8 -> 27.8 ms | 0.551 |
| GWG010 CMYK OP | 25.3 -> 13.2 ms | 0.536 | 5.4 -> 3.6 ms | 0.679 |
| GWG031 gray image OP | 17.0 -> 13.3 ms | 0.779 [0.772-0.798] | 1.09 -> 1.09 ms | 0.993 |

A second run with each commit built separately (base, +map, +memo, +table,
order rotated per round) splits it cleanly: the map half moves warm to
0.19-0.55x and cold only to 0.87-0.92x; the memo takes cold the rest of the
way (a 0.13-0.28x step); the table is GWG031's 0.79x cold step and a no-op on
the spatial pages.

Controls that build no spatial substitute and no single-component one
(GWG020, GWG090, GWG190-192, the V50 ICC-CMS master, and three generated
office documents) land at 0.93-1.03x cold and warm (the low end is a 1.2 ms
record), taking the reruns with 15-41 reps per round where there was one,
and every per-round range straddles 1.0. Serialize time (`serializeCommands`
with decoded images, unchanged code) moves 0.92-1.11x, which is the same
noise.

Direct substitute builds (`pdfImageOverprintStream` over a spot backdrop,
fresh stream per rep, same interleaving):

| raster | base | fix | ratio |
|---|---|---|---|
| gray 1-bit 1024x1024 | 248 ms | 5.7 ms | 0.023 |
| gray 1-bit 1023x997 (padded rows) | 241 ms | 5.6 ms | 0.023 |
| gray 2-bit 1021x999 | 267 ms | 5.6 ms | 0.021 |
| gray 4-bit 1024x1024 | 286 ms | 5.8 ms | 0.020 |
| Indexed 4-bit 1023x1001 | 415 ms | 5.6 ms | 0.013 |
| gray 8-bit 2048x2048 | 68 ms | 15.1 ms | 0.224 |
| Indexed 8-bit 2048x2048 | 67 ms | 15.3 ms | 0.227 |
| Separation 8-bit 1448x1448 | 33 ms | 7.7 ms | 0.230 |
| GWG031 Im0 (Indexed 8-bit 615x415) | 4.33 ms | 1.07 ms | 0.243 |
| GWG031 Im1 (Indexed 8-bit 615x415) | 4.34 ms | 1.22 ms | 0.281 |
| control: CMYK 1024x1024, 64 tuples | 30.1 ms | 28.8 ms | 0.96 |
| control: CMYK 512x512, every pixel distinct | 113 ms | 112 ms | 0.95 |
| control: GWG031 Im2/Im3 (CMYK 196x149) | ~0.9 ms | ~0.9 ms | 0.99-1.02 |

dart2js (`-O3`, the web worker's flag since #964) under node, wall time for
record + serialize with decoded images, 5 interleaved rounds of 3 reps:

| page 0 of | cold | ratio | warm | ratio |
|---|---|---|---|---|
| GWG082 | 365 -> 50 ms | 0.137 | 83 -> 13 ms | 0.157 |
| GWG080 | 453 -> 61 ms | 0.134 | 98 -> 28 ms | 0.295 |
| V50 SPOT master | 941 -> 161 ms | 0.171 | 212 -> 76 ms | 0.363 |
| V50 CMYK master | 521 -> 161 ms | 0.310 | 173 -> 101 ms | 0.590 |

Reach is narrow. In the checked-in corpora, only six Ghent pages take the
spatial path (GWG010, GWG080/081/082, the CMYK and SPOT masters). The
investigation's census of a private real-world corpus (53 documents) found no
image-overprint substitute build of any kind. This is prepress and packaging
artwork: DeviceN, spot and Indexed rasters overprinting vector plates. There
it removes most of the worker's first-paint cost for the page.

## Identity

- Record + `serializeCommands(decodeImages: true)` hashes for every page (up
  to 10 per file) of all 252 `test_corpora` PDFs. Each page is recorded twice
  on one document, so both the cold build and the memoised second walk are
  covered. 407 pages hash identically between main and each of the three
  commits. The same 12 files fail to open on both (encrypted or fuzzed).
- The direct-build bench hashes every substitute: identical for all 14 cases,
  and the dart2js bench's record hashes match main's too.
- `pdf_graphics/test/image_colorants_test.dart` gained oracle tests that need
  no reference build:
  - Each spatial substitute pixel (Indexed over DeviceN, DeviceN, and
    4-component CMYK with high bytes, both modes) equals the uniform
    substitute's pixel for its own backdrop entry.
  - The memoised walk equals the unmemoised one byte for byte. The test uses a
    map one column wider than the image, which forces the unmemoised walk
    without sampling the extra column.
  - Unknown and out-of-palette cells still decline.
  - Equal maps built separately hash alike and return the identical stream,
    which is the Expando contract.
  - 1/2/4/8-bit gray and Indexed rasters at odd widths, with and without an
    inverting `/Decode`, plus a 4-bit Separation, match a per-sample reference
    (a one-pixel raster holding just that sample).

  The file also passes under `dart test -p node`. It cannot run there as
  committed, because `pdf_test_fixtures` has 64-bit integer literals dart2js
  rejects. A temporary copy with `buildClassicPdf` inlined passes all 44
  tests.
- `dart_pdf_editor` `ghent_render_test` and `overprint_render_test` pass with
  no baseline change.

## The substitute memo's cap stays a cap

The per-image substitute memo holds four backdrops and is keyed on the
`PdfColorContext` by identity. Before #963, `PdfColorContext.forDocument` made
a new context per revision, so an edit session filled the cap by its fourth
revision and the substitute was silently declined from then on. The first
proposal here was to replace the oldest entry instead of refusing. That
breaks the contract in the #604 log: one render's collect and paint walks
must get the same substitute object for the same backdrop. With five
backdrops on one page, plain replacement would hand the paint walk an object
the collect walk never decoded, and every render would rebuild all five.

A narrower version (evict only entries of a superseded context) was written
and then dropped: #963 now keeps the context across revisions unless the
output condition itself changes. Six catalog revisions applied with
`applyIncrementalUpdate` re-record GWG082 page 0 with the revision-0 bytes on
main already, and with this branch each re-record costs 4-6 ms instead of
24-27 ms.

## Gotchas

- **A per-image microbenchmark can lie about neighbours.** Running GWG031's
  four images in one process can show the two CMYK images 10-30% slower on the
  fix. The code path for those images had not changed. What had changed was
  the heap: the fix's preceding Indexed builds leave far less garbage. Run in
  isolation, or at scale (the every-pixel-distinct CMYK control), they are
  1.00x.
- **Millisecond pages need many reps on a loaded machine.** GWG020's 2 ms
  warm re-record read 1.15x slower at 5 reps per round and 1.03x at 41, with a
  per-round range of 0.84-1.28x. None of the changed code runs on that page.
- `bucket?[packed]` inside a conditional expression does not parse (`?[` reads
  as the start of a conditional); spell it `bucket == null ? null : bucket[k]`.

## Follow-ups not taken

- The warm path still rebuilds and hashes the whole backdrop map on every walk
  just to find the memoised substitute. Hoisting `_spatialBackdrop`'s
  per-row `c*v + e` term keeps the doubles bit-identical if the
  `(a*u + c*v) + e` order is preserved. Caching the map per (draw, raster
  generation) would skip it entirely, but needs an invalidation design.
- Sub-byte rasters over a spatial map still take the unmemoised walk
  (`canPackTuple` gates the spatial memo). A 16-bit single-component table
  (65,536 entries) is also possible. Nothing in either corpus needs them.
- `compositeAt`'s pack still uses `num.clamp`; #963's `clampByte` would be
  cheaper on dart2js, but it now runs once per distinct composite, not per
  pixel.

## Files

- `packages/pdf_graphics/lib/src/overprint_compositor.dart`: `_spatialBackdrop`
- `packages/pdf_graphics/lib/src/colorants.dart`: `PdfColorantBackdropMap._hash`
- `packages/pdf_graphics/lib/src/image_colorants.dart`: `_buildSubstitute`,
  `_ImageSamples.compositeAt`, `_substituteStream`
- `packages/pdf_graphics/test/image_colorants_test.dart`: the groups
  "spatial image overprint (a per-pixel backdrop map)" and "single-component
  rasters (the per-sample table)"
