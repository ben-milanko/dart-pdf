# Web render benchmark - CanvasKit vs skwasm

Times dart-pdf's page rasterization **inside a real browser**, under each of
Flutter's two web renderers, and prints a side-by-side table:

- **CanvasKit** - Skia compiled to WebAssembly + WebGL, app compiled with
  dart2js. The default of `flutter build web`.
- **skwasm** - the newer Skia-in-Wasm renderer (multithreaded, needs
  cross-origin isolation), app compiled to WebAssembly with dart2wasm. Produced
  by `flutter build web --wasm`.

The existing `benchmark/benchmark_render_test.dart` can't tell these apart: it
rides `flutter test`'s headless **host** engine, not a web renderer. This
harness builds the web app for real, serves it, and drives it in headless
Chromium so the rasterization actually flows through CanvasKit / skwasm.

The in-browser work is the same pipeline the other benchmarks measure:
`PdfPageRenderer.renderImage` → `Picture.toImage` → `toByteData(rawRgba)`
readback, per page, at a fixed pixel ratio. The entrypoint lives at
`packages/dart_pdf_editor/example/lib/web_benchmark.dart`.

## Quick start

```bash
benchmark/web/run.sh [corpus_dir] [count] [scale] [maxPages] [repeat]
# defaults: corpus=test_corpora/pdfjs count=20 scale=2 maxPages=5 repeat=3
```

Requirements: fvm/flutter 3.44.4, Node, a global Playwright with Chromium
(`PLAYWRIGHT_BROWSERS_PATH`), and `python3` for the compare table. `run.sh`
generates a manifest, builds both renderers, serves + drives each, and runs
`benchmark/compare.py`.

## Pieces

| file                                  | role                                                                               |
| ------------------------------------- | ---------------------------------------------------------------------------------- |
| `web_benchmark.dart` (in example/lib) | in-page harness: fetch manifest + PDFs, render + time, publish results on `window` |
| `gen_manifest.cjs`                    | pick N corpus PDFs into `manifest.json` (skips fuzz fixtures)                      |
| `serve.cjs`                           | static server for a build dir + corpus + manifest, with COOP/COEP headers          |
| `drive.cjs`                           | Playwright: load a build, detect the renderer used, scrape results to JSON         |
| `run.sh`                              | build both → serve+drive both → compare                                            |

The driver confirms which renderer actually ran by watching network requests
(`skwasm*.wasm` / `main.dart.wasm` vs `canvaskit*.wasm`), so the `renderer`
field in the output is observed, not assumed.

## Important caveats

- **Software rasterization.** Headless Chromium has no GPU, so WebGL falls back
  to SwiftShader (software) for both renderers. The **absolute** ms are
  software-rasterized and far slower than a real GPU; the CanvasKit-vs-skwasm
  **ratio** is the portable signal. Run `drive.cjs --headed` on a machine with a
  display/GPU for representative absolute numbers.
- **Local engine resources.** Built with `--no-web-resources-cdn` so
  CanvasKit/skwasm load from the bundle, not the gstatic CDN (the sandbox can't
  validate the CDN cert, and a benchmark shouldn't depend on the network).
- **Blocked font fallback.** The driver aborts `fonts.gstatic.com`, so
  non-embedded CJK/symbol glyphs fall back to boxes. Equal handicap for both
  renderers; affects glyph fidelity, not the timing comparison.
- **Explicit locale.** The driver sets `locale=en-US`; headless Chromium
  otherwise reports a locale Flutter's parser rejects on boot.

## Results

`run.sh` ends by printing `benchmark/compare.py web-canvaskit.json
web-skwasm.json`. The JSON files (in `out/`) also carry `loadMs` (engine boot)
and `appBytes` (approx transfer size) per renderer, which `compare.py` does not
table - read them from the JSON for the load-time / bundle-size comparison.

### Latest run

20 files from `test_corpora/pdfjs` (19 rendered without error), scale 2,
maxPages 5, best-of-3 passes, in this sandbox's **headless Chromium with
SwiftShader (software WebGL - no GPU)**. Captured 2026-06-18.

| renderer      | app build | throughput       | ms/page | boot       | fetched bytes¹ |
| ------------- | --------- | ---------------- | ------- | ---------- | -------------- |
| **CanvasKit** | dart2js   | **24.8 pages/s** | 40.4    | 609 ms     | 9.8 MB         |
| **skwasm**    | dart2wasm | 15.2 pages/s     | 66.0    | **417 ms** | **7.4 MB**     |

**skwasm rasterized 1.63× slower than CanvasKit** here, consistently across the
corpus (per-file 0.42×–0.95×). It booted ~30% faster and fetched fewer bytes.

¹ Uncompressed bytes of the resources actually fetched (not the full 43–45 MB
on-disk bundle); a real server would gzip/brotli these.

Caveats that matter for reading these numbers:

- **This is software rasterization.** With no GPU, both renderers fall back to
  SwiftShader, so the absolute ms are far slower than production and the gap is
  not predictive of GPU hardware - skwasm's threaded raster and CanvasKit's
  WebGL path scale differently with a real GPU. Re-run `--headed` on a GPU box
  before trusting the magnitude or even the direction of the ratio.
- Best-of-3 over a one-shot headless process; boot times especially are noisy.
- Blocked CDN font fallback means CJK/symbol glyphs render as boxes under both.

Reproduce: `benchmark/web/run.sh`.
