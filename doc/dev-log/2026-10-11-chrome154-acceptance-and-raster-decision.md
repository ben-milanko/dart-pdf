# 2026-10-11 - Chrome 154 acceptance runs, attribution passes, and the #1000 raster decision

This session worked through the open performance tickets (#997–#1001) in a
cloud container. Everything here ran on **Chrome for Testing 154.0.8037.92**,
downloaded from the CfT `known-good-versions` index, so the browser matches
the 10-02 checkpoint. Its GPU is SwiftShader, which makes absolute times about
4× hardware. The results that carry over are ratios, A/Bs and phase shares.
Builds were per-commit worktree bundles served with `PERF_WEB_DIR` and
`PERF_NO_BUILD=1`, interleaved round by round with the order alternating.

## #997 closed: Chrome 154 confirms readiness, not pixels

| build | runs | zoom first visual p50 | zoom stable p50 |
|---|---|---|---|
| `fadf7760` (10-02, own harness, polled readiness) | 7 | 111.3 ms | 162.4 ms (= ready) |
| `main` `4860010c` (tracked readiness, #999) | 6 | 116.5 ms | 116.5 ms |

The ~50 ms was the polled readiness sample, as the Chromium 141 bisect and
the `PdfPerfLog` trace already showed. Closed with that evidence.

## #998: mechanism confirmed, cadence not judgeable without a GPU

- **Inside the wheel stage the fix is visible.** UI-thread vector prerenders
  dropped from 3–4 to 2 per run, and `Worker.onmessage` long-animation-frame
  time from 78 to 44 ms/run.
- **rAF p95 still reads 183–200 ms on both builds.** Each wheel frame spends
  60–120 ms of SwiftShader raster compositing the visible page images, which
  hides the UI-thread work. Acceptance needs a hardware run, so the issue
  stays open with the command to run.
- **Page stable p50 moved 405 → ~470 ms between the builds.** All of it is one
  jump: back to page 7 after page 8. Whether the previous page already holds a
  neighbour raster (fast, about 20 ms) or only a command-warm scene (slow,
  300–1200 ms) is a race on every build. Counts of fast runs: 10-02 4/6 (and
  6/7), pre-#1070 3/6, `main` 2/6, `main` without the decode gate 3/5. No commit
  flips it, so it isn't a #1070 regression. Filed as #1079.

## #999 attribution passes

- **Per-zoom timeline on `main`** (medians of 6 runs, Flutter `FrameTiming`
  windows per action):
  - zoom to 2×: first visual 290 ms, build 10 ms, raster 282 ms (largest frame
    240 ms);
  - zoom back to 1×: 106–131 ms, build 6–7 ms, raster 148–158 ms.

  Zoom readiness now lands 16–27 ms before the pixels.
- **Page-stable phase split.** Per page jump, build is 15–29 ms summed against
  199–858 ms of raster (largest frame 94–310 ms). Plan pages carry 3.8–23k
  commands. The 62-page book from the 10-02 checkpoint isn't in the repo;
  `parity-scan` (scan-book-12p) stands in and shows the same split on JS:
  - per jump: build 13–30 ms, raster 133–215 ms (largest frame 52–119 ms);
  - per zoom: build 8–12 ms, raster 56–105 ms.
- **Offline split** (`benchmark/run.sh`, pdf.js corpus, 210 pages both engines
  rendered, scale 2, best of 3):
  - full render 12.5 vs 10.5 ms/page, **1.19× slower** than PDFium;
  - interpretation alone 0.8 ms/page, against PDFium's 10.5 ms/page including
    raster.

  The gap is raster. Its outliers are `colorspace_atan.pdf` (185 vs 21.5 ms),
  `calrgb.pdf` (401 vs 105 ms) and `issue4246.pdf` (77 vs 19 ms), which are
  colour-space conversion candidates for #1001. The 2026-10 figure (52 files /
  268 pages, 1.73×) used the git-ignored local `corpus/`, so the two aren't
  directly comparable.
- **SkWasm on `parity-plan` in screenshot mode:** see the next section.

## #1000: the measurement and the call

There were four interleaved configurations of the same `main` source, all with
screenshot capture. The full table and the prerequisites are in
`doc/benchmarks/pdfium-parity.md` ("Off-main-thread raster decision").

- **SkWasm** fixes cadence (rAF p95 1.00× PDFium on all three scenarios) but
  not page latency.
- **JS + `domSurface=1`** fixes open and page p50 but not cadence (2–4×). That
  is the shape the A2 ImageBitmap hybrid would have, so A2 isn't worth
  building separately.
- **SkWasm + `domSurface=1`** is the only configuration that moves both. It
  passed everything on `parity-text` except zoom refinement, which is a second
  change about 120 ms after the first.
- **`surface-check` found real gaps.**
  - Text foreground coverage at 1.5× is 1.35× the SkWasm baseline (limit
    1.20).
  - Plan page 0 at 3× measured 1.083 against a 1.08 limit.
  - The scan check timed out mirroring page 7 at 2×.
- **The corpora sit entirely inside the surface profile.** Real documents with
  embedded fonts fall back to SkWasm, so `Path2D` glyph outlines come first.

The call: go for SkWasm + worker surface as the web target, behind the
prerequisites (profile coverage, pixel gates, zoom refinement, memory budget,
wasm deploy cache-busting, overlays, hardware confirmation). It isn't a default
yet.

## Gotchas

- `pgrep -f <script>` inside an `until` loop matches the loop's own command
  line. Wait on a file or a PID instead.
- A container restart kills background measurements. `measure.sh` appends per
  run, so re-run only the missing rounds.
- Screenshot mode puts page/zoom first visual at the ~39 ms capture floor for
  both engines. Compare stable latency, cadence and RSS across backends, and
  never pool screenshot with screencast runs.
