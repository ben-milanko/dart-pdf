# Automated real-world Chrome perf loop

An unattended version of the manual `flutter run -d chrome` perf check: it
loads the big CAD PDF in **real headless Chrome** (system Chrome, dart2js
build), auto-scrolls every page, scrapes the `PdfPerfLog` trace + `FrameTiming`,
and prints a verdict — repeatably, so a loop can chart trends and catch
dart2js-only regressions (like the Int64 accessor bug) that VM tests can't.

## Pieces

- **`perf_harness.dart`** — a standalone Flutter web entrypoint (not the shipping
  app). Fetches the PDF from `/perf.pdf`, mounts the real `PdfEditorView` with
  the web render worker, enables `PdfPerfLog`, captures every `debugPrint` line
  and every frame's timing, then auto-scrolls all pages. Exposes to the driver:
  `window.__perfDone`, `__perfDump()`, `__perfFrames()`, `__perfError`. Scroll
  knobs come from the URL query (`?maxPages=&dwell=&passes=&fast=`) so the
  prebuilt bundle never needs a rebuild to vary the run.
- **`driver.mjs`** — Node + `puppeteer-core` (system Chrome, no download). Serves
  `build/web` + `/perf.pdf`, drives Chrome through the harness, waits for
  `__perfDone`, parses the trace, prints a summary, and appends one JSON record
  per run to `results.ndjson`.
- **`build.sh`** — compiles the render worker + the harness bundle into
  `app/build/web`. Run once per code change.
- **`loop.sh N`** — runs the driver N times (alternating full + capped sweeps),
  then reports the aggregate.
- **`report.mjs`** — summarises `results.ndjson` (per-run table + aggregate;
  flags FAIL and UI-thread-interpret regressions).

## Usage

```sh
cd app/tool/perf
npm install                       # once — pulls puppeteer-core only
tool/perf/build.sh                # after any engine/app change (from app/)
node driver.mjs                   # one run (full 133-page sweep)
PERF_MAX_PAGES=40 node driver.mjs # one capped run (~30s)
./loop.sh 8                       # eight runs + aggregate
node report.mjs 20                # last 20 runs' trend
```

### Env (driver)

| var | default | meaning |
|-----|---------|---------|
| `PERF_PDF` | `~/Downloads/MW307(TNT975)F-UPS-ZB.pdf` | PDF to serve at `/perf.pdf` |
| `PERF_MAX_PAGES` | `0` (all) | cap pages scrolled (faster smoke) |
| `PERF_DWELL_MS` | `220` | dwell on each page |
| `PERF_FAST_PASS` | `1` | add a coarse fast-fling pass |
| `PERF_HEADLESS` | `true` | `false` for a visible window |
| `PERF_TIMEOUT` | `300` | overall budget, seconds |
| `PERF_VERBOSE` | `false` | echo every browser console line |
| `PERF_PORT` / `PERF_CHROME` | `8099` / system Chrome | server port / Chrome path |

## Verdict

`✓ PASS` — no harness/page errors, frames captured, pages visited. `◐ PASS
(ui-interp)` — passed but some page interpreted on the UI thread
(`path=plain`/`recorded`), the regression signal the worker offload exists to
prevent. `✗ FAIL` — a fatal (startup crash, timeout) or any error line.

The trace fields parsed: interpret-path counts (`worker`/`recorded`/`plain`),
worker decode bytes + warm ms (the off-thread image decode), and the
`FrameTiming` build-duration distribution (p50/p95/max, counts over 16/32/50ms).
