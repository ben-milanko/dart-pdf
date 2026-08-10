# Reusable real-Chrome perf harness

> **Front door:** `tool/perf.sh web [scenario]` (one run) and
> `tool/perf.sh webdiff <ref> [scenario]` (one-command A/B) at the repo root.
> `tool/perf.sh competitive [scenario]` runs the common DartPDF-versus-PDFium
> user journey described below.
> `tool/perf.sh surface-check [scenario]` runs the worker-surface pixel gate.
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

## Chromium/PDFium competitive journey

`competitive.mjs` closes the gap between the internal DartPDF browser timings
and the offline `pypdfium2` raster benchmark. It launches clean instances of
the same installed Chrome binary and drives both the DartPDF viewer and
Chrome's built-in PDF viewer (PDFium) through an identical cold open, page-jump
sequence, zoom sequence, and sustained wheel stream. The text scenario also
runs matched cold/warm full-document text queries:

The release build uses the minimal workspace package at
`app/tool/perf_harness`, not the production app's dependency/plugin graph. Its
web shell intentionally has no branded splash, fade, OCR/file-launch bridge,
or other app chrome, so cold-open measures Flutter plus the viewer rather than
unrelated plugins and transitions.

```sh
# Rebuilds the Dart harness, then runs three interleaved cold samples/engine.
tool/perf.sh competitive parity-plan --iterations 3

# Other checked-in real-world shapes.
tool/perf.sh competitive parity-scan --iterations 5
tool/perf.sh competitive parity-text --iterations 5
tool/perf.sh competitive parity-diagram --iterations 5

# Deterministically generated 138-page CAD journeys.
tool/perf.sh competitive parity-long-cad --iterations 5
tool/perf.sh competitive parity-progressive-cad --iterations 5

# Build once and gate all six scenarios. This is the acceptance front door.
tool/perf.sh pdfium-gate

# Fail when a controlled runner misses the documented parity tolerances.
PERF_NO_BUILD=1 tool/perf.sh competitive parity-plan --iterations 7 --gate

# Verify when this Chrome/host samples full screenshots. The runner uses a
# conservative 36ms bound; override it only when this probe says to.
tool/perf.sh screenshot-probe
PERF_SCREENSHOT_SAMPLE_DELAY_MS=40 \
  tool/perf.sh competitive parity-plan --iterations 7 --gate

# A/B an opt-in Dart harness switch without changing PDFium or rebuilding.
PERF_NO_BUILD=1 PERF_DART_QUERY=prewarm=0 \
  tool/perf.sh competitive parity-text --iterations 3

# Reproducible negative control: disable exact full-page raster retention.
PERF_NO_BUILD=1 PERF_DART_QUERY=rasterCacheMb=0 \
  tool/perf.sh competitive parity-text --iterations 3

# SkWasm uses an offscreen canvas, so validate it with full screenshots.
WASM=1 PERF_VISUAL_CAPTURE=screenshot \
  tool/perf.sh competitive parity-text --iterations 3

# A side-by-side prebuilt directory is both built and served by this command.
WASM=1 PERF_BUILD_OUTPUT=/tmp/dartpdf-skwasm \
  PERF_WEB_BACKEND=skwasm PERF_VISUAL_CAPTURE=screenshot \
  tool/perf.sh competitive parity-text --iterations 3

# Default-off worker-owned Canvas2D surface with strict command fallback.
WASM=1 PERF_BUILD_OUTPUT=/tmp/dartpdf-skwasm-surface \
  PERF_WEB_BACKEND=skwasm PERF_VISUAL_CAPTURE=screenshot \
  PERF_DART_QUERY=domSurface=1 \
  tool/perf.sh competitive parity-text --iterations 5

# Compare three real pages at the first three distinct journey zooms against
# the established renderer and fail the scenario's calibrated pixel budgets.
PERF_NO_BUILD=1 \
  PERF_BUILD_OUTPUT=/tmp/dartpdf-skwasm-surface \
  tool/perf.sh surface-check parity-scan
```

Keep `WASM=1`, `PERF_WEB_BACKEND=skwasm`,
`PERF_VISUAL_CAPTURE=screenshot`, and `PERF_DART_QUERY=domSurface=1` when adding
`PERF_NO_BUILD=1`. A prebuilt directory name is not renderer metadata; omitting
those variables intentionally runs and records the default JS/CanvasKit path.

The `domSurface=1` benchmark bootstrap fetches the PDF once and lets the render
worker paint page zero before Flutter/SkWasm finishes booting. It holds that
canvas until the hydrated viewer surface is ready, then verifies the handoff in
`surface-check`. This is a strict-fallback benchmark experiment, not a public
application bootstrap API.

The runner alternates engine order, uses a fresh browser profile for every
sample, disables the HTTP cache, fixes the viewport and low-quality compositor
screencast, and serves exactly the same PDF bytes. An action is complete after
its engine says the requested page/zoom is ready and Chrome has emitted no
changed compositor frame for 500 ms. A visual tracker is not allowed to settle
on a shell or page placeholder before that readiness promise resolves. Dart's
page-ready transition is timestamped inside the page with
`performance.timeOrigin + performance.now()`, so a screenshot occupying CDP
cannot turn a delayed readiness poll into fake renderer latency. The
confirmation exceeds DartPDF's 200 ms zoom-refinement debounce and is not
charged to the metric. Wheel actions send the same signed distance as 18 steps
at a fixed 16 ms event-start cadence. Dispatch promises are collected without
making the next hardware-like event wait for the previous page acknowledgement;
their rAF sample is read
before the quiet window so idle frames cannot hide interaction jank. Text
queries use DartPDF's viewer search and Chromium's PDF plugin controller, and a
result-count mismatch fails the run. This deliberately includes scheduling,
interpretation, image decode, raster, upload, and presentation—the delay a user
sees—not just an engine's preferred internal boundary.

Capture starts at action dispatch and runs concurrently with the engine-state
wait. Cold open is the deliberate exception: full screenshot polling begins at
the matched logical-document boundary (real page count/document dimensions),
before first-page readiness, because capturing the still-booting SkWasm shell
perturbs Wasm compilation. The pre-navigation baseline hash is captured before
the cold-open stopwatch begins, so blank-tab JPEG work is instrumentation, not
document latency.

`Page.captureScreenshot` samples compositor pixels before its encoded JPEG is
returned. Timestamping only the response charged content-dependent encoding to
the engine and imposed a roughly 45–60 ms measurement floor. Screenshot mode
therefore timestamps a changed frame at the earlier of response completion and
request start + `PERF_SCREENSHOT_SAMPLE_DELAY_MS` (36 ms by default). The
checked-in transferred-`OffscreenCanvas` probe found a consistently-old frame
at 32 ms on the reference Chrome 151 host; 36 ms is a conservative upper bound.
Run `tool/perf.sh screenshot-probe` on another controlled runner before gating.
Raw capture-duration summaries and the selected bound are recorded in NDJSON.

Cold-open tracking begins before navigation, then finds the first occurrence
of the eventual stable page hash. This excludes bootstrap and white-page
placeholder frames without racing a fast renderer that paints before a
readiness poll. Page/zoom first-visual and final-stable samples are both kept;
the latter remains the budgeted metric.

Page commands snap in both adapters: Chromium's `viewport.goToPage()` and
DartPDF's zero-duration `animateToPage()`. DartPDF's optional 250 ms smooth
near-page animation is therefore not charged against PDFium's instant jump.

Headline ratios are `dart-pdf / PDFium` (lower is better). The initial
definition of “PDFium-class” in `competitive_scenarios.json` is no more than
15% slower at p50, 25% slower at p95, and 25% higher whole-browser RSS. The
same p50/p95 limits cover wheel journeys, with a 1.25× rAF-p95 ceiling; the
text scenario applies them independently to cold and warm queries. These
are aspirational budgets until a controlled machine has enough samples; use
`--gate` only on stable hardware. Raw per-action samples, p50/p95 aggregates,
Chrome version, network bytes, screencast payload, RAF intervals, Flutter
frame diagnostics, and browser-process-tree RSS are appended to
`results-competitive-<scenario>.ndjson`.

Cold-open reporting keeps two clocks. `open*` starts before navigation and
therefore includes the real Flutter/SkWasm application-shell bootstrap.
`document*` starts when the server receives `/perf.pdf` and isolates the
fetch/open/first-page pipeline. Both remain visible: the narrower metric is
diagnostic evidence for where to optimize, never a replacement that hides app
startup from a full-file parity gate. The matched range scenario deliberately
gates `document*`: its purpose is transport/document parity after both viewers
request the PDF, while `open*` stays a cold-app bootstrap diagnostic.

For `transport: "range"`, the Dart page first reaches an initialized loading
shell with `deferStart=1`. The driver then calls `__perfStartDocument()` and the
server timestamps the first `/perf.pdf` request. This prevents a screenshot or
SkWasm bootstrap from racing the start boundary. `fullyLoadedMs` is measured
from that first request; `navigationFullyLoadedMs` preserves the raw
navigation-relative value. `openNetwork` and `network` each record bytes and
request counts, and the aggregates expose p50/p95 for all four. A 206/416-aware
local server is part of the harness, so a malformed or multi-range request
cannot silently become a full-file success.

The sparse Dart arm opens `PdfHttpByteSource` with one first-paint page and an
incomplete page-tree walk, paints that page without waiting for Flutter's
worker pool, then hands the complete bytes to the normal worker renderer. The
temporary page-count hint is preview-only; the full document remains the
authoritative model after handoff. One identity-keyed `SharedArrayBuffer` is
reused by sibling workers for an immutable document revision.

Important boundaries:

- The four content-shape scenarios and `parity-long-cad` serve a full response
  to both engines. `parity-progressive-cad` is the explicit transport tier: the
  same endpoint honors RFC 7233 ranges for both, records bytes and request
  counts at open and full handoff, and gates request amplification separately
  from transferred bytes.
- Compositor screencasting has a cost. The runner uses the same downscaled,
  low-quality stream for both engines and reports its frame payload; compare
  interleaved ratios, not a single absolute number.
- Flutter's SkWasm backend presents through an offscreen canvas that Chrome's
  DevTools screencast may omit. SkWasm competitive runs default to
  `PERF_VISUAL_CAPTURE=screenshot`, and explicitly requesting `screencast`
  fails instead of recording placeholder timings. Screenshot mode polls full
  composited screenshots for both engines with the same hash/quiet-window
  rule. The result records `visualCaptureMode` and `webBackend`, so histories
  cannot silently mix the two methods.
- `PERF_VISUAL_CAPTURE=none` disables all screenshot/screencast requests for
  diagnosing whether capture perturbs Flutter frame timing. Its visual values
  are intentionally invalid, so the runner suppresses the parity report and
  refuses `--gate` in this mode.
- `PERF_BROWSER_COOLDOWN_MS` inserts an out-of-band pause after each fresh
  browser for diagnosing process-teardown or thermal interference. It defaults
  to zero and is recorded; it is not a substitute for a stable runner.
- Results record Chrome's GPU device, display/Skia backend, and graphics
  feature-status map. Check these before comparing machines; a software run
  and an ANGLE/Metal or Vulkan run are different experiments.
- Dart-side diagnostics retain Flutter `{vsync-start,build,raster,total}` frame
  timings per cold-open, page-jump, zoom, and wheel action. Timestamp windows,
  rather than callback-list offsets, keep Flutter's delayed timing batches
  assigned to the action that actually produced them. These frames are
  profiling evidence only; the common composited visual metric remains the
  parity gate.
- The PDFium adapter validates the private Chrome PDF-viewer methods it uses
  (`viewport.goToPage` and `viewport.setZoom`) and fails loudly if a Chrome
  update changes that contract.
- `parity-long-cad` covers normalized scrollbar scrubbing, same-process warm
  reopen, continuous peak RSS, and a settled-memory tail. Wheel and text-query
  stages cover the other shared desktop-web interactions. Touch/fling remains
  a physical-device platform tier, not something inferred from headless Chrome;
  the existing Dart-only `search` and `scroll` scenarios remain useful deeper
  diagnostics.

The full methodology and acceptance contract live in
[`doc/benchmarks/pdfium-parity.md`](../../../doc/benchmarks/pdfium-parity.md).

`surface-check` renders each sampled page through the established SkWasm
renderer and the default-off worker-owned Canvas2D path at identical view
transforms. It checks channel error, foreground recall/precision, and both
bounds of foreground coverage. Scenario-specific budgets live beside the
journey in `competitive_scenarios.json`; PNG baselines, candidates, diffs, and
`report.json` are written under `/tmp` by default. Up to four journey zoom legs
are preserved, including duplicates, so `2x,1x,3x,1x` checks both the 3×
viewport-region path and the exact repeated-size cache result.

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
   `_drive()` in
   [`harness.dart`](../perf_harness/lib/harness.dart), emit numbers with
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

- [`harness.dart`](../perf_harness/lib/harness.dart) — the standalone Flutter web
  entrypoint. Dispatches on `?scenario=`, drives the real viewer/editor, and
  exposes `window.__perfDone/__perfError/__perfDump()/__perfFrames()/__perfMetrics()`.
- [`driver.mjs`](driver.mjs) — Node + `puppeteer-core` (system Chrome, no
  download). Resolves `--scenario` from `scenarios.json`, serves `build/web` +
  the scenario's PDF at `/perf.pdf`, drives Chrome, scrapes the trace/frames/
  metrics, prints a summary, appends one envelope per run.
- [`bench.mjs`](bench.mjs) — the one-command A/B orchestrator (`webdiff`).
- [`build.sh`](build.sh) — compiles the render worker + the harness bundle into
  `app/build/web`. `WASM=1` selects SkWasm; `PERF_BUILD_OUTPUT` can keep a
  side-by-side build elsewhere (relative paths resolve from the directory that
  invoked the script). Run once per code change.
- [`loop.sh`](loop.sh) / [`report.mjs`](report.mjs) — the legacy scroll loop +
  its trend summary (still `results.ndjson`). Single-scenario `web` runs write
  per-scenario `results-<scenario>.ndjson` so trends never mix workloads:
  `PERF_RESULTS=results-search-text.ndjson node report.mjs 20`.

## Env (driver)

| var | default | meaning |
|-----|---------|---------|
| `PERF_SCENARIO` | *(none)* | scenario name (same as `--scenario`); picks kind + PDF + params |
| `PERF_PDF` | scenario's PDF, else legacy CAD | override the served PDF |
| `PERF_WEB_DIR` | `PERF_BUILD_OUTPUT`, else `app/build/web` | the built bundle to serve; explicitly overrides the build output |
| `PERF_BUILD_OUTPUT` | `app/build/web` | build destination and competitive runner fallback serve directory |
| `WASM` | `0` | `1` builds/labels the harness as SkWasm; competitive runs then default to screenshot capture |
| `PERF_VISUAL_CAPTURE` | backend-aware | `screencast` for JS CanvasKit, full-compositor `screenshot` for SkWasm, or diagnostics-only `none`; SkWasm+screencast is rejected |
| `PERF_WEB_BACKEND` | inferred | explicit result label when serving a side-by-side prebuilt backend |
| `PERF_DART_QUERY` | *(empty)* | query parameters applied only to the Dart harness, for recorded A/B controls such as `rasterCacheMb=0` or the default-off plain-text `domSurface=1` probe |
| `PERF_PAGES` / `PERF_ZOOMS` | scenario | comma-separated page-jump and zoom sequences for repeating a real-document trace through the competitive journey |
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
