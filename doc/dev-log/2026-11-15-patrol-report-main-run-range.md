# 2026-11-15 - Patrol reports judge a PR against where `main` has been

The Patrol performance comments (web, Android, iOS) compare a PR's timings
with the newest `Patrol E2E` artifact from `main`. That artifact was measured
by a different run on a different runner, and runners differ by tens of
percent. Reports on PRs that could not have changed the timing - a pure-Dart
decoder change against `native-mobile-tiles`, which rasterises a synthetic
grid and runs no PDF code - showed swings of +/-30%, and I read one of them
as a real web win before measuring it properly and retracting it.

The existing guard (`within run spread`, overlapping interquartile ranges)
cannot see this. It compares the repeats inside each run, and those are tight:
the noise is *between* runs, not within them.

## What changed

- The three baseline download steps keep going after the first usable
  artifact and collect up to four older ones
  (`$RUNNER_TEMP/patrol-<platform>-baseline-history.txt`, one JSON path per
  line). The newest is still "Main" in every table.
- `tool/patrol_perf_summary.dart --baseline-history <json>` (repeatable).
  `PatrolPerfComparison.history` + `mainRunRange(path)`: the lowest and
  highest value `main` reported for a timing across those artifacts.
- A PR timing inside that range is labelled `within main run-to-run range`
  instead of a percentage against one of the runs. Outside it, the percentage
  against the newest artifact is shown as before. Scenario elapsed p50 and
  the p95 phase rows both use it; counts are untouched.
- The report states `main`'s range per scenario, so a percentage that does
  appear can be read against it.

Fewer than three `main` artifacts carrying a timing means no range, and the
report is exactly what it was. An unreadable history file is skipped with a
note on stderr - history only ever widens what counts as ordinary.

## What it is not

It is not a same-runner A/B. With five runs, a timing drawn from the same
distribution still lands outside their min-max about a third of the time, so
a percentage in the report is "outside what main has recently done", not
"regressed". The honest fix for a number you care about is still
`tool/perf.sh webdiff <ref> <scenario>` (same machine, alternating) - or
building `main` in the same job, which would double the emulator/simulator
minutes of every PR. That trade is the repo owner's; this change costs four
extra artifact downloads per report job and no build time.

The GPU validation job already builds `main` on the same host and passes no
history, so its report is unchanged.

## Checked

`dart tool/patrol_perf_summary_test.dart` (new cases: inside / outside the
range, phase rows, two artifacts are not a range, an artifact without the
timing does not count). The download loop was run locally from the workflow
YAML against a fake `gh` (failed download, artifact without a JSON, seven
runs -> newest + four history), and the tool end to end with the files it
produced. The workflows themselves only run in CI.
