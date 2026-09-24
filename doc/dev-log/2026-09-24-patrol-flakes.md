# Patrol E2E: the native lanes' random failures

The "Patrol E2E" iOS Simulator and Android (API 35) jobs failed at random, on
main and on PRs, usually with every Dart test reported green. From
2026-09-17 to 2026-09-24, 5 of 56 completed iOS job attempts and 2 of 67
Android attempts failed; many passing iOS jobs only got there by discarding
attempts. Reading the failed job logs turned up four different causes. Only
one of them was a Dart test failing.

## 1. iOS: perf markers cut off the log (the most common)

The native-perf loop accepted an attempt only if
`tool/patrol_perf_summary.dart` found all six `scenario name=…` markers in the
tee'd `patrol test` output. Those lines come from the `flutter:` device log,
which patrol_cli streams with `xcrun simctl spawn <udid> log stream`. The stream
runs 5-10 s behind the app, and the CLI stops reading it as soon as xcodebuild
exits. The second test's tail (the `gpu-native-*` markers) was often still in
flight: xcodebuild says `Executed 2 tests, with 0 failures`, but the CLI
summary says `Total: 1, Successful: 1` because it counts from the same
lagging stream. Runs 35847078181 (main, 5/6) and 35677641336 (4/6) ran out of
attempts this way.

Fix: `patrol_test/patrol_support.dart` `mirrorPerfTraceToFile()` sets
`PdfPerfLog.sink` to append each `[perf …]` line to
`Directory.systemTemp/<PDF_PATROL_PERF_TRACE>`, which is inside the app's data
container. It uses one `RandomAccessFile` opened for append, so each line is one
unbuffered `write(2)`: the line survives the app being killed and costs no
fsync. `tool/run_ios_patrol_ci.sh` passes a trace name for each attempt, runs
`patrol test --no-uninstall` so the container is still there afterwards, finds
the file under `xcrun simctl get_app_container <udid> <bundle> data`, and gives
that file to the summarizer. Once patrol has passed, an incomplete trace is a
hard error; there is no silent retry.

Android reads the same lines out of the emulator's logcat buffer instead
(`adb logcat -c` before each repetition, then `adb logcat -d -v raw -s flutter`,
with the buffer raised to 16M). An app file won't work there because the
example runs under the test orchestrator with `clearPackageData=true`, which
wipes app storage between tests.

Only the perf lines go into the aggregate `patrol-{ios,android}.log`. The
demo journey's streamed log still comes first, so the downstream report and the
main-branch baseline comparison work as before.

## 2. iOS: simulator app-lifecycle faults

- Run 35989015086 (PR #948): `Failed to terminate
  dev.milanko.pdfViewerExample:37785` after 60 s. XCUIApplication.launch has to
  kill the instance left over from test listing, and it failed before
  `runDartTest` was ever sent. The Dart side never ran that test; the tearDown
  maps that read "success" belong to the *unrequested* passes Patrol makes
  through every test in each launch, so they say nothing about it.
- Run 35980935128 (PR #947), "Successful: 0": `Application
  "…RunnerUITests.xctrunner" is unknown to FrontBoard`. This happened right
  after the CLI uninstalled and reinstalled the runner.

Neither fault involves the code under test, and patrol 4.10 / patrol_cli 4.8
have no fix for them. `--no-uninstall` (from fix 1) also stops the
uninstall-then-reinstall between attempts that led to the FrontBoard case.
What's left is handled by `tool/patrol_attempt_triage.dart`, which reads only
the failed attempt's log. It allows a retry (counted against the existing
reps+2 attempt budget, and logged as a `::warning::`) only if every
`error: -[RunnerUITests …]` line is one of the known lifecycle signatures and
nothing in the Dart log shows a failure (`passed: false`, a framework
exception, `Some tests failed`, `test result: FAILED/CRASHED`). A real Dart
failure shows up as `((passed) is true) failed - …` on the xcodebuild side,
which the Dart log can't lose, so it always stays a hard failure. The tests
are in `tool/patrol_attempt_triage_test.dart`, run from ci.yml. The demo
journey gets no retry.

## 3. Android: "A SemanticsHandle was active at the end of the test"

Run 35862969912 / job 107187462037 (PR #941). The tile test's body passed, and
then `_verifySemanticsHandlesWereDisposed` failed it (the tearDown line reads
`passed: false`). `testWidgets` records the handle count synchronously, then
reaches the body after a few async turns. Patrol's workaround for
leancodepl/patrol#1474 (and flutter#142713) replaces
`onSemanticsEnabledChanged` with a no-op as the body's first statement. If the
OS turns accessibility on inside that gap (UiAutomator connecting in a fresh
orchestrator process), the framework's default handler takes a handle and the
count goes up by one. `guardPlatformSemanticsToggles()` installs the same
no-op in `setUpAll`, before the first test records the count, in both native
targets. Tests still get a semantics tree through `patrolTest`'s own handle.

## 4. Android demo: form text field (a real Dart failure)

Run 35995024823 (main at 91920434) failed `fills text, checkbox, radio, and
choice form fields`: after `enterText` + `TextInputAction.done`, the `name`
field's value never became "Grace Hopper" within 6 s. That is a Dart
assertion in the functional journey, so it is left strict. The form commit
path has changed a lot in the last few days (#943/#944/#946/#947), so treat
another occurrence as a possible regression, not flake.

## Versions

patrol_cli moves from 4.7.0 to 4.8.0 (in patrol-e2e.yml and
preview-demo-web.yml). That is the release paired with the example's patrol
4.10.0; both came out on 2026-09-15, and 4.10's native screenshots and
build-time discovery need it. The skew was not the cause of any failure above:
4.7.0's compatibility range is patrol 4.9.0+. Build-time test discovery would
remove the listing launch behind the "Failed to terminate" case, but it is
still experimental and not adopted here.

## Gotchas

- `gh run view --job <id> --log` can return the log of a *different attempt*
  of a re-run job. Use `gh api --allow-escape-sequences
  repos/<o>/<r>/actions/jobs/<id>/logs` for the exact attempt.
- `PatrolBinding: tearDown(): count: N, results: {...}` lists every test the
  launch walked through, including unrequested ones. Look at
  `tearDown(): test "…" …, passed: <bool>` for the requested one.
