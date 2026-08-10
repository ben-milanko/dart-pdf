# Reusable real-Chrome perf harness

> **Front door:** `tool/perf.sh web [scenario]` (one run) and
> `tool/perf.sh webdiff <ref> [scenario]` (one-command A/B) at the repo root.
> Runs append envelope records (`tool/perf/SCHEMA.md`, suites `chrome-scroll`
> / `chrome-open` / `chrome-search` / `chrome-edit`). **Do not edit sources or
> run builds/tests while a measurement run/loop is in flight** — concurrent
> compiles pollute timings and can crash mid-run children.

An unattended, scenario-driven version of the manual `flutter run -d chrome`
perf check. It loads a real PDF in **real headless Chrome** (system Chrome,
dart2js build), runs one named **scenario** against the real
`PdfViewer`/editing stack, scrapes the `PdfPerfLog` trace + `FrameTiming` + the
scenario's own metrics, and prints a repeatable verdict — so you can chart
trends and A/B a change end to end, catching dart2js-only regressions that VM
tests can't.

This replaces the old single-workload harness and the pile of one-off
`example/lib/web_*_benchmark.dart` entrypoints: **one bundle, many workloads,
switched from the URL** so the prebuilt bundle never rebuilds to change what it
measures.

## Scenarios

Declared in [`scenarios.json`](scenarios.json) — a name → `{kind, pdf, params}`
registry. `pdf` is a repo-relative file from the CC0 `test_corpora/dartpdf`
corpus, so **any checkout (and any A/B worktree) can run every scenario** with
no magic local file. Five workload kinds ship:

| kind | what it measures | headline metrics |
|---|---|---|
| `scroll` | scroll every page (+ optional zoom-settle / fast-fling): frame smoothness, interpret/decode worker offload | `buildP50/P95/Max`, `buildOver50`, interpret paths, `workerWarmMax`, tab memory |
| `open` | cold-open profile: bytes → `PdfDocument.open` → `pageCount` → first painted content and a visually settled target page | `openBytesMs`, `openDocMs`, `openPageCountMs`, `openFirstContentMs`, `openVisualSettleMs` |
| `search` | full-document text search latency + hit count (best-of-N) | `searchMs`, `searchMatches` |
| `edit` | apply a batch of annotations through the real `PdfEditingController`: incremental-save + appearance-gen cost | `editApplyMs`, `editApplyMsPerOp`, `editRevisions`, `editBufferGrowthKb` |
| `hover` | mouse-move over a page with an editing tool armed: what following the painted cursor costs per pointer event | `hoverBuildMsTotal`, `hoverBuildMsPerEvent`, `hoverBuildMsP50/P95/Max`, `hoverFrames` |
| `warm` | idle for a fixed window, then arrive on a far page: what the idle full-raster warm (#614) buys and what it spent | `warmArriveMs`, `warmCompletions`, `warmRetainedMb`, `warmEvictions`, `warmHits/warmMisses` |

Stock scenarios: `scroll-plan`, `scroll-scan`, `scroll-diagram`, `open-plan`,
`open-text`, `search-text`, `edit-annotate`, `hover-ink`, `hover-eraser`,
`warm-plan-off`, `warm-plan-document`, `warm-scan-off`, `warm-scan-document`
(default `scroll-plan`).

`warm` is a **paired** kind: `warmArriveMs` only means something next to the
control arm's, so read `warm-plan-document` against `warm-plan-off` (the two
differ only in `?warm=`), not on its own.

### Adding a scenario going forward

Two ways, no driver change needed:

1. **Same kind, different doc/params** — add a JSON entry to `scenarios.json`.
2. **New workload kind** — add a `_drive<Kind>()` method + a `case` in
   `_drive()` in [`perf_harness.dart`](perf_harness.dart), emit numbers with
   `_metric(name, value)`, then add a JSON entry. The driver reads
   `window.__perfMetrics()` **generically**, so a new scenario's metrics show
   up in the summary, the history file, and the A/B diff automatically.

## Usage

```sh
# one run of a scenario (auto-builds the bundle if missing)
tool/perf.sh web scroll-plan
tool/perf.sh web open-text
tool/perf.sh web search-text
tool/perf.sh web edit-annotate

# rebuild the bundle after an engine/app change
tool/perf.sh web build

# one-command A/B: baseline git ref vs the working tree
tool/perf.sh webdiff main search-text
tool/perf.sh webdiff HEAD~5 scroll-plan --iterations 5 --threshold 1.05

# legacy scroll loop (the original full/capped alternating sweep)
tool/perf.sh web loop 8
```

### One-command A/B (`webdiff` → `bench.mjs`)

Builds a baseline git ref **and** the working tree, runs the same scenario
against both in interleaved ABAB order, and prints a per-metric median-delta
table — the web counterpart of the VM-only `tool/perf.sh diff`.

- Both sides run the **same** harness + driver + scenario + PDF bytes; only the
  compiled library in the bundle differs. The ref is checked out into a cached
  git worktree (`$TMPDIR/dart-pdf-webperf-ab/<sha>`, one `pub get` per sha) and
  today's `tool/perf/*` is copied in before building, so an old ref measures
  its own lib with the current harness (same bootstrap as
  `tool/perf/perf_diff.sh`).
- Regressions past `--threshold` (lower-is-better metrics only; equality/hit-
  count metrics are informational) set the exit code, so CI can gate on it.

```
══ search-text: main (a1b2c3d) → working tree, 3 interleaved runs

metric                  baseline    current     Δ         verdict
────────────────────────────────────────────────────────────────────────
buildP95                12.40       11.90       -4.0%     ·
openPageCountMs         410.00      405.00      -1.2%     ·
searchMatches           88          88          +0.0%     ≈
searchMs                52.30       38.10       -27.2%    ✓ faster
────────────────────────────────────────────────────────────────────────
```

## Pieces

- [`perf_harness.dart`](perf_harness.dart) — the standalone Flutter web
  entrypoint. Dispatches on `?scenario=`, drives the real viewer/editor, and
  exposes `window.__perfDone/__perfError/__perfDump()/__perfFrames()/__perfMetrics()`.
- [`driver.mjs`](driver.mjs) — Node + `puppeteer-core` (system Chrome, no
  download). Resolves `--scenario` from `scenarios.json`, serves `build/web` +
  the scenario's PDF at `/perf.pdf`, drives Chrome, scrapes the trace/frames/
  metrics, prints a summary, appends one envelope per run.
- [`bench.mjs`](bench.mjs) — the one-command A/B orchestrator (`webdiff`).
- [`build.sh`](build.sh) — compiles the render worker + the harness bundle into
  `app/build/web`. Run once per code change.
- [`loop.sh`](loop.sh) / [`report.mjs`](report.mjs) — the legacy scroll loop +
  its trend summary (still `results.ndjson`). Single-scenario `web` runs write
  per-scenario `results-<scenario>.ndjson` so trends never mix workloads:
  `PERF_RESULTS=results-search-text.ndjson node report.mjs 20`.

## Env (driver)

| var | default | meaning |
|-----|---------|---------|
| `PERF_SCENARIO` | *(none)* | scenario name (same as `--scenario`); picks kind + PDF + params |
| `PERF_PDF` | scenario's PDF, else legacy CAD | override the served PDF |
| `PERF_WEB_DIR` | `app/build/web` | the built bundle to serve |
| `PERF_MAX_PAGES` / `PERF_DWELL_MS` / `PERF_PASSES` / `PERF_FAST_PASS` | scenario | scroll knobs (override the scenario's) |
| `PERF_TARGET_PAGE` | scenario | open/scroll target page |
| `PERF_QUERY` / `PERF_REPEAT` | scenario | search needle / best-of-N |
| `PERF_OPS` | scenario | edit: annotations to apply |
| `PERF_EVENTS` / `PERF_TOOL` | scenario | hover: pointer events to dispatch / the armed tool |
| `PERF_IMAGE_CACHE_MB` | `0` | decoded-image cache budget, MB |
| `PERF_HEADLESS` | `true` | `false` for a visible window |
| `PERF_TIMEOUT` | `300` | overall budget, seconds |
| `PERF_VERBOSE` | `false` | echo every browser console line |
| `PERF_PORT` / `PERF_CHROME` | `8099` / system Chrome | server port / Chrome path |
| `PERF_RESULTS` | `./results.ndjson` | ndjson output path |

### Tab-memory probe

The summary's `tab memory` line comes from
`performance.measureUserAgentSpecificMemory()`, which counts CanvasKit's WASM
heap (issue #283). It needs cross-origin isolation (the server sends COOP/COEP)
**and** the browser-process PerformanceManager, which the old headless shell
does not run — so `PERF_CHROME` must point at a **full** Chrome/Chromium binary,
not a `*_headless_shell` one, and the driver uses new headless. `build.sh`
builds with `--no-web-resources-cdn` so CanvasKit is served locally.

No representative document handy for a scroll scenario?
`packages/pdf_cos/tool/gen_image_pdf.dart` generates an image-heavy multi-page
PDF with a controllable decoded-RGBA footprint.

## Verdict

`✓ PASS` means no harness/page errors and the scenario produced its metrics (or
visited pages). `◐ PASS (ui-interp)` is **scroll-only**: the run passed but some
page interpreted on the UI thread (`path=plain`/`recorded`), the regression
signal the worker offload exists to prevent. `✗ FAIL` means a fatal startup
crash, timeout, or error line.
