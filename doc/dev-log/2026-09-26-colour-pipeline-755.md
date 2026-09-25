# 2026-09-26 — the #755 colour pipeline: typed ICC tables, a stable colour context, per-pixel memos

#755 made DeviceCMYK/DeviceGray and ICC sources render through a PDF/X
OutputIntent profile. That was the right fidelity call, and it put a press
profile's full A2B/B2A machinery on several hot paths at once: the profile
parse in every isolate, every incremental edit, every 1-bit gray pixel, and
every ICC RGB or 16-bit pixel. This session removes that overhead without
changing a single output byte. Five commits, all in `pdf_graphics`.

## What changed

1. **`icc.dart` — typed, deduplicated LUT tables and cached black points.**
   `IccProfile.parse` built all six A2B/B2A tables of an mft2 press profile
   as growable `List<double>`: about a million boxed doubles, ~30 ms to parse
   and ~28 MB to keep, per profile, per isolate. Every table (mft1/mft2 input
   curves, CLUT and output curves, the mAB CLUT and sampled curves, `curv`
   tables, the identity curve) is now a `Float64List` filled by a direct loop
   (`_readTable`). The stored values are the same `u16/65535` / `u8/255`
   doubles, so transforms are bit-identical. Each distinct A2B/B2A tag offset
   is parsed once (every Ghent press profile aliases A2B2 to A2B0), and
   `sourceBlackPoint`/`destinationBlackPoint` are cached per intent - they were
   recomputed on every relative-colorimetric ICC conversion through the output
   profile, about a third of each one.
2. **`color_context.dart` — keep the context across revisions; memo device
   colours.** `PdfColorContext.forDocument` was keyed on `cos.revision`, so
   every edit re-inflated (1.8 MB, over the decoded-stream cache cap) and
   re-parsed the profile in every re-rendering isolate. It is now keyed on the
   ordered list of `/OutputIntents[i]/DestOutputProfile` streams by identity.
   `deviceCmyk`/`deviceGray` memoise their result by the exact clamped input
   (4096-entry cap, stops learning when full).
3. **`image_pixels.dart` — 1-bit gray table, int-typed palette and YCCK
   clamps.** 1-bit DeviceGray converted every pixel through `deviceGray`
   (an A2B evaluation under an OutputIntent); the two possible samples are now
   converted once into an 8-byte RGBA table.
4. **`image_pixels.dart` — 1-bit gray as 32-bit words**, eight pixels per
   source byte.
5. **`image_pixels.dart`, `color.dart`, `color_context.dart` — ICC RGB memo,
   16-bit gray table, clamp helpers.** The rgbIcc per-pixel branch goes
   through the existing `_ColorMemo`; one-component 16-bit images use an
   `Int32List(65536)` table filled on demand.

The clamp helpers (`clampUnit`, `clampByte`, `clampIndex`) live in a new,
non-exported `lib/src/unit_clamp.dart`, pinned against `num.clamp` by
`test/unit_clamp_test.dart`.

## Numbers

All A/B runs: AOT (or dart2js -O2 under node) builds of origin/main (after
#959) and the branch, a fresh process per run, interleaved over at least 5
rounds (base/branch order alternating), medians; CPU is the child's user+sys
time. The machine was heavily loaded throughout (load average 50-120 on 10
cores), so the ratios are what matter.

| workload | origin/main | branch | ratio |
|---|---|---|---|
| `IccProfile.parse`, GWG169's 1.8 MB FOGRA39-class profile | 33.8 ms | 2.0 ms | 0.06x |
| 100k relative-colorimetric `toSrgb` through that profile | 83.5 ms | 23.0 ms | 0.28x |
| cold first record (open + interpret + serialize page 0), 54 Ghent files, geomean | 63.1 ms | 19.1 ms | 0.30x |
| ... its `PdfColorContext` build alone (inflate + parse), geomean | 38.7 ms | 9.1 ms | 0.24x |
| ... process maxRSS, geomean | 95 MB | 52 MB | 0.55x |
| live heap holding 4 parsed profiles (forced GC) | 129.7 MB | 43.5 MB | 0.34x |
| dart2js profile parse / per-colour `toSrgb` / `fromPcs` | 5.7 / 52.5 / 41.8 ms | 2.1 / 32.6 / 29.1 ms | 0.38x / 0.62x / 0.70x |
| per-edit `forDocument` + first colour, GWG169, 8 annotation edits | 57.3 ms | 0.01 ms | - |
| RSS after those 8 edits | 231 MB | 56 MB | 0.24x |
| live heap after 6 annotation edits, GWG169 (forced GC) | 89.7 MB | 40.3 MB | 0.45x |
| cold first record: V50 CMYK / GWG082 / GWG060 | 395 / 330 / 49 ms | 212 / 165 / 19 ms | 0.54x / 0.50x / 0.39x |
| warm re-record: GWG060 / V50 CMYK | 15.6 / 58.6 ms | 11.5 / 49.1 ms | 0.74x / 0.84x |
| JBIG2 book, 8-page worker decoding record | 1378 ms | 321 ms | 0.23x |
| ... decoding its 1-bit images alone | 1199 ms | 158 ms | 0.13x |
| JBIG2 book, `perf_sweep --measures decodeImages`, all 32 pages | 5386 ms | 586 ms | 0.11x |
| GWG173 worker decoding record | 78.9 ms | 6.2 ms | 0.08x |
| JBIG2 book, Flutter raster (benchmark_render_test, 4 pages) | 615 ms | 227 ms | 0.37x |
| dart2js JBIG2 book page record | 407 ms | 134 ms | 0.33x |
| dart2js real-world pages with large Indexed images | 357 / 964 ms | 190 / 843 ms | 0.53x / 0.87x |
| GWG161 (ICC RGB) cold image decode | 4341 ms | 74 ms | 0.017x |
| V50 ICC-CMS cold image decode | 6862 ms | 441 ms | 0.064x |
| GWG182 (16-bit ICC gray) cold image decode | 1352 ms | 123 ms | 0.091x |
| GWG183 (16-bit DeviceGray) cold image decode | 58.7 ms | 16.5 ms | 0.28x |
| all 54 Ghent files (3 pages each), cold image decode total | 14.1 s | 1.44 s | 0.10x |
| controls: image-scan-4p / photo-jpeg-6p process CPU | - | - | 1.03x / 1.03x |
| dart2js GWG161 page record | 9808 ms | 221 ms | 0.023x |

Per commit: the typed tables recover most of the parse time and memory on
their own; the context memo adds 0.82-0.84x on the cold GWG082 and V50 CMYK
first records (and fixes the edit path); the word writes, measured against the
table-only commit, are 0.82x on the AOT JBIG2 record (0.72x on its 1-bit
decode) and 0.79x on the dart2js page record (process CPU 0.86x) - so they
stay; the ICC RGB memo and 16-bit table are 0.28x of the Ghent image-decode
total on top of everything before them.

Two numbers that did not move the right way, for the record:

- Live heap after 6 edits is 0.45x, not below 0.4x: the base still holds two
  boxed profiles (about 60 MB of `_Double` and `_List`), the branch one typed
  profile, and most of what is left is the document and its revisions.
- `perf_sweep`'s peak RSS over the 32-page JBIG2 decode rose 59 -> 67 MB
  (1.14x, every round), while the 8-page record bench's fell 74 -> 65 MB. The
  1-bit path allocates nothing new and retains nothing, so this is most likely
  GC timing: decoding 9x faster leaves the collector less time to reclaim one
  15 MB page surface before the next is allocated.

Reach: every PDF/X or print-ready document with a CMYK OutputIntent (all 54
Ghent files; none of the documents in a private real-world corpus), plus every
JBIG2 scan and every Indexed image on the web worker regardless of intent.

## Identity checks

- ICC transforms: `toSrgb`/`toPcs`/`fromPcs` and both black points over the 23
  distinct profiles in the test corpora and a private real-world corpus, 4
  intents x 400 samples, hash identically. Profiles truncated at 20-80% still
  parse to null.
- `tool/hash_image_decodes.dart` over `test_corpora`, the private corpus and
  the generated JBIG2 book (`gen_jbig2_scanned_pdf.dart ... 32 900 1700 2200
  20260725`): all 23,928 hash lines identical to origin/main.
- Record + decoded-image hashes of every Ghent page identical to origin/main,
  and the serialized records of every A/B above (AOT and dart2js) hash
  identically on both sides.
- Ghent across 6 annotation edits with a content record after each: 54/54 files
  hash identical to revision 0, and revision 0 identical to origin/main
  (origin/main: 43/54 stable, see below).
- `ghent_render_test` (forced `GHENT_COMPARE=1`) and `overprint_render_test`
  pass with no baseline change; `tool/perf.sh gate` counters are exactly
  unchanged.

## Gotchas

- **A closure in `IccProfile._parse` can pin the whole profile.** The returned
  transforms close over `_parse`'s scope, and the VM keeps one context per
  scope. A `putIfAbsent(() => _Lut.parse(bytes, ...))` put `bytes` in that
  context and kept every decoded profile (1.8 MB each) alive for as long as the
  profile lived. The dedupe uses `containsKey` instead, and a comment says why.
- **Type every table, not just the CLUT.** With only the CLUT typed,
  `_Curve._sample` sees two list types and goes polymorphic, which measured
  slower per pixel on dart2js than all-boxed.
- **The parse stays eager on purpose.** Lazy per-intent tables are another
  2 ms and 5 MB, but they move a truncated table's `RangeError` from parse time
  (where `IccProfile.parse` returns null) to the first conversion, inside the
  interpreter, which only catches `Exception` - the page render aborts, and
  later calls silently fall back to another intent's table. Laziness needs an
  allocation-free structural validator first. Each typed table's extent is
  checked against the input before allocation, so a hostile header cannot make
  the eager parse allocate more than the file could hold.
- **`num.clamp` on dart2js** is three `compareTo` calls, and its static type is
  `num` for int bounds; storing that into a `Uint8List` palette made dart2js
  treat the palette's elements as `num` and every per-pixel store from it a
  checked, out-of-line `$indexSet`. `clampUnit` maps NaN to 1.0 and -0.0 to
  0.0 exactly like `clamp`; `clampIndex` answers `lo` instead of throwing when
  `lo > hi` (only an ICC CLUT with no grid points gets there, and its empty
  table throws on the next read anyway).
- **The revision-keyed context was also a correctness bug.** Array colour
  spaces are cached per COS object and keep the context they were parsed
  under, and `image_colorants.dart`'s substitute memo compares contexts by
  identity with 4 entries per image. After the fourth edit an image-overprint
  substitute silently stopped being built, and 11 of the 54 Ghent files drifted
  from their revision-0 rendering. Identity reuse fixes both; the list compares
  every intent's stream, so an unusable first intent cannot mask an edit to a
  later one.
- **Word writes without an Endian branch:** read each table entry back through
  `Uint32List.view(table.buffer)` and it is already in host order, exactly how
  a word store lays it into the output. The output view needs a 4-aligned
  offset, which the freshly allocated RGBA buffer has.

## Deliberately not done

- **PDF/A gate.** Narrowing the `outputProfile != null` gates to 4-channel
  profiles would let a PDF/A sRGB OutputIntent keep the #531 bypass
  (`rgb8Transform`, `isSrgb`) and the platform JPEG codec for gray - but it
  restores pre-#755 output (up to 1 LSB off today's), so it needs its own
  reviewed change.
- **`_scaledGray1Region` ignores the OutputIntent**, so a downscaled
  CCITT/Flate 1-bit image in a PDF/X file renders differently from its full
  decode. Fixing it (and then routing JBIG2 through the packed kernels) changes
  output.
- Lazy LUT tables (see above); a cross-document profile cache (only worth it
  now that a profile is ~7 MB, and only byte-bounded with capacity 1);
  caching mesh-shading vertex colours per `PdfShading`.

## Files

- `packages/pdf_graphics/lib/src/icc.dart` (`_readTable`, `_Lut`, black-point
  slots), `lib/src/unit_clamp.dart`
- `packages/pdf_graphics/lib/src/color_context.dart` (`forDocument`,
  `_outputProfileStreams`, `_ProcessColorKey`)
- `packages/pdf_graphics/lib/src/image_pixels.dart` (`_toRgba` 1-bit and
  rgbIcc branches, `_toRgba16`, `_indexedPalette`, `_decodeLut`,
  `_decodeDctCmyk`)
- Tests: `test/icc_test.dart`, `test/unit_clamp_test.dart`,
  `test/color_context_test.dart`, `test/image_pixels_test.dart`
