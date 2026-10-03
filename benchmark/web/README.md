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

Requirements: fvm/flutter 3.47.5, Node, a global Playwright with Chromium
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

- **Software rasterization.** The driver forces ANGLE/SwiftShader, so WebGL
  runs in software for both renderers, whatever the host GPU. The **absolute** ms are
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

20 files from `test_corpora/pdfjs` (19 rendered without error, 20 pages),
scale 2, maxPages 5, best-of-3 passes, in Playwright's headless Chromium
(Chrome Headless Shell 153) on an Apple M1 Pro laptop. The driver forces
ANGLE/SwiftShader, so WebGL is still **software-rasterized (no GPU)** even on
this host. Captured 2026-10-02 at commit `fadf7760`. This is a new checkpoint
on a different host, not a like-for-like successor to the 2026-06-18 sandbox
run (which measured skwasm 1.63× slower).

| renderer      | app build | throughput       | ms/page | boot        | fetched bytes¹ |
| ------------- | --------- | ---------------- | ------- | ----------- | -------------- |
| **CanvasKit** | dart2js   | **36.6 pages/s** | 27.3    | 2959 ms     | 13.8 MB        |
| **skwasm**    | dart2wasm | 31.1 pages/s     | 32.2    | **2548 ms** | **11.8 MB**    |

**skwasm rasterized 1.18× slower than CanvasKit** here (a replicate run gave
1.17×). It was slower on most files but not all: per-file 0.53×–1.36×, with
skwasm ahead on 5 of 19. It booted 5–14% faster across two runs and fetched
about 15% fewer bytes.

¹ Uncompressed bytes of the resources actually fetched (not the full 48–50 MB
on-disk bundle); a real server would gzip/brotli these.

Caveats that matter for reading these numbers:

- **This is software rasterization.** `drive.cjs` passes
  `--use-angle=swiftshader`, so both renderers run on SwiftShader and the
  absolute ms are far slower than production. The gap is not predictive of GPU
  hardware - skwasm's threaded raster and CanvasKit's WebGL path scale
  differently with a real GPU. Re-run `--headed` on a GPU box before trusting
  the magnitude or even the direction of the ratio.
- Boot took 2.5–3 s on this host versus 0.4–0.6 s in the 2026-06-18 sandbox,
  and the skwasm boot lead moved between runs; do not compare boot times
  across hosts.
- The host was moderately loaded (desktop apps running), and the corpus is
  tiny (about 0.6 s of total render across 20 pages, many of them trivial
  2–70 ms one-page fixtures), so per-file ratios are noisy. Best-of-3 over a one-shot headless process.
- Blocked CDN font fallback means CJK/symbol glyphs render as boxes under both.

Reproduce: `benchmark/web/run.sh`.
