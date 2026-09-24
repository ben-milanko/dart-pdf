#!/usr/bin/env bash
# Runs the iOS simulator Patrol lane: the functional demo journey once, then
# the native performance target PATROL_NATIVE_PERF_REPETITIONS times. Run from
# the example directory (packages/dart_pdf_editor/example).
#
# The performance markers are read from a trace file the tests write inside
# the app's container (see patrol_test/patrol_support.dart), not from the
# streamed device log: Patrol stops streaming when xcodebuild exits, which is
# often before the second test's tail has been forwarded.

set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP must be set by GitHub Actions}"
: "${PDF_PATROL_BUILD_COMMIT:?PDF_PATROL_BUILD_COMMIT must be set}"
: "${PATROL_IOS_DEVICE:?PATROL_IOS_DEVICE must name a booted simulator}"
: "${PATROL_NATIVE_PERF_REPETITIONS:=${PATROL_PERF_REPETITIONS:-3}}"

if ! [[ "$PATROL_NATIVE_PERF_REPETITIONS" =~ ^[1-9][0-9]*$ ]]; then
  echo "PATROL_NATIVE_PERF_REPETITIONS must be a positive integer" >&2
  exit 64
fi

bundle_id=dev.milanko.pdfViewerExample
scenarios=(
  native-mobile-tiles
  gpu-native-pipeline-warm
  gpu-native-page-0-scene-warm
  gpu-native-page-0-first-tile
  gpu-native-page-0-canvas-tile
  gpu-native-page-0-reused-tile
)
require_one=()
for scenario in "${scenarios[@]}"; do
  require_one+=(--require-scenario-runs "$scenario=1")
done

# The functional journey stays strict: any failure fails the job.
patrol test \
  --device "$PATROL_IOS_DEVICE" \
  --target patrol_test/demo_e2e_test.dart \
  --dart-define PDF_PERF_LOG=true \
  --dart-define "PDF_BUILD_COMMIT=$PDF_PATROL_BUILD_COMMIT" \
  --show-flutter-logs \
  --verbose \
  2>&1 | tee "$RUNNER_TEMP/patrol-ios.log"

completed=0
attempt=0
max_attempts=$((PATROL_NATIVE_PERF_REPETITIONS + 2))
while ((completed < PATROL_NATIVE_PERF_REPETITIONS && attempt < max_attempts)); do
  attempt=$((attempt + 1))
  attempt_log="$RUNNER_TEMP/patrol-ios-perf-$attempt.log"
  trace_name="patrol-native-perf-$attempt.log"
  trace="$RUNNER_TEMP/patrol-ios-perf-$attempt.trace"
  echo "::group::Patrol native performance attempt $attempt/$max_attempts"
  # --no-uninstall keeps the app container (and so the trace) after the run.
  # It also spares each attempt an uninstall/reinstall cycle, which is when
  # the simulator has been seen to "forget" the freshly installed test runner.
  set +e
  patrol test \
    --device "$PATROL_IOS_DEVICE" \
    --target patrol_test/native_perf_e2e_test.dart \
    --no-uninstall \
    --dart-define PDF_PERF_LOG=true \
    --dart-define "PDF_BUILD_COMMIT=$PDF_PATROL_BUILD_COMMIT" \
    --dart-define "PDF_PATROL_PERF_TRACE=$trace_name" \
    --show-flutter-logs \
    --verbose \
    2>&1 | tee "$attempt_log"
  patrol_status=${PIPESTATUS[0]}
  set -e
  echo "::endgroup::"

  if ((patrol_status != 0)); then
    # Retry only a simulator app-lifecycle fault (XCTest failing to launch or
    # terminate an app) with no sign of any Dart failure; everything else is a
    # real failure.
    if reason="$(dart ../../../tool/patrol_attempt_triage.dart "$attempt_log")"; then
      echo "::warning::iOS Patrol attempt $attempt hit a $reason; retrying the attempt"
      continue
    fi
    echo "::error::iOS Patrol native performance attempt $attempt failed (patrol exit $patrol_status)"
    exit "$patrol_status"
  fi

  container="$(xcrun simctl get_app_container "$PATROL_IOS_DEVICE" "$bundle_id" data)"
  source_trace="$(find "$container" -type f -name "$trace_name" -print -quit)"
  if [[ -z "$source_trace" ]]; then
    echo "::error::iOS Patrol attempt $attempt passed but left no $trace_name in the app container"
    exit 1
  fi
  cp "$source_trace" "$trace"
  if ! dart ../../../tool/patrol_perf_summary.dart \
    "$trace" \
    --output "$RUNNER_TEMP/patrol-ios-perf-${attempt}-summary" \
    "${require_one[@]}"; then
    echo "::error::iOS Patrol attempt $attempt passed but its trace is missing performance scenarios"
    exit 1
  fi
  cat "$trace" >> "$RUNNER_TEMP/patrol-ios.log"
  completed=$((completed + 1))
done

if ((completed < PATROL_NATIVE_PERF_REPETITIONS)); then
  echo "::error::iOS Patrol produced $completed/$PATROL_NATIVE_PERF_REPETITIONS complete performance repetitions"
  exit 1
fi
