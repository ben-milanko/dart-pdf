# 2026-07-18 — Performance tooling suite (zero-cost instrumentation + capture/compare/trend)

Groundwork for the Bluebeam-level performance push: the render path was
already well-instrumented (PdfPerfLog, PdfRenderTrace + gate, the Chrome
loop, the pdfium harness — perf issues #213–#219/#306 all closed), but
nothing below `dart_pdf_editor` was timed, no run was comparable to any
other run, and nothing tracked history. This session added both halves.
Hard constraint honored throughout: **zero impact on regular API users**.

## In-library: the `PdfPerf` facade (pdf_cos)

- `packages/pdf_cos/lib/src/perf/perf.dart`, exported via the new
  entrypoint `package:pdf_cos/perf.dart` — deliberately NOT exported from
  `pdf_cos.dart`; doc-declared unstable, no semver. Enum-indexed phases
  (`PdfPerfPhase`), counters (`PdfPerfCount`), rare events, a pluggable
  `sink`, `PdfPerfStats` (snapshot/reset/addInto/toJson/fromJson/format),
  `PdfPerfBudget` tripwires.
- Cost tiers: `--dart-define=PDF_PERF=false` **dead-code-eliminates the
  whole facade** (const-first guard: `if (!kPdfPerfCompiledIn || !_enabled)`),
  verified by `tool/check_perf_dce.sh` (grep of `PdfPerf.debugDceMarker` in
  compiled JS, both polarities — the compiled-in leg needs the probe to
  assign `PdfPerf.sink`, else dart2js whole-program analysis proves the sink
  null and strips the marker anyway). Compiled-in-but-disabled (the default)
  = one branch, no allocation, no clock reads — proven by
  `PdfPerf.debugInitialized` staying false across a full workload
  (`pdf_cos/test/perf_test.dart`, which also asserts byte-identical save
  output enabled-vs-disabled).
- Instrumented: `CosDocument.open`/xref parse/**recovery** (counter +
  event — an accidental recovery fallback is a silent 10–100x open bug),
  `getObject` (count only — hottest path, no clock), object-stream index,
  stream decrypt, per-filter decode times + decoded bytes (`filters.dart`
  chain), content tokenize (the **cursor** owns contentOps/contentBytes —
  it already counted ops for `operationLimit`, flushed once at stream end,
  so the hot loop pays nothing; `parse()` keeps only the phase timing),
  incremental + full save, encryptObjectGraph, ranged byte-source traffic.
  Upper layers: page-tree walk, font parse (+failed counts), text extract,
  ByteRange patch, fallback-font embeds.
- Isolate-local by design. `PdfPerfLog.enabled` is now a getter/setter that
  bridges the facade on (lazily for the dart-define path). Worker plumbing:
  isolate `_WorkerInit.perfEnabled` (sink → developer.log); web worker
  enables on the existing `timings` init flag and piggybacks a per-job
  snapshot (`cosStats` JSON) on results — `PdfRenderTrace.cosStats` carries
  it, and `captureOffThread` attaches a before/after delta.
- New gate riding plain `dart test`:
  `pdf_document/test/perf_gate_test.dart` — budget tripwires + the
  structural `xrefRecovered == 0` assertions on well-formed fixtures.

## Dev-side: capture / compare / trend (`tool/perf/`)

- **Envelope schema v1** (`tool/perf/SCHEMA.md`): additive wrapper
  (schema/suite/scenario/rev/env/ts/metrics) around the existing
  `benchmark/` JSON — `compare.py` verified byte-for-byte unaffected.
  Emitters updated: `benchmark_interpret.dart`, `pdfium_benchmark.py`,
  `benchmark_render_test.dart`, `app/tool/perf/driver.mjs` (+ a `metrics`
  block).
- **`tool/perf.sh`** front door: sweep / interpret / render / web /
  compare-pdfium / gate / dce / diff / report.
- **`perf_sweep.dart`** (pdf_graphics/tool): per-file killable child
  processes (survives pdfjs-hostile; clean per-file `maxRss`), best-of-N
  openMs/firstPageMs/interpretMs/extractMs/saveMs, `--phases` attaches
  PdfPerf snapshots, scenario support. Scenarios in
  `tool/perf/scenarios.json` with a `ciSafe` flag (gitignored `corpus/`
  scenarios skip gracefully). **Deterministic seeded CAD generator**
  `pdf_cos/tool/gen_cad_pdf.dart` (A1 sheets, dense linework/hatch/labels,
  byte-identical across machines — LCG gotcha: `0x8000000000000000` is
  int64-negative on the VM; divide via `(x >> 11) * (1.0 / (1 << 52))`).
- **`diff.dart`**: pairs results by file, judges each metric by the median
  ratio with 3-MAD outlier exclusion (outliers listed, never counted),
  `--targets` renders the aspirational budgets, exit 1 gates.
  **`perf_diff.sh <ref> [scenario]`**: cached git worktree per sha,
  interleaved ABAB runs, `merge_runs.dart` best-of merge; bootstraps the
  harness+facade files into pre-tooling refs (additive only — the ref still
  measures its own lib code). Self-diff and HEAD-diff verified; sub-ms
  metrics need the default 4 iterations (1-iteration smokes show ±10%).
- **Counter gate** (`perf_count_gate.dart` + committed
  `tool/perf/baselines/counters.json`): deterministic structural counters
  (objects loaded, bytes decoded per filter, content ops, fonts parsed,
  saved bytes …) over fixtures + 6 Ghent files + the seeded CAD sheet;
  3% band; `--update-baseline` re-baselines as a reviewable diff. Runs
  per-PR in ci.yml next to the DCE check. Verified deterministic
  run-over-run and that perturbation fails with a readable table.
- **CI**: `perf-nightly.yml` (cron 03:17) — CI-safe sweeps + pdfium column,
  **baseline-rerun ratio check** (previous nightly's sha re-measured on the
  same runner via perf_diff.sh, threshold 1.15 → job failure emails), then
  history + dashboard pushed to the orphan **`perf-data`** branch with the
  default token. `perf-web.yml` (manual) runs the Chrome loop on the
  generated CAD corpus. One-time setup still needed: repo Settings → Pages
  → serve from `perf-data`.
- **Dashboard** (`tool/perf/report/build_report.mjs`, zero-dep node):
  static index.html, inline SVG trend charts per scenario×metric, budget
  lines + PASS/MISS vs `tool/perf/targets.json` (the Bluebeam ambition made
  checkable — never a PR gate), per-point commit tooltips, light+dark.
- pdfium harness gained `--first-page` (open→page-0 rendered, the Revu
  time-to-first-paint proxy) and `--save` (FPDF_SaveAsCopy) — opt-in flags
  so default renderMs stays comparable with the committed README tables.
  `perf_harness.dart` gained `?zoom=N` settle cycles.

## Gotchas for future sessions

- **Never edit sources or run builds/tests while a sweep runs**: sweep
  children compile from source at spawn; an Edit mid-run produced 9
  consecutive exit-254 compile-error children (looked like a corpus
  problem, wasn't). Same reason the Chrome loop README already banned
  concurrent CPU work; now it bans concurrent edits too.
- The counter gate initially showed `contentOps: 0` everywhere — the
  interpreter tokenizes via `ContentOperationCursor`, not
  `ContentStreamParser.parse`; counts had to live in the cursor.
- `test/ghent_render_test.dart` `2-SPOT/GWG030_Gray_K_black_OP_X1.pdf`
  fails its pixel baseline (11.1%) on clean main (dfdc2d9e) too —
  pre-existing, unrelated to this work, needs its own look.
- pdf_cos gained a public library file (`lib/perf.dart`) → next release is
  a lockstep minor bump.
