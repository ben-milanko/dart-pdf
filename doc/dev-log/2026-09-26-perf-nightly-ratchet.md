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
2. **Sweeps** (`id: sweeps`), unchanged.
3. **Ratio checks** (`id: ratio`, `continue-on-error: true`). The `nightly`
   check runs against the previous nightly. The `accepted` check runs
   against `tool/perf/baselines/nightly-accepted.sha`, on Sundays
   (`date -u +%u` = 7) or when the `check_accepted` dispatch input is set.
   Each check records `ok|regressed|error|skipped` as a step output.
   perf_diff's exit 1 counts as `regressed`; any other failure counts as
   `error`. `ghent-suite-open` now runs 4 interleaved iterations instead of
   2, because it carries firstPageMs, which is a few ms per file.
   `save-incremental` stays at 2.
4. **Render trend** (`id: render_trend`, `continue-on-error: true`). This
   runs `tool/perf/render_trend.dart` on tonight's
   `out/perf-history/flutter-render.ndjson` against perf-data's
   `history/flutter-render.ndjson`. It writes a table to the step summary.
5. **Record tonight's verdict.** This writes one JSON line:
   `{date, sha, prevSha, acceptedSha, verdict, checks{nightly, accepted,
   renderTrend}, runId}`. It runs only when the sweeps succeeded.
6. **Upload tonight's envelopes** (`if: always()`, 90 days), so a failed
   append no longer loses a night.
7. **Append** (`if: !cancelled() && steps.sweeps.outcome == 'success'`). It
   also appends the verdict line to perf-data's
   `history/nightly-verdicts.jsonl` and puts the verdict in the commit
   subject. It does not use a bare `always()`: after a failed or cancelled
   sweep, that would append partial history and make an unmeasured commit
   the next night's baseline.
8. **Fail on a red verdict.** This is the last step, so a red night still
   emails the maintainer after the history is safe. `timeout-minutes` goes
   from 90 to 150. Going by the 09-24 log timings, a weekday is about 66
   min and a Sunday with both baselines about 110 min.

Also changed:

- `tool/perf/baselines/nightly-accepted.sha` = 812f8e5d (#755). The weekly
  check's baseline moves only in a reviewed PR, the same model as
  counters.json and `--update-baseline`. It is the first commit past both
  known steps. #602's cost is accepted in its dev-log. #755's
  OutputIntent/first-page cost is still open, so a fix for it will read
  "improved" and everything after it is judged. Expect the weekly
  interpretMs to read about 1.07-1.12x from #811/#812 (1.07x in a local
  A/B, about 1.12x on the CI nights). Bump the file past them if they are
  accepted.
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
  rule.

## Evidence

- **Workflow emulation (27 checks, all pass).** A small emulator ran the
  real YAML's `run:` scripts with `bash -eo pipefail` in step order. It
  honoured `if:` (with the implicit `success()`), `continue-on-error`,
  step `env:` expressions, `$GITHUB_OUTPUT` and the step summary. The runs
  used a throwaway repo (a bare origin with main + perf-data frozen like
  today, and a fresh clone per night) with stub `nightly.sh`,
  `perf_diff.sh` and `date`. Results:
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
  - A perf_diff error: recorded as `error`, not `regressed`.
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
- **Lint.** actionlint (with shellcheck) is clean on the workflow.
  shellcheck is clean on nightly.sh. PyYAML parses the workflow.

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
`tool/perf/render_trend.dart`, `tool/perf/render_trend_test.dart`,
`tool/perf/baselines/nightly-accepted.sha`, `tool/perf/nightly.sh`,
`tool/perf/report/build_report.mjs`, `tool/perf/SCHEMA.md`,
`packages/pdf_graphics/tool/perf_run_context.dart`,
`packages/dart_pdf_editor/test/benchmark_render_test.dart`.
