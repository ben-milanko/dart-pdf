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

1. **Resolve the previous nightly's commit** (`id: prev`,
   `tool/perf/nightly_state.dart resolve`). This runs first, before anything
   touches perf-data: the append step's worktree advances the local
   perf-data ref, so a later read would return HEAD. The baseline comes
   from `history/nightly-verdicts.jsonl`. Only the nightly writes that file,
   whereas perf-backfill appends OLD commits to the envelope history, so the
   envelope tail can't be trusted. Unreadable lines are skipped, so the last
   *readable* record decides. Only when the verdict file does not exist yet
   does it fall back to the vm-sweep tail. The rules (`prevRule` in the
   record):
   - `previous`: the last recorded night's commit. This is the ratchet.
   - `recheck`: the last night is HEAD itself and its nightly check read
     `regressed` or `error`. This covers a re-run, a dispatch on the same
     commit, and a night with no new commits. That night's baseline is
     checked again, instead of HEAD against itself.
   - `unchanged`: the last night is HEAD and read ok. There is nothing new,
     so the check skips.
   - `carry`: the last night's nightly check read `error`, so it judged
     nothing (a perf_diff failure, or a check that ran out of its 80 min).
     Its baseline is carried into tonight's comparison, so its range is
     judged together with tonight's instead of being absorbed. This happens
     once only: a night whose own baseline was already carried, or
     re-checked past the night before it, is not carried again, so a
     baseline that keeps failing cannot freeze the ratchet.

   It also reads perf-data at a `base`. That is the tip, except on a re-run
   (below), where it is perf-data as it stood before this run's first
   attempt appended. And it says whether the weekly accepted check is
   overdue.
2. **Sweeps** (`id: sweeps`), unchanged apart from a step timeout.
3. **Ratio checks**, one step per baseline, both `continue-on-error: true`
   and both running `tool/perf/nightly_ratio_check.sh`:
   - `id: ratio` checks against the previous nightly.
   - `id: accepted` checks against `tool/perf/baselines/nightly-accepted.sha`
     on Sundays (`date -u +%u` = 7), when the `check_accepted` dispatch
     input is set, or when the last accepted check on record is 7 days old
     or there is none. That last condition is a backstop for a Sunday run
     that GitHub dropped or whose sweeps failed. Otherwise it records
     `not-run`. An `error` counts as a check that ran, so a typo in the sha
     file is red every Sunday rather than every night.

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
   `out/perf-history/flutter-render.ndjson` against
   `history/flutter-render.ndjson` at the prev step's `base`. It writes a
   table to the step summary.
5. **Record tonight's verdict.** This writes one JSON line:
   `{date, sha, prevSha, prevRule, acceptedSha, verdict, checks{nightly,
   accepted, renderTrend}, runId, attempt}`. It runs only when the sweeps
   succeeded.
6. **Upload tonight's envelopes** (`if: always()`, 90 days), so a failed
   append no longer loses a night. The artifact name carries
   `github.run_attempt`, because a re-run keeps the run id and
   upload-artifact refuses a duplicate name.
7. **Append** (`if: !cancelled() && steps.sweeps.outcome == 'success'`). It
   also appends the verdict line to perf-data's
   `history/nightly-verdicts.jsonl`. The commit subject carries the verdict
   and the run (`(regressed, run <id>)`), and a `Perf-Nightly-Run: <id>`
   trailer lets a re-run find it. It does not use a bare `always()`: after
   a failed or cancelled sweep, that would append partial history and make
   an unmeasured commit the next night's baseline.
8. **Fail on a red verdict.** This is the last step, so a red night still
   emails the maintainer after the history is safe. Its message says how to
   re-check the night and, when the nightly check errored, what happens to
   that night's range.

**Re-runs.** "Re-run jobs" keeps the run id and the commit, and attempt 1
has already appended its night. Before this was handled, attempt 2 resolved
HEAD as its own baseline, so the nightly check read `skipped`. The render
trend was judged against attempt 1's flagged night (about 1.0x). The run
page then showed green with the regression still there, and the night was
recorded twice. Now:
- The prev step finds this run's appends on perf-data by the trailer. It
  reads everything (verdicts, render history, the accepted-check age) from
  the parent of the first one, so attempt N repeats attempt 1's
  comparisons exactly.
- The append drops the latest attempt's lines (`nightly_state.dart
  drop-run`: the lines that commit added, removed once each from the end,
  so a later backfill's lines stay) and appends this attempt's. The night
  is recorded once, with the latest numbers and verdict.
- If a later night has been recorded since, the re-run leaves perf-data
  alone. Its result stays on the run page and in its artifact, because
  appending an old night after a newer one would make it the next
  baseline.

A **dispatch on the same commit** is a new run, so it is recorded as a
night of its own. The `recheck` rule gives it the red night's baseline. The
render trend leaves out every history night at tonight's commit, so it is
judged against the nights before that commit, not against itself. A
scheduled night with no new commits after a red night gets the same
treatment: it stays red until a commit lands, rather than going green
because it compared HEAD with itself. After a green night it skips, as
before.

**To re-check a red night:** re-run the job, or dispatch the workflow on the
same commit. **An `error` night** judged nothing. The next night carries its
baseline once. If that errors too, the range has been measured by nothing
but the weekly accepted check, so check it by hand with
`tool/perf.sh diff <prevSha>`. A large slowdown is the likeliest cause of an
80-min timeout, which is why the carry exists.

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
  OutputIntent/first-page cost was left open, so a fix for it reads
  "improved" and everything after it is judged. Two such fixes have landed
  since: #956 (glyph outline paths built only where they are read) takes
  back part of #755's interpret cost, and #963 (typed ICC tables, a
  revision-stable colour context and per-pixel memos) cuts the
  OutputIntent profile parse that dominates its first page (30.4 -> 1.8 ms
  for a press profile, per that PR). "Improved" never fails the check.
  #811/#812 push the other way, about 1.07-1.12x interpretMs on small
  overprint pages (1.07x in a local A/B, about 1.12x on the CI nights), so
  the first accepted check's interpretMs is the net of all three. Bump the
  file past #811/#812 if they are accepted.
- `tool/perf/render_trend.dart` + `render_trend_test.dart` (wired into
  ci.yml next to the other tool tests). Per scenario:
  - Each file's baseline is the median of its renderMs over up to 5 prior
    nights.
  - The verdict is the median of the per-file ratios, red at >= 1.4x. In
    ghent-render (54 files) that damps one noisy file: the worst files are
    listed, not counted. image-render, devicen-render and
    jbig2-scanned-render render one file each, so for them that one file's
    ratio is the verdict. Single-file noise reached 1.27x in the replay.
  - Nights at tonight's own commit are left out (see Re-runs above).
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
    1.27x). If a flagged night looks like noise, watch the dashboard for
    the next two nights, or re-run it. render_trend_test.dart pins both
    behaviours.
  - A history line of the wrong shape (valid JSON, but `results` not a
    list, or rows that are not objects) is skipped like a corrupt one.
    Before, it threw, the CLI exited 255, and the check would have read
    `error` every night until someone hand-edited perf-data.
- Envelope `env` gains `flutter` (from `PDF_PERF_FLUTTER_VERSION`, which
  nightly.sh exports from `flutter --version --machine`) and `runnerImage`
  (`$ImageOS/$ImageVersion`, set on hosted runners). These go in
  `perf_run_context.dart`'s envInfo and in benchmark_render_test.dart
  (inlined there because render_backfill grafts that file onto old
  commits). `runnerImage` needs both variables to be non-empty, so an
  empty `ImageVersion` cannot produce a half value like `ubuntu24/`.
  Mid-series the CI Flutter went 3.44.8 -> 3.47.0 -> 3.47.4 and the runner
  image rolled over, with nothing on record to show it.
- `build_report.mjs` reads `nightly-verdicts.jsonl`. It shows a verdict
  table for the last 14 nights and puts the Flutter version and runner image
  in each section's meta line. On every chart it rings each commit's points
  by that commit's latest verdict: red for `regressed`, dashed grey for
  `error` (a check broke and nothing was judged), and nothing once a
  re-check comes back ok. With no verdict file its output is unchanged
  apart from three CSS rules and a blank line where the verdict table
  goes (checked on a perf-data history snapshot). Both loaders skip a line
  that parses to something other than an object (`null`, a number, an
  array). Before, a `null` line threw a TypeError, and because the page is
  rebuilt in the step that commits the history, one bad line would have
  frozen perf-data again every night.

## Evidence

- **Workflow emulation (47 checks, all pass).** A small emulator ran the
  real YAML's `run:` scripts with `bash -eo pipefail` in step order. It
  honoured `if:` (with the implicit `success()`), `continue-on-error`,
  step `env:` expressions, `$GITHUB_OUTPUT`, the step summary, and step
  and job `timeout-minutes` scaled to 0.5 s per minute. A job timeout
  cancels the job. The runs used a throwaway repo (a bare origin with
  main + perf-data frozen like today, and a fresh clone per night) with
  stub `nightly.sh`, `perf_diff.sh` and `date`. Each night has its own
  run id, and a re-run keeps the id with a higher `run_attempt`. Results:
  - Nightly regressed: the job goes red in its last step, the history and
    a `regressed` verdict line are appended, and the artifact is uploaded.
    The next night compares against that night's commit, not the frozen
    one. With no accepted check on record, the first night runs it too.
  - Clean night: green, and the verdict is appended.
  - Unchanged HEAD after a green night: the check is skipped and the night
    is still recorded.
  - Accepted baseline regressed (dispatch input): red, with
    `checks.accepted = regressed`. Sunday runs the accepted check; Monday
    does not.
  - Re-run of a red night (nightly and render both red): attempt 2 is red
    again. It makes the same 2 perf_diff calls against attempt 1's
    baseline, and perf-data ends with one verdict line and one
    flutter-render night for the commit (attempt 2's, `attempt 2` in the
    subject). The round-1 version of this workflow, given the same run,
    reads green against itself with 0 perf_diff calls and records the
    night twice. That was the review finding.
  - A new dispatch on the same commit re-checks the red night (`recheck`)
    and is red. A re-run of it where the red was noise comes back green
    and replaces that night with `ok`. The next commit then compares
    against it.
  - A re-run after a later night has been recorded makes attempt 1's
    comparison, and perf-data is left untouched.
  - An errored nightly check: the next night compares against the errored
    night's baseline (`carry`), and the night after that advances.
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
  - Each night is judged as the workflow would have judged it, after the
    nights before it and leaving out nights at its own commit. 36 of the
    217 (scenario, commit) pairs were measured on more than one night.
  - With the level reset, it flags exactly 08-25: ghent-render 9.52x and
    jbig2-scanned-render 1.845x. There are no other flags. The highest
    unflagged ratio is 1.271x (jbig2, on 09-21, the second night of an
    unchanged commit, judged against the commits before it). Judged
    against its own earlier night, as the round-1 rule did, the highest
    was 1.223x.
  - The plain rule, "median of the prior 5" with no reset, flags
    08-25, 08-26 and 08-27 for both suites: three red nights per step. Its
    highest unflagged ratio is 1.29x, on the night the window straddles
    the step.
  - First night after this lands, with history frozen at 07-25 and 09-23's
    envelopes: ghent-render 7.65x is red. jbig2 is skipped because it has
    no history before 07-26. The next night reads 0.92x.
- **`tool/perf/nightly_test.dart` (60 checks, in ci.yml).** It runs
  nightly_ratio_check.sh against a stub perf_diff in a throwaway git repo
  and holds the workflow to its timeout budget and wiring. It reads the
  committed `nightly-accepted.sha` the way the script does and requires
  exactly one full sha, so a bad bump fails the PR that makes it instead
  of the next Sunday (ancestry of HEAD is checked too when the commit is
  in the clone; ci.yml's checkout is shallow). It checks
  nightly_state.dart's rules: the ratchet, a re-check, one carry and no
  second, corrupt trailing verdict lines, the weekly backstop, and
  line-dropping. It also runs `resolve`/`drop-run` against a throwaway
  perf-data branch through a first attempt, its re-run, a same-commit
  dispatch, a third attempt, a backfill that does not supersede a re-run,
  and a later night that does. And it feeds
  build_report.mjs `null`/array/number lines and a regressed/error/re-checked
  set of verdicts. Reverting any one of the fixes fails it:
  - mapping every exit 1 to `regressed` fails 1 check;
  - the old concatenate-and-skip reading of the sha file fails 4;
  - dropping the ratio steps' timeouts fails 1, and so does a 200-min job
    limit;
  - the old loaders fail 3 (every dashboard check);
  - the old artifact name fails 1;
  - the round-1 dashboard rings fail 1.
- **`tool/perf/render_trend_test.dart` (29 checks).** The round-1
  `results` cast crashes the test, and without the same-commit exclusion
  the re-check case fails.
- **`packages/pdf_graphics/test/perf_run_context_test.dart`** pins
  `toolchainEnv`, including the empty-`ImageVersion` case.
- **Lint.** actionlint (with shellcheck) is clean on the workflow.
  shellcheck is clean on nightly.sh and nightly_ratio_check.sh. PyYAML
  parses the workflow.

## Expect after merge

- The first run (dispatch or schedule) is red against 1cf882ca, as every
  night has been, but this time the history and verdict are appended. The
  next night compares against that commit.
- The render trend is probably red once on that first night too.
  perf-data's render history ends at 07-25, before #755's 9.5x
  ghent-render step. 09-23's envelopes replay at 7.65x against it; #963
  takes some of that back, but not likely all of it.
- There is no accepted check on record yet, so the first run also runs the
  accepted check (against #755). That is the first real reading of
  everything after #755. After that it runs on Sundays.

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
- "Re-run jobs" keeps `github.run_id` and `GITHUB_SHA` and bumps
  `github.run_attempt`, so the run id is what ties attempts together. That
  is why the perf-data commit carries a `Perf-Nightly-Run:` trailer, and
  why the verdict record keeps `runId` and `attempt`.

## Files

`.github/workflows/perf-nightly.yml`, `.github/workflows/ci.yml`,
`tool/perf/nightly_ratio_check.sh`, `tool/perf/nightly_state.dart`,
`tool/perf/nightly_test.dart`,
`tool/perf/render_trend.dart`, `tool/perf/render_trend_test.dart`,
`tool/perf/baselines/nightly-accepted.sha`, `tool/perf/nightly.sh`,
`tool/perf/report/build_report.mjs`, `tool/perf/SCHEMA.md`,
`packages/pdf_graphics/tool/perf_run_context.dart`,
`packages/pdf_graphics/test/perf_run_context_test.dart`,
`packages/dart_pdf_editor/test/benchmark_render_test.dart`.
