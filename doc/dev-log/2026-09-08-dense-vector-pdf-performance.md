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
  not retain one-shot paths.
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
| 2× | 103.76 | 64.25 | 87.70 | 85.34 |
| 4× | 102.74 | 61.59 | 102.88 | 103.52 |
| 8× | 96.56 | 63.26 | 128.97 | 128.74 |

At 4×, replay work falls 40%, and replay plus raster falls from approximately
206 ms to 165 ms (20%). Raster cost is unchanged. The scene retained 47,620
paths, estimated at 30,571,520 bytes, with zero evictions during this run.

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
