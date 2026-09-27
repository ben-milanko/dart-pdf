# CAD raster masks: an instrument that sees them, then two exact kernels

The image-heavy CAD fixture (#419) was profiled from a real 62 MB
cathodic-protection sheet, but it did not draw what the sheet draws, and the
one perf measure that decodes images decoded at native size. So the slowest
real path on that sheet - masked colour tiles decoded to their display
target - was invisible to every sweep, and the stencil kernel (#949) was
tuned against stencils with the wrong polarity. This session fixes the
instrument first and then uses it for the kernels.

## The instrument

**`decodeImagesAtTarget` (perf_sweep).** An opt-in measure that records each
page with `RecordingPdfDevice` and times exactly the render worker's decoding
record: `serializeCommands(decodeImages: true, maxImagePixelRatio: R,
pageRasterPixels: pdfPageRasterPixels(cropBox, R), imageCache: fresh,
compactStateScopes: true)`, with R from the scenario key `imageRatio`
(default 0.5). Besides `decodeAtTargetMs` it reports the PdfPerf call counts
of `imageDecode` / `imageDownsample` / `imageColorConvert` / `imageAlpha` for
one pass, which are deterministic, so a changed decode path shows even where
the time is noise. It lives in its own child script
(`tool/perf_record_images.dart`) because `tool/perf/backfill.sh` grafts
`perf_sweep.dart` onto commits much older than the record-path APIs; the
native-size `decodeImages` measure is untouched.

**The sheet as drawn (`PdfTileSpec.masked`, `gen_cad_image_pdf.dart
faithful2`).** #419's profile counted the sheet's 462 `/Mask` stencil streams
as drawn ImageMasks ("923 ImageMask, smasks 0"). The sheet actually draws 925
images: 462 ImageMask stencils, 445 DeviceRGB and 17 Indexed 2048x1754 tiles
each under a same-size 1-bit `/Mask`, and one 3x1 Indexed image. Its stencils
use `/Decode [1 0]`, paint ~1-1.5% of pixels, and only ~1.3-1.8% of their
bytes hold a painting bit; the old hatch sets its bits under `/Decode [0 1]`,
so it paints 94%. `masked` tiles build their plane from a few full-width rules
plus bands of 18x9 symbol blocks, placed by a per-tile generator (never the
shared one, so colour tiles and vector ops are unchanged), with a
`maskBlank` option for the fully transparent ones the sheet also has.
Existing profiles, the Patrol builder and the #419 file are byte-identical
(checked by generating each with the base and the new code).

| | real sheet (a private real-world corpus) | faithful2 fixture |
|---|---|---|
| draws | 462 IM / 445 RGB+Mask / 17 Idx+Mask / 1 Idx | same |
| stencil paint / busy bytes / blank rows | ~1-1.5% / ~1.5% / 83% | 0.9% / 1.4% / 83% |
| record r0.5, origin/main, thread CPU (5 rounds) | 21.1-22.6 s | 1.05x the sheet (1.04-1.07) |
| imageDecode/Downsample/ColorConvert/Alpha calls | 925/925/463/462 | 925/925/463/462 |
| bytes inflated | 5.271 GB | 5.272 GB |

A first prototype without the 3x1 Indexed image gave 924/924/462/462; with
it the fixture's signature is the sheet's.

New scenarios: `cad-images-v2-record` (full size, local; ~70 MB, ~18 s to
generate) and `cad-images-v2-quarter-record` (231 tiles in the same order;
nightly). The #419 scenario's note now says what it is.

**Cold render mode (`PDF_BENCHMARK_COLD=1`).** `benchmark_render_test`
clears `CanvasPdfDevice`'s text layout caches before every file of every
pass, so `renderMs` is a first paint. `PDF_BENCHMARK_DIR` also takes a file or
a comma-separated list now. The nightly runs `substituted-text-cold-render`
(cad-labels-6p + the new prose fixture, 1.5x, 3 pages), and `render_trend`
picks it up under its own name. Measured with the bench grafted onto each
commit (best of 3 cold passes, flutter_tester, 2 rounds):

| commit | cad-labels-6p | prose-report-20p |
|---|---:|---:|
| 335222ca (before #649) | 64.9 / 65.6 ms | 13.5 / 14.7 ms |
| 8793afb3 (#649) | 169.5 / 166.5 ms (2.6x) | 53.7 / 55.8 ms (3.9x) |
| this branch | 71.2 / 74.3 ms (1.10x) | 23.6 / 26.2 ms (1.8x) |

So the mode catches #649 at 2.6x. HEAD is not back at or below 335222ca:
cad-labels is ~1.1x, consistent with #962's note that composed pieces add
raster draw calls, and real prose is still ~1.8x its pre-#649 cold cost.

**Real-vocabulary prose (`prose-report-20p.pdf`).** The text documents in
`test_corpora/dartpdf` draw every word from 26, so any word or piece cache
holds the whole vocabulary after a line. The new generator walks an order-2
word chain over ~1,550 words of repo-authored English (842 distinct tokens)
and sets it one `Tj` per line in unembedded Helvetica. Every other corpus file
regenerates byte-identical (annotated-10p already differs from its committed
bytes at origin/main; not touched).

## Phase A: blank words in the stencil coverage kernel

`_scaledImageMaskRegion` still touched every source byte, so a thumbnail cost
as much as native size. It now steps over blank paper a 32-bit word at a time
when the samples are 4-aligned (a platform decompressor's samples may not be;
the byte walk stays for those and for row heads and tails), hoists the
polarity (`paint = byte ^ flip`), and counts whole-byte cells with one piece
per byte. Non-blank bytes take the unchanged piece/popcount path, so the
counts are those of the byte walk. All-blank words read the same in either
byte order, and `Uint32List` is exact under dart2js.

AOT, thread CPU, 150 real stencils, 5 interleaved rounds (base = origin/main):
div 4 0.66x, div 16 0.36x (136 -> 49 ms), div 32 0.30x. The fixture's
stencils give 0.37x at div 16. A brute-force test now covers widths to 400,
sparse ink, every buffer offset mod 4, and whole-byte cells.

## Phase B: an exact masked region kernel

`decodePdfImagePixelsRegionScaled` declined anything masked, so a deep-zoom
slice of a masked tile decoded, composited and premultiplied the whole native
image, then cropped and box-filtered it. `_scaledMaskedDirect8Region` does the
same arithmetic in one pass over just the region: a single-Flate 8-bit
DeviceRGB/DeviceGray base with identity /Decode, under a same-size 1-bit
stencil `/Mask` (its /Decode honoured) or a same-size 8-bit `/SMask` without
/Matte. Each cell sums what the composite would have produced (masked out: 0;
opaque: the colour; partial: `c * a ~/ 255`) and divides like
`downsamplePdfDecodedPixels`. A stencil walks only its visible bits, skipping
blank words and bytes, which is most of the win on the CAD sheet. Declines:
DeviceGray under an OutputIntent (`_toRgba` maps it through the output
condition), cells whose 32-bit column sums could overflow (they fall back;
never `Int64List`, which dart2js lacks), region requests outside the image
(the fallback returns null rather than clamping), `samplesAreDecoded`, and
the whole-image scaled call: whole-image downscales keep their current path,
whose output is not the full decode at mask edges. Bracketed with PdfPerf
`imageAlpha` and `imageDownsample` (one fused pass records both). A same-size
slice (deep zoom at or past native resolution) writes each premultiplied
sample straight out instead of summing it into a column and dividing by one.

Output is byte-identical: 2,640 decoding-record hashes (whole page at 0.5/1/2
and deep-zoom regions at 2 and 8) over Ghent, pdf.js, `test_corpora/dartpdf`,
the quarter fixture and the real sheet matched origin/main, and again after
the dart2js fix and the same-size path below. Parity tests against
`cropDownsamplePdfDecodedPixels(decodePdfImagePixels(...))` (24 randomized
images, same-size slices with unaligned edges, a masked gray image under an
OutputIntent, decline shapes, the overflow guard) pass on the VM and under
`dart test -p node`.

Region slices (centre quarter of each masked RGB tile, every inflate paid),
AOT thread CPU medians, 5 interleaved rounds vs origin/main: real sheet 1:1
1358 -> 149 ms (0.11x), 1:2 0.16x; the 27 Mpx soft-masked underlay 1:1
326 -> 107 ms (0.33x), 1:2 0.37x; a dense 2048x1754 soft mask 1:1 0.76x, a
mostly visible stencil /Mask 1:1 0.65x.

**dart2js.** The web render worker runs this kernel as dart2js output: its
browser inflate declines /SMask and 8-bit /Mask images, so they take the
portable path. The first cut assigned the two decoded sample arrays inside
the kernel's `try`, and dart2js types a `try`-assigned local only by its
declaration, so all 14 sample reads compiled to `J.$index$asx(...)`
interceptor calls instead of native typed-array indexes. The CAD tiles hid it
(the blank-word skip reads ~1% of their stencil bytes); a review caught it on
soft masks, where that cut made the underlay's 1:1 slice 6.7x slower on the
web than origin/main. The samples now
come from `_decodeMaskedSamples`, whose record destructures into typed
locals, and `test/image_kernels_dart2js_test.dart` compiles a probe at -O3,
unminified, and fails if either masked kernel indexes through an interceptor
(it first checks that a `try`-assigned probe still does, so the check cannot
pass vacuously). With native reads the 1:1 underlay slice was still 1.25x
origin/main when its planes were resident, because `~/` is a checked call
under dart2js and a same-size slice paid four per pixel; the direct write
above removed that.

dart2js -O3 under node, per image, median of 5 interleaved rounds. "Resident"
keeps the inflated planes in the decoded-stream cache, as the worker's seeded
samples are for a deep-zoom slice; "inflate paid" turns that cache off, as for
a page's first record. The dense cases are synthetic 2048x1754 RGB images on a
one-page PDF, whole images decoded at the worker's r1.0 target (~1/3.3):

| case | origin/main | first cut | this branch | vs origin/main |
|---|---:|---:|---:|---:|
| underlay slice 1:1, resident | 230 ms | 1,550 ms | 47 ms | 0.20x |
| underlay slice 1:2, resident | 259 ms | 1,390 ms | 105 ms | 0.40x |
| underlay slice 1:1, inflate paid | 365 ms | 1,676 ms | 193 ms | 0.53x |
| dense soft mask slice 1:1 / 1:2, resident | 38 / 44 ms | 201 / 181 ms | 7.7 / 13.7 ms | 0.20x / 0.31x |
| mostly visible stencil /Mask slice 1:1 / 1:2 | 382 / 388 ms | 144 / 126 ms | 6.1 / 12.9 ms | 0.02x / 0.03x |
| real sheet tile slices 1:1 / 1:2, inflate paid | 425 / 426 ms | - | 27 / 35 ms | 0.06x / 0.08x |

Every slice hash equals origin/main's under node too.

`render_command_codec_test`'s SMask deep-zoom test assumed the fast path
declines every soft-masked image; its mask is now a different size from its
image, which only the general path resamples, so it still tests the fallback
with the same expected pixels.

## Nightly budget

Locally (loaded M-series machine) the whole of `nightly.sh` ran 1,000 s. New
work: generating the quarter sheet 6.4 s, its `decodeImagesAtTarget` sweep
15 s, the cold render bench 5 s. Removed: generating the #419 sheet, 19.1 s
(`gen_perf_docs.sh --nightly`). Net about +7 s here; hosted runners are
slower, but that stays far inside the ~5 min of headroom in the 45-min sweep
step. No workflow timeout changed, and counters.json is untouched.

The nightly `dartpdf-corpus` vm-sweep sweeps all of `test_corpora/dartpdf`, so
`prose-report-20p.pdf` joins its aggregate on the day this lands: a step in
that series' p50/p95 on that date is the new file, not a regression.

## Gotchas

- Under dart2js, never read a hot loop's typed array from a local assigned
  inside a `try`: decode in a helper and destructure its result. The
  interceptor calls it costs do not show on the VM at all.

- flutter_tester answers every unregistered font family with its kern-free
  test font (#962), and CI registers no system Helvetica, so
  `substituted-text-cold-render` trends the test-font path of the shaping and
  placement code, not production faces.
- The two cad-images-v2 files live in their own cache directories: a vm-sweep
  scenario sweeps its whole corpus directory, and `cache/cad-images` already
  has two readers.
- `gen_perf_docs.sh` only generates missing files, so a changed generator
  needs a new cache name; `--nightly` skips everything the nightly does not
  read.

## Not done

Browser inflate for masked 8-bit images on the web worker, `/Matte`,
Indexed-8 through a palette LUT (the sheet's 17 Indexed+Mask tiles), and the
unmasked `_scaledGray8Region` OutputIntent hole. The general full decode's
`_toRgba` also indexes through interceptors under dart2js (17 sites in an -O3
build, already on origin/main); worth a look, measured on its own.
