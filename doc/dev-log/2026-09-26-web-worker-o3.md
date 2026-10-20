# Web render worker compiled at dart2js -O3

`dart run dart_pdf_editor:build_web_worker` compiled the worker at `-O2`
from the first worker PR (#75) until now. No rationale was recorded; the
only earlier mention of the level is `dart compile js -O2` as a
verification command in 2026-07-11-web-strip-worker.md. The app bundle has
always been `flutter build web --release`, which is dart2js `-O4`, so the
main thread already runs the same pdf_cos/pdf_document/pdf_graphics code
with fewer checks than the worker had.

## What changed

- `packages/dart_pdf_editor/bin/build_web_worker.dart`: the level is now
  `defaultWorkerOptimizationLevel = 3`, overridable with `-O<n>` or
  `--optimization-level <n>` (1-4). `--no-optimize` still passes no `-O`
  flag at all (dart2js's own default, -O1), and its help text says so. The
  old text said "Skip -O2". Flag parsing moved into `WorkerBuildOptions`
  so `test/build_web_worker_test.dart` can pin the default without
  running dart2js.
- The tool now exits non-zero on failure. `main` returned 64 or dart2js's
  exit code, but `dart run` ignores main's return value, so every failure
  exited 0: "error: worker compile failed (exit 1)" was printed and the
  CI step passed. main now sets `exitCode`. Every deploy, preview,
  release and publish workflow (plus `tool/release.sh` and
  `app/tool/build_web.sh`) builds the worker through this tool, so no
  workflow edits are needed for either change.
- `strict-casts: true` in the `analysis_options.yaml` of pdf_cos,
  pdf_document and pdf_graphics. All three were already clean, including
  test/ and tool/.
- `doc/render_worker_web.md` documents the level and the override.

## Why -O3 and not -O4

`dart compile js -h -v`: -O3 is -O2 plus `--omit-implicit-checks`, and -O4
adds `--trust-primitives`.

- **Implicit checks** are the parameter/covariance `as` checks dart2js
  emits on every generic `List` store, `add` and `setRange`. They showed
  up in every -O2 worker profile (`_generalAsCheckImplementation`,
  `_isTestViaProperty`, `_arrayInstanceType`). Dropping them is only
  unsafe if code relies on an implicit downcast throwing. strict-casts
  makes the analyzer reject implicit downcasts from `dynamic`, so the
  worker's libraries can't pick up such a dependency. No `on TypeError`
  handler exists anywhere in the core libraries. Covariance checks, such as
  a `List<int>` used through a `List<num>`, fall outside strict-casts; the
  corpus identity run below is the evidence that nothing depends on those.
- **`--trust-primitives`** also drops bounds checks: an out-of-range
  typed-array read yields `undefined` instead of throwing. The `on
  RangeError` recovery paths in pdf_cos (`document.dart`,
  `byte_source.dart`) would stop firing, and a scan loop that relies on
  the throw to end could spin on a truncated or hostile file, which is a
  hang rather than a wrong pixel. -O4 would also give about 1.2-1.3x
  more on image decode and save, and a 4% smaller gzipped worker. It
  first needs a node-run dart2js smoke over the pdf.js broken-file suite
  and truncated corpus copies that asserts termination with per-file
  timeouts, as well as hash equality. The main thread already carries
  that exposure today.

## Measurements

The machine was heavily loaded throughout (load average 15-120 on 10
cores). All A/Bs were interleaved, and the node numbers use instructions
retired, which load barely affects. Everything below was measured on main
at e8b20157 (after #957-#959).

**Real Chrome.** One perf-harness bundle was built from main with
`app/tool/perf/build.sh`, then copied into two web dirs that differ only in
`pdf_render_worker.dart.js` (the -O2 file is main's own build). I drove
`app/tool/perf/driver.mjs` over them for 5 rounds, alternating the arm
order. The worker time is the sum of `worker=` over the `webworker phase
kind=record` lines.

| scenario | worker record ms, O2 -> O3 | O3/O2 |
| --- | --- | --- |
| open-plan | 321.0 -> 260.0 | 0.81 |
| open-diagram | 294.0 -> 238.0 | 0.81 |
| read-text | 93.0 -> 78.0 | 0.84 |
| wheel-text | 35.0 -> 30.0 | 0.86 |

- O3 was faster in all 20 paired rounds.
- The user-facing numbers barely move, because first paint and navigation
  are dominated by main-thread open, build and replay, which this change
  doesn't touch.
  - openFirstContentMs: 377 -> 354 on open-plan (0.94), 230 -> 234 on
    open-diagram (1.02, noise).
  - read-text readFirstP50Ms and wheel-text wheelSharpWhileScrollingPct:
    unchanged.
- No metric got worse than 1.05x. The worst was open-diagram openBytesMs
  at 1.036, the main-thread file fetch, which this doesn't touch.

**Node kernels.** I used a scratch bench over the worker's pure-Dart calls.
Per-rep cost is `(X(reps=4) - X(reps=1)) / 3` for instructions retired and
process CPU, over 5 interleaved rounds, O2/O3. The process-CPU clock ticks
in 3.3 ms steps, so the CPU column is coarse for the small kernels.

| kernel | instructions | CPU |
| --- | --- | --- |
| interpret, plan set | 1.35x | 1.23x |
| interpret, dense diagram | 1.19x | 1.10x |
| interpret, text report | 1.48x | 1.00x |
| text extraction, booklet | 1.44x | 1.33x |
| image decode, scan | 1.02x | 1.00x |
| pure-Dart inflate (the browser-flate fallback) | 1.63x | 1.38x |

In the real worker the in-Chrome gain is smaller (about 1.15-1.2x) than
these kernel ratios, because transfer, serialization and browser decode
don't change. Image decode doesn't benefit: the same kernel measured 1.23x
a day earlier, on main before #957-#959, but main's own image path has
since dropped from 739 M to 460 M instructions per rep and the -O3 margin
went with it.

**Identity.**
- The `recordHash` kernel (open, record page plus annotations, serialize
  with image decode, extract text, and fold in every exception type)
  matches between O2 and O3 on 240 of the 252 `test_corpora` files and on
  all 53 files of a private real-world corpus.
- Of the other 12, 7 are password-protected and throw the same
  `CosPasswordException` ("password required or incorrect") at open in
  both builds. The hash differs only because it includes the minified
  `runtimeType` name, which differs between builds. The other 5 fail to
  parse identically.
- `build_web_worker --optimization-level 2` reproduces main's worker byte
  for byte.
- The CI worker-compiles Chrome tests (`render_worker_sparse_web_test`,
  `compression_worker_test`, `render_worker_text_reuse_test`) pass against
  the -O3 bundle: 18 passed, and 2 skipped for SharedArrayBuffer, as in CI.

**Size.** The worker drops from 1,628,643 to 1,610,503 B, and from about
715 KB to 711 KB gzipped. The change doesn't affect worker startup.

## Gotchas

- The nightly web trends and the web perf harness build their worker
  through this tool, so worker-side phase timings step down about 15-20% when
  this lands. That is expected; it is not a regression in the baseline.
- strict-casts applies to a whole package, test/ and tool/ included.
  dart_pdf_editor's lib/ is also clean, but its tests have 10 implicit
  downcasts from `dynamic`, in three files (the editing guides, high-zoom
  tile and overprint tests), so it was left off there.
- `Future<int> main` is a trap in any `bin/` tool: the returned int is not
  the exit code. Set `exitCode`.
