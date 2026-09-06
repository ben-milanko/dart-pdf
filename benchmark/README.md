# dart-pdf vs PDFium render benchmarks

> **Front door:** `tool/perf.sh` at the repo root dispatches every perf
> suite (this one included, as `tool/perf.sh compare-pdfium`), and all
> suites now emit the shared envelope schema (`tool/perf/SCHEMA.md`) on top
> of the JSON documented here - `compare.py` is unaffected.

Performance harnesses that time dart-pdf rendering against **PDFium** (the
C++ engine Chrome uses) over the same corpus of PDFs, and emit a side-by-side
comparison table (ms/page, pages/s, speedup ratio).

PDFium comes from [`pypdfium2`](https://pypi.org/project/pypdfium2/), which
bundles a prebuilt PDFium binary. You do not need a system PDFium build or
`pdfium_test`.

## Latest results

Real-world corpus (52 files / **268 pages** that all three tools rendered
without error), scale 2.0 (144 DPI), up to 10 pages per file, best-of-3 render
passes, on the 10-core M1 Pro development Mac. PDFium 5.9.0 / libpdfium
150.0.7869.0. Captured 2026-08-23 from commit `1b887e9f`.

| engine | throughput | ms/page | vs PDFium |
|---|---|---|---|
| **PDFium** (rasterize; open excluded) | 31.3 pages/s | 31.9 | 1.00× |
| **dart-pdf interpret** (pure Dart, no raster) | 82.4 pages/s | 12.1 | **2.63× faster** |
| **dart-pdf render** (full Flutter raster + readback) | 16.2 pages/s | 61.6 | **1.93× slower** |

Takeaways:

- **The pure-Dart page interpreter processes this corpus 2.63× faster than
  PDFium rasterizes it.** The interpreter number excludes rasterization; it
  isolates the portable Dart parsing, font, geometry, and content-stream work.
- **The apples-to-apples full Flutter render is 1.93× slower than PDFium.**
  Beyond interpretation, this path includes image decoding, Flutter
  painting/rasterization, and `toImage`/`toByteData` readback.
- Since the 2026-07-26 checkpoint, the common set grew from 49 files / 255
  pages to 52 files / 268 pages. Absolute milliseconds are therefore not a
  direct regression comparison; the relative ratios moved from 2.42× to
  2.63× for interpretation and from 1.95× to 1.93× for full rendering.

Absolute milliseconds and ratios are machine-specific. Re-run on the target
hardware with `benchmark/run.sh corpus 2 10` (see Quick start).

## What gets measured

Three harnesses, all writing the same JSON schema so they line up file-by-file:

| harness | engine | measures | needs |
|---|---|---|---|
| `pdfium_benchmark.py` | PDFium via pypdfium2 | page rasterization to bitmap | `pip install pypdfium2` |
| `benchmark_render_test.dart` | dart-pdf full pipeline | page load + interpret + paint + `toImage` | fvm Flutter |
| `benchmark_interpret.dart` | dart-pdf interpreter | page load + interpret to a `NullDevice` (no raster) | fvm Dart |

`benchmark_render_test.dart` is the **apples-to-apples** comparison with
PDFium. Both produce a rasterized bitmap at the same scale. dart-pdf's
rasterization runs on Flutter's engine, so that harness is a `flutter test`
file (it skips in CI unless `PDF_BENCHMARK_DIR` is set).

`benchmark_interpret.dart` isolates dart-pdf's pure-Dart parse + content-stream
work (the part that runs on the web and on the VM); it has no PDFium counterpart
but is the fairer number for "how fast is the Dart code itself", since it
excludes Flutter's GPU raster + readback.

### Fair-comparison notes

- **Scale.** PDFium `scale` and dart-pdf `pixelRatio` use the same unit:
  `1.0` = 72 DPI = 1 px per PDF point. Both harnesses default to `2.0`.
- **Timing boundaries.** File bytes are read up front and excluded. `openMs`
  records document open/page-count work separately and is not included in the
  comparison table; `renderMs` is the per-page loop used for the headline
  figures. dart-pdf loads page objects lazily, so that loop includes page-level
  parsing. The render harnesses call `toByteData(rawRgba)` / touch the PDFium
  bitmap buffer to force rasterization to fully complete before the clock
  stops.
- **Warmup.** Flutter's first raster pays one-time shader/engine warmup, which
  inflates the first few files. `run.sh` defaults to three sweeps and keeps
  each file's fastest pass; set `BENCHMARK_REPEAT=1` for a quick single pass.
- **Page cap.** Default 10 pages/file keeps long documents from dominating;
  raise with `--max-pages 0` (all pages).
- **Malformed PDFs.** Some corpora (notably `test_corpora/pdfjs`) hold
  deliberately-corrupted files that send PDFium into a multi-minute native
  spin. PDFium renders the whole sweep in one process, and a long native call
  ignores signals, so `pdfium_benchmark.py --timeout N` renders each file in a
  killable fork child and records anything over `N` seconds as a `timeout`
  error instead of hanging the run. `run.sh` passes `--timeout 30` by default
  (override with `PDFIUM_TIMEOUT`). The dart-pdf render harness has its own
  per-page 60 s timeout.
- **Fonts.** `benchmark_render_test.dart` reuses the test suite's
  `loadSystemFonts` (macOS font paths); on other platforms dart-pdf falls back,
  which is fine for timing.

## Interaction performance

The table above is an offline throughput benchmark. It does **not** measure
viewer FPS, scrolling jank, or dropped frames, so it is not evidence for the
3.1.1 frame-pacing fixes by itself. Those are measured separately in real
Chrome by [`app/tool/perf/`](../app/tool/perf/README.md), which records frame
build percentiles and `PdfPerfLog` jank events while it drives real scroll
scenarios.

Historical 3.1.0→3.1.1 release result: the `scroll-plan` workload, a
16-sheet vector plan set with
about 70,000 operations per page, run as a release web build in headless
Chrome. These are medians from five interleaved runs of each version, captured
2026-07-26:

| interaction metric | 3.1.0 | 3.1.1 | change |
|---|---:|---:|---:|
| frame build p50 | 1.12 ms | 1.11 ms | -0.6% |
| frame build p95 | 1.80 ms | 1.77 ms | -1.4% |
| worst build frame (median/run) | 16.34 ms | 15.57 ms | -4.7% |
| jank events/run (build or raster over 16 ms) | 7 | 1 | **-85.7%** |
| browser agent memory | 303 MiB | 256 MiB | -15.5% |

The typical frame was already fast in 3.1.0; the 3.1.1 improvement is the
large reduction in sporadic over-budget frames, matching the release's
scheduler, thumbnail-yielding, and wheel-preview-cache fixes. Neither version
recorded a build frame over 32 ms in this A/B.

Reproduce it with:

```bash
tool/perf.sh web scroll-plan
tool/perf.sh webdiff app-v3.1.0 scroll-plan --iterations 5
```

Keep interaction results separate from the ms/page table: they answer
different questions and use different workloads.

## Quick start

```bash
pip install pypdfium2

# one command: best-of-3 for all three over test_corpora/pdfjs
# at scale 2, 10 pages/file
benchmark/run.sh

# or a custom corpus / scale / page cap
benchmark/run.sh /path/to/pdfs 2 20

# quick single pass
BENCHMARK_REPEAT=1 benchmark/run.sh /path/to/pdfs 2 20
```

`run.sh` writes JSON into `benchmark/out/` (git-ignored) and prints the table.

## Running a harness on its own

```bash
# PDFium (--timeout kills any file that spins past N seconds)
python3 benchmark/pdfium_benchmark.py test_corpora/pdfjs \
    --scale 2 --max-pages 10 --repeat 3 --timeout 30 --out benchmark/out/pdfium.json

# dart-pdf full render (Flutter)
cd packages/dart_pdf_editor
PDF_BENCHMARK_DIR=../../test_corpora/pdfjs PDF_BENCHMARK_SCALE=2 \
PDF_BENCHMARK_MAX_PAGES=10 PDF_BENCHMARK_REPEAT=3 \
PDF_BENCHMARK_OUT=../../benchmark/out/dart-render.json \
  fvm flutter test test/benchmark_render_test.dart

# dart-pdf interpret only (pure Dart VM)
cd packages/pdf_graphics
fvm dart run tool/benchmark_interpret.dart ../../test_corpora/pdfjs \
    --max-pages 10 --repeat 3 \
    --out ../../benchmark/out/dart-interpret.json
```

## The comparison table

```bash
# first JSON is the baseline; speedup columns are baseline_ms / tool_ms
python3 benchmark/compare.py benchmark/out/pdfium.json \
    benchmark/out/dart-render.json benchmark/out/dart-interpret.json

# options
python3 benchmark/compare.py ... --md         # GitHub Markdown table
python3 benchmark/compare.py ... --per-file    # every file (default: slowest 25)
```

Example (8-file pdfjs subset, scale 2; illustrative, not a hardware-neutral
result):

```
## Totals (pages all tools rendered without error)
- pdfium: 7 pages = 131.6 pages/s (7.6 ms/page)
- dart-pdf-render: 7 pages = 19.6 pages/s (50.9 ms/page)
- dart-pdf-interpret: 7 pages = 155.0 pages/s (6.5 ms/page)
```

`err` in a cell means that tool failed on that file; the totals row only counts
pages every tool rendered without error, and scales each file to the smallest
page count the tools agree on, so the throughput numbers are comparable.

## Corpus

Anything works: point the harnesses at a directory (searched recursively) or a
single file. The checked-in `test_corpora/pdfjs` (171 edge-case PDFs) and
`test_corpora/ghent` (54 print-conformance PDFs) make a reproducible default;
Ben's git-ignored `corpus/` (real-world CAD/scans/reports) is the realistic
stress set:

```bash
benchmark/run.sh corpus 2 0      # all pages of every real-world PDF
```

## Web renderer benchmark (CanvasKit vs skwasm)

The harnesses above ride `flutter test`'s headless **host** engine, so they
can't compare Flutter's two **web** renderers. `benchmark/web/` builds the app
for the browser both ways (CanvasKit and `--wasm`/skwasm), drives it in headless
Chromium via Playwright, and emits this same JSON schema (with the renderer
detected at runtime). See [benchmark/web/README.md](web/README.md):

```bash
benchmark/web/run.sh            # build both, drive both, print the table
```

## JSON schema

```json
{
  "tool": "pdfium",
  "scale": 2.0,
  "maxPages": 10,
  "engine": "pypdfium2 5.9.0 / libpdfium 150.0.7869.0",
  "results": [
    {"file": "foo.pdf", "pages": 3, "pagesRendered": 3,
     "openMs": 1.2, "renderMs": 45.6, "error": null}
  ]
}
```
