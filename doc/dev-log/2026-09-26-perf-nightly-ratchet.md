# perf-nightly: keep history on red nights, ratchet night over night

The nightly perf job had been red every night since 2026-07-26 (62 of 62
runs through 2026-09-25), and for most of that time the red told nobody
anything new. This session makes it a per-night signal again.

## What was wrong

- **The append step was skipped on red.** `Append history + rebuild
  dashboard` had no `if:`, so it only ran when the ratio check passed. The
  ratio check's baseline (`PREV_SHA`) is the last commit on the perf-data
  history, so after the first red night it never moved: every one of the 62
  logs says `ratio check vs 1cf882ca...`. The perf-data branch and the
  dashboard stopped at `perf-nightly: 2026-07-25 @ 1cf882ca`, and none of
  the 62 nights' envelopes were kept. The vm-sweep envelopes went to
  `--out /dev/null` plus the runner's history file, so they are gone. The
  flutter-render envelopes survive only in the Actions logs, which keep 90
  days, so the first ones expire around 2026-10-24.
- **The first red night was an accepted cost.** 07-26 was #602's colorant
  buffer (interpretMs 1.60x). Its dev-log (2026-07-25-overprint-colorant-
  buffer.md, "Where it landed, honestly") accepts that cost, but the
  workflow had no way to record an acceptance. From then on every new step
  just looked like "still red":
  - 08-25 (#755): firstPageMs went 1.28x -> 8.44x and peakRss 1.04x -> 1.29x
    against the frozen baseline. The same night ghent-render went up 9.5x
    and jbig2-scanned-render 1.84x.
  - 08-27: interpretMs up about 12%. About a third to a half of that is
    #811/#812 (+5-9% on small overprint pages in a local A/B). The rest
    coincides with a hosted-runner image upgrade.
  - The drift after 08-25 (firstPage 8.4x -> 11.5x) is noise. The same
    commit measured on different nights spans 8.6-13.3x.
- **Nothing compared the flutter-render envelopes.** The ratio check only
  diffs the VM `save-incremental` and `ghent-suite-open` sweeps. The render
  suites went only to the dashboard, and the dashboard was frozen.

## What changed

`.github/workflows/perf-nightly.yml`, in step order:

1. **Resolve the previous nightly's commit** (`id: prev`). This runs first,
   before anything touches perf-data: the append step's worktree advances
   the local perf-data ref, so a later read would return HEAD. The previous
   commit comes from the last line of `history/nightly-verdicts.jsonl`. Only
   the nightly writes that file, whereas perf-backfill appends OLD commits
   to the envelope history, so the envelope tail can't be trusted. Until
   the verdict file exists it falls back to the vm-sweep tail.
2. **Sweeps** (`id: sweeps`), unchanged apart from a step timeout.
3. **Ratio checks**, one step per baseline, both `continue-on-error: true`
   and both running `tool/perf/nightly_ratio_check.sh`:
   - `id: ratio` checks against the previous nightly.
   - `id: accepted` checks against `tool/perf/baselines/nightly-accepted.sha`
     on Sundays (`date -u +%u` = 7) or when the `check_accepted` dispatch
     input is set, and records `not-run` otherwise.

   Each check records `ok|regressed|error|skipped` as a step output.
   `regressed` needs perf_diff's `VERDICT: REGRESSED` line as well as its
   exit 1, because perf_diff.sh also exits 1 when a side produced no
   envelopes (merge_runs.dart) or a `set -e` command fails. Any other
   failure is `error`. An empty or unknown previous-nightly sha is
   `skipped`, but a `nightly-accepted.sha` that does not name exactly one
   commit is `error`, so a typo can't quietly turn the weekly check off.
   `ghent-suite-open` now runs 4 interleaved iterations instead of 2,
   because it carries firstPageMs, which is a few ms per file.
   `save-incremental` stays at 2.
4. **Render trend** (`id: render_trend`, `continue-on-error: true`). This
   runs `tool/perf/render_trend.dart` on tonight's
   `out/perf-history/flutter-render.ndjson` against perf-data's
   `history/flutter-render.ndjson`. It writes a table to the step summary.
5. **Record tonight's verdict.** This writes one JSON line:
   `{date, sha, prevSha, acceptedSha, verdict, checks{nightly, accepted,
   renderTrend}, runId}`. It runs only when the sweeps succeeded.
6. **Upload tonight's envelopes** (`if: always()`, 90 days), so a failed
   append no longer loses a night. The artifact name carries
   `github.run_attempt`, because a re-run keeps the run id and
   upload-artifact refuses a duplicate name.
7. **Append** (`if: !cancelled() && steps.sweeps.outcome == 'success'`). It
   also appends the verdict line to perf-data's
   `history/nightly-verdicts.jsonl` and puts the verdict in the commit
   subject. It does not use a bare `always()`: after a failed or cancelled
   sweep, that would append partial history and make an unmeasured commit
   the next night's baseline.
8. **Fail on a red verdict.** This is the last step, so a red night still
   emails the maintainer after the history is safe.

**Timeouts.** A job timeout is a cancellation, and the append is
`!cancelled()`, so a job that times out loses the night. That makes it the
one failure this design must never hit. Every step from the sweeps through
the append has its own `timeout-minutes`: sweeps 45, each ratio check 80,
render trend 10, verdict 5, upload 10, append 15. A check that runs past
its own limit fails its step, `continue-on-error` absorbs it, the verdict
records `error`, and the history still lands. The job's limit (270, under
the hosted runner's 360) covers the sum of those step limits plus 20 min
of setup, which is measured at under 1.5 min. `tool/perf/nightly_test.dart`
holds the workflow to that budget.

The runtime projection comes from the 68 logged nights 07-20..09-25:

- Sweeps take 15-28 min.
- One side run takes about 2.4-4.6 min for save-incremental and 2.7-5.2
  min for ghent-suite-open. That puts one baseline's check (2+2 and 4+4
  side runs) at about 32-60 min, median 52.
- **A weekday runs about 49-90 min, median about 80. A Sunday with both
  baselines runs about 81-150 min, median about 131.**

The first cut of this change set the job to 150 min with no step limits,
and its figures (66 and 110 min) came from the fast 09-24 night. On the
slowest logged night a Sunday projects to about 150 min, right at that
limit, so a slow Sunday would have timed the job out mid-check.

Also changed:

- `tool/perf/baselines/nightly-accepted.sha` = 812f8e5d (#755). The weekly
  check's baseline moves only in a reviewed PR, the same model as
  counters.json and `--update-baseline`. It is the first commit past both
  known steps. #602's cost is accepted in its dev-log. #755's
  OutputIntent/first-page cost is still open, so a fix for it will read
  "improved" and everything after it is judged. #956 (glyph outline paths
  built only where they are read) already takes back part of #755's
  interpret cost, so it reads "improved" here. #811/#812 push the other
  way, about 1.07-1.12x interpretMs on small overprint pages (1.07x in a
  local A/B, about 1.12x on the CI nights), so the first Sunday's
  interpretMs is the net of the two. Bump the file past #811/#812 if they
  are accepted.
- `tool/perf/render_trend.dart` + `render_trend_test.dart` (wired into
  ci.yml next to the other tool tests). Per scenario:
  - Each file's baseline is the median of its renderMs over up to 5 prior
    nights.
  - The verdict is the median of the per-file ratios, red at >= 1.4x. One
    slow file is listed but never decides it.
  - A flagged night starts a new level: later nights never look back past
    it. So a step is red once, the same one-alert-per-step behaviour as the
    VM ratchet, and the two-month history gap costs one red night.
  - Nights are ordered by commit date, then ts, like the dashboard, so
    backfilled points sit where they belong.
  - `--replay <history>` prints every night's verdict.
  - **The reset has a price.** The night after a flag is judged against
    that one night alone. If the flag was a noise spike, a real step no
    bigger than the spike that lands in the next night or two reads about
    1.0x and is absorbed without its own flag. A spike that just recedes
    is harmless: the next night reads "improved", and the spike drops out
    of the median as nights accumulate. A spike followed by a step can't be
    told apart from a step that held, and without the reset every real step
    flags three nights running, so the reset stays. None of the 277
    replayed verdicts was a noise flag (the noisiest unflagged night was
    1.22x). If a flagged night looks like noise, watch the dashboard for
    the next two nights. render_trend_test.dart pins both behaviours.
- Envelope `env` gains `flutter` (from `PDF_PERF_FLUTTER_VERSION`, which
  nightly.sh exports from `flutter --version --machine`) and `runnerImage`
  (`$ImageOS/$ImageVersion`, set on hosted runners). These go in
  `perf_run_context.dart`'s envInfo and in benchmark_render_test.dart
  (inlined there because render_backfill grafts that file onto old
  commits). Mid-series the CI Flutter went 3.44.8 -> 3.47.0 -> 3.47.4 and
  the runner image rolled over, with nothing on record to show it.
- `build_report.mjs` reads `nightly-verdicts.jsonl`. It shows a verdict
  table for the last 14 nights, rings red nights' points on every chart,
  and puts the Flutter version and runner image in each section's meta
  line. With no verdict file its output is unchanged apart from one CSS
  rule. Both loaders skip a line that parses to something other than an
  object (`null`, a number, an array). Before, a `null` line threw a
  TypeError, and because the page is rebuilt in the step that commits the
  history, one bad line would have frozen perf-data again every night.

## Evidence

- **Workflow emulation (32 checks, all pass).** A small emulator ran the
  real YAML's `run:` scripts with `bash -eo pipefail` in step order. It
  honoured `if:` (with the implicit `success()`), `continue-on-error`,
  step `env:` expressions, `$GITHUB_OUTPUT`, the step summary, and step
  and job `timeout-minutes` scaled to 0.5 s per minute. A job timeout
  cancels the job. The runs used a throwaway repo (a bare origin with
  main + perf-data frozen like today, and a fresh clone per night) with
  stub `nightly.sh`, `perf_diff.sh` and `date`. Results:
  - Nightly regressed: the job goes red in its last step, the history and
    a `regressed` verdict line are appended, and the artifact is uploaded.
    The next night compares against that night's commit, not the frozen
    one.
  - Clean night: green, and the verdict is appended.
  - Unchanged HEAD: the check is skipped and the night is still recorded.
  - Accepted baseline regressed (dispatch input): red, with
    `checks.accepted = regressed`. Sunday runs the accepted check; Monday
    does not.
  - Render step: red once. The next night is judged against the new level
    and is green.
  - A perf_diff error, including exit 1 with no verdict line: recorded
    as `error`, not `regressed`.
  - A typo in `nightly-accepted.sha` on a Sunday: `error`, red, nothing
    measured.
  - A slow Sunday (every perf_diff call 50 min): the accepted check runs
    past its 80-min step limit and records `error`, and the verdict and
    history are appended. The pre-fix version of this workflow (one ratio
    step, no step limits, 150-min job) times out mid-check in the same
    run, and perf-data is untouched.
  - Failed sweep or cancellation: perf-data is untouched. The upload still
    runs.
  - The origin/main workflow under the same stubs reproduces the bug: the
    red night skips the append, and the next night still compares against
    the frozen commit.
- **Render-trend replay.** The replay covered 277 night x scenario
  verdicts: perf-data's history through 07-25 plus the flutter-render
  envelopes printed in the 62 nightly logs, 07-25..09-24.
  - With the level reset, it flags exactly 08-25: ghent-render 9.52x and
    jbig2-scanned-render 1.845x. There are no other flags. The highest
    unflagged ratio is 1.223x (jbig2, 08-28).
  - The plain rule, "median of the prior 5" with no reset, flags
    08-25, 08-26 and 08-27 for both suites: three red nights per step. Its
    highest unflagged ratio is 1.29x, on the night the window straddles
    the step.
  - First night after this lands, with history frozen at 07-25 and 09-23's
    envelopes: ghent-render 7.65x is red. jbig2 is skipped because it has
    no history before 07-26. The next night reads 0.92x.
- **`tool/perf/nightly_test.dart` (25 checks, in ci.yml).** It runs
  nightly_ratio_check.sh against a stub perf_diff in a throwaway git repo,
  holds the workflow to its timeout budget, and feeds build_report.mjs
  `null`/array/number lines. Reverting any one of the fixes fails it:
  - mapping every exit 1 to `regressed` fails 1 check;
  - the old concatenate-and-skip reading of the sha file fails 4;
  - dropping the ratio steps' timeouts fails 1, and so does a 200-min job
    limit;
  - the old loaders fail 2;
  - the old artifact name fails 1.
- **Lint.** actionlint (with shellcheck) is clean on the workflow.
  shellcheck is clean on nightly.sh and nightly_ratio_check.sh. PyYAML
  parses the workflow.

## Expect after merge

- The first run (dispatch or schedule) is red against 1cf882ca, as every
  night has been, but this time the history and verdict are appended. The
  next night compares against that commit.
- The render trend is also red once on that first night. perf-data's
  render history ends at 07-25, before #755's 9.5x ghent-render step.
- The first Sunday's accepted check (against #755) is the first real
  reading of everything after #755.

## Gotchas

- `continue-on-error` makes `steps.X.conclusion` success while
  `steps.X.outcome` stays failure. Gate on `outcome`.
- A step that runs past its own `timeout-minutes` is marked Failed, and
  the runner then applies `continue-on-error` as it would for any other
  failure (`ApplyContinueOnError` in actions/runner). Outputs the step
  wrote before it was killed are kept, because the file commands are
  processed in a `finally`. A **job** timeout is different: it cancels
  the job, and every `!cancelled()` step is skipped.
- The verdict file is `.jsonl` on purpose. build_report.mjs charts every
  `*.ndjson` line as an envelope, so a verdict line there would show up as
  an "unknown" section.
- "Two consecutive red nights" does not work with a night-over-night
  baseline: the second night compares against the regressed one. That is
  why firstPageMs got more iterations instead.
- The lost 07-26..09-24 nights are not backfilled here, because that needs
  a perf-data push. The flutter-render envelopes can still be harvested
  from the logs until about 10-24. The vm-sweep ones never reached the
  logs, so recovering them means re-running `tool/perf/backfill.sh` over
  the nightly commits.
- A moving baseline absorbs creep under 15% a night. The weekly accepted
  check covers that for the VM sweeps. For the render suites, the
  now-updating dashboard is the backstop.

## Files

`.github/workflows/perf-nightly.yml`, `.github/workflows/ci.yml`,
`tool/perf/nightly_ratio_check.sh`, `tool/perf/nightly_test.dart`,
`tool/perf/render_trend.dart`, `tool/perf/render_trend_test.dart`,
`tool/perf/baselines/nightly-accepted.sha`, `tool/perf/nightly.sh`,
`tool/perf/report/build_report.mjs`, `tool/perf/SCHEMA.md`,
`packages/pdf_graphics/tool/perf_run_context.dart`,
`packages/dart_pdf_editor/test/benchmark_render_test.dart`.
