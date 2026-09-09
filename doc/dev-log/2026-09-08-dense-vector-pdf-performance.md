# Dense vector sheet: parsing, zoom replay, and first-drag latency

The supplied single-page engineering sheet is 3.94 MB on disk, but expands to
31.96 MB of content, 1,096,964 operators, and 3,504,274 numeric tokens. Its
421 × 269 pt page carries 705,104 path segments and 13,452 text runs. The PDF
is a local benchmark input and is not included in the repository.

Three changes address measured costs:

- The COS lexer accumulates numeric values while scanning their boundaries,
  avoiding a second byte pass. Existing integer/decimal precision limits and
  malformed-input fallback behavior stay intact.
- A retained scene caches native path geometry across zoom and detail replays.
  Fill rules have separate entries; transforms, paints, dashes, clipping, and
  drawing order remain unchanged. Each scene has a 32 MiB estimated geometry
  budget and a 65,536-entry cap, participates in global memory-pressure
  eviction, and releases its cache on disposal. Direct interpretation does
  not retain one-shot paths. Once a path would exceed either limit it is
  returned uncached, preserving a reusable subset for repeated scans of pages
  larger than the cache.
- After a heavy visible page paints and the viewport/render scheduler stays
  idle for 500 ms, the viewer prepares its text through the worker, one focused
  page at a time. Motion cancels the pending warm. Search shares pending
  requests and promotes them to foreground priority; stale
  revision replies cannot populate the current cache, and speculative failure
  never falls back to the UI isolate. A gesture made before warming completes
  can still pay the existing synchronous extraction cost.

## Measurements

Local native Flutter test engine, seven measured pairs per scale after warmup,
with alternating cached/uncached order and identical commands and decoded
images. Times below are medians in milliseconds. Raster timing includes RGBA
readback; these are renderer measurements, not browser or full-app latency.

| Scale | Rebuild paths | Reuse paths | Raster before | Raster after |
| --- | ---: | ---: | ---: | ---: |
| 2× | 102.56 | 57.31 | 86.21 | 84.84 |
| 4× | 99.23 | 54.85 | 101.71 | 97.43 |
| 8× | 108.75 | 55.44 | 126.54 | 125.43 |

At 4×, replay work falls 45%, and replay plus raster falls from approximately
201 ms to 152 ms (24%). Most of the gain is in replay; rasterization remains
the larger phase. The scene retained 47,620 paths, estimated at 30,571,520
bytes, with zero evictions during this final run, which includes the cache
follow-up below.

A separate same-process streaming-parser A/B, alternating the original and
optimized lexer for ten runs each, improved median parsing from 246.46 ms to
208.52 ms (15.4%). Every one of the file's 4,679,417 tokens matched the original
lexer exactly, including types, offsets, signed zero, and byte values.

Fresh local text extraction measured 625 ms cold and 426–430 ms after VM
warming. Preparing it on the worker removes that main-isolate work from
ordinary first interaction once the warm result is ready.

## Reproduction and verification

From `packages/dart_pdf_editor`:

```sh
PDF_PATH=/absolute/path/to/dense.pdf \
  fvm flutter test --no-pub test/benchmark_path_replay_test.dart --reporter expanded
```

Optional `PDF_PAGE` selects a zero-based page, `PDF_BENCHMARK_SCALES=2,4,8`
chooses scales, and `PDF_BENCHMARK_OUT=/tmp/replay.json` saves measurements.
The first pair at each scale verifies identical RGBA pixels.

Validation completed:

- Exact pixels at 2×, 4×, and 8× for cached versus uncached replay.
- Before/after worker-rendered PNG at 4× is byte-identical.
- All 376 pdf_cos tests, including numeric boundary regressions.
- 50,012 original/optimized numeric cases under dart2js `-O2` and Node.
- 137 viewer, search, worker, hover, and touch-selection regression tests.
- 11 native-path-cache and retained-scene tests, including fill rules,
  dashed strokes, clipping, eviction, and memory pressure.
- Ghent and PDF.js interpretation corpora: 225 tests.
- Ghent and PDF.js rendering corpora: 218 tests; no baseline updates.

PR review follow-up: idle-window cancellation and native/browser priority
promotion have regression coverage. Worker queue promotion forwards through
both cache and pool wrappers without launching a duplicate extraction.

The wide-CAD regression also exposed quadratic eviction in the shared cache:
finding the newest map key scanned the entire cache, and finding the oldest
scanned deleted slots. A linked recency list now keeps ordinary touches and
evictions constant-time. In a local overflow microbenchmark, 32,768 insertions
at capacities of 8,192, 16,384, and 32,768 took 1,210–3,361 ms before and 5–8 ms
after. Memory limits and resource ownership are unchanged. Focused tests cover
repeated turnovers, nullable keys, remap collisions, and reentrant builders.

A synthetic 160,001-command replay visits 88,084 native paths, beyond the
65,536-entry limit. Stable admission retains that many paths with no churn:
458,752 hits and zero evictions across the measured replays. Cached replay
measured 1,113.3 ms versus 1,131.9 ms uncached (1.6% less), with 2.5% less
replay plus raster time and identical pixels. The small gain on this oversized
case is expected: the unretained geometry still has to be rebuilt.

## Follow-up opportunities

The strongest next candidate is selective replay around transparency groups.
This file's 24 groups and 16 soft masks currently make `PdfRegionReplayIndex`
reject the whole transcript, disabling viewport culling and cached tiles. A
probe found only four outermost group spans, containing 228 of 171,406 raw
commands. Indexing balanced groups as indivisible units could retain their
compositing semantics while culling the rest of the drawing. Their bounds must
include mask subcommands and all paint effects; the probe's ordinary paint
bounds are not sufficient. This improvement has not been implemented or timed.

Text preparation could reuse extraction-ready runs from the original worker
recording instead of interpreting the page again. It must preserve character
advances, bidi ordering and invisible text, and exclude annotation appearances
and mask-only content. Warming currently hides the repeated walk after the
result is ready; it does not eliminate it.

Rasterization remains approximately 100 ms at 4×. Profiling the soft-mask
layers could establish whether explicit conservative bounds or reusable mask
surfaces help. Their small painted footprints suggest an opportunity, but the
raster engine may already infer tight bounds, so a measured comparison is
needed before changing compositing.
