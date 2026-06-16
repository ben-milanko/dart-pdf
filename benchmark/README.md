# dart-pdf vs PDFium render benchmarks

Performance harnesses that time dart-pdf rendering against **PDFium** (the
C++ engine Chrome uses) over the same corpus of PDFs, and emit a side-by-side
comparison table (ms/page, pages/s, speedup ratio).

PDFium comes from [`pypdfium2`](https://pypi.org/project/pypdfium2/), which
bundles a prebuilt PDFium binary. You do not need a system PDFium build or
`pdfium_test`.

## Latest results

Real-world corpus (49 files / **245 pages** that all three tools rendered
without error), scale 2.0 (144 DPI), best-of-3 render passes, on the
development Mac. PDFium 5.9.0 / libpdfium 150.0.7869.0. Captured 2026-06-14
with the #52 render-perf work in place (shared parse, image-decode cache +
fast-paths, cross-render font cache, inline path construction, text-show
memoisation, and a rewritten content-stream tokenizer).

| engine | throughput | ms/page | vs PDFium |
|---|---|---|---|
| **PDFium** (open + rasterize) | 48.5 pages/s | 20.6 | 1.00× |
| **dart-pdf interpret** (pure Dart, no raster) | 73.6 pages/s | 13.6 | **1.52× faster** |
| **dart-pdf render** (full Flutter raster + readback) | 18.6 pages/s | 53.7 | **2.60× slower** |

Takeaways:

- **The pure-Dart engine is now ~1.5x faster than PDFium** for parse +
  content-stream interpretation, the code that runs on the VM and the web. The
  content-stream tokenizer rewrite (faster number/keyword/name lexing, no
  reference lookahead on content operands) roughly halved parse time and is
  what flipped this from 1.10× *slower* to 1.52× *faster*.
- **The full render path is 2.60x slower, and that gap is Flutter, not the
  interpreter.** interpret is 13.6 ms/page but render is 53.7, so ~40 ms/page
  is image decoding + Flutter's GPU rasterization + `toImage`/`toByteData`
  readback. A phase split of the render path (scale 2): parse 13.5, collect
  2.3, image decode 18.1, paint 7.3, **GPU rasterize 16.7**, readback 0.7
  ms/page. The decode and rasterize costs dominate; both lean on platform
  codecs / GPU that PDFium reaches via an in-process CPU bitmap (no GPU upload
  or readback). The per-file split confirms it: a single giant-image page
  renders at 0.11x, while text/vector documents interpret *faster* than PDFium
  rasterizes them.

Absolute milliseconds are machine-specific; the **ratios** are the portable
number. Re-run with `benchmark/run.sh corpus 2 10` (see Quick start).

## What gets measured

Three harnesses, all writing the same JSON schema so they line up file-by-file:

| harness | engine | measures | needs |
|---|---|---|---|
| `pdfium_benchmark.py` | PDFium via pypdfium2 | open + rasterize to bitmap | `pip install pypdfium2` |
| `benchmark_render_test.dart` | dart-pdf full pipeline | open + interpret + paint + `toImage` | fvm Flutter |
| `benchmark_interpret.dart` | dart-pdf interpreter | open + interpret to a `NullDevice` (no raster) | fvm Dart |

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
  is parse/load; `renderMs` is the per-page render loop. The render harnesses
  call `toByteData(rawRgba)` / touch the PDFium bitmap buffer to force the
  rasterization to fully complete before the clock stops.
- **Warmup.** Flutter's first raster pays one-time shader/engine warmup, which
  inflates the first few files. Pass `--repeat 3` / `PDF_BENCHMARK_REPEAT=3`
  to render the sweep several times and keep each file's fastest pass.
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

## Quick start

```bash
pip install pypdfium2

# one command: runs all three over test_corpora/pdfjs at scale 2, 10 pages/file
benchmark/run.sh

# or a custom corpus / scale / page cap
benchmark/run.sh /path/to/pdfs 2 20
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
    --max-pages 10 --out ../../benchmark/out/dart-interpret.json
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
