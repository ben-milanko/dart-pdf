#!/usr/bin/env bash

set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP must be set by GitHub Actions}"
: "${PDF_PATROL_BUILD_COMMIT:?PDF_PATROL_BUILD_COMMIT must be set}"
: "${PATROL_NATIVE_PERF_REPETITIONS:=${PATROL_PERF_REPETITIONS:-3}}"

if ! [[ "$PATROL_NATIVE_PERF_REPETITIONS" =~ ^[1-9][0-9]*$ ]]; then
  echo "PATROL_NATIVE_PERF_REPETITIONS must be a positive integer" >&2
  exit 64
fi

# The GitHub emulator otherwise selects Impeller OpenGLES. flutter_gpu's
# current GLES shader-pipeline path can terminate the instrumentation process
# before Dart can report a fallback, so the GPU-specific Patrol cohort uses
# the emulator's Vulkan/SwiftShader backend. The checked-in example manifest
# remains device-default for ordinary users and local development.
cp ../../../tool/android_patrol_vulkan_manifest.xml \
  android/app/src/debug/AndroidManifest.xml

# A wedged emulator must fail this step fast instead of hanging it until the
# job timeout. When the emulator went offline during instrumentation teardown,
# Patrol exited but the step then sat silent for 35 minutes until the job was
# cancelled - most likely `patrol ... | tee` waiting on a log-streaming child
# (adb logcat) that still held the pipe, which is how a `| tee` pipeline
# behaves when an orphan keeps its write end open. So Patrol writes to a file under
# `timeout`, `tail --pid` streams that file and stops when Patrol itself exits
# (orphaned children can't hold it open), and every adb call is bounded.
emulator=emulator-5554
adb_bounded() {
  timeout --kill-after=10s 60s adb -s "$emulator" "$@"
}
patrol_logged() {
  local log=$1 limit=$2
  shift 2
  : > "$log"
  timeout --kill-after=30s "$limit" patrol test --device "$emulator" "$@" \
    > "$log" 2>&1 &
  local pid=$!
  tail -n +1 -f --pid="$pid" "$log"
  local status=0
  wait "$pid" || status=$?
  if ((status == 124 || status == 137)); then
    echo "::error::patrol test exceeded $limit (emulator likely wedged)"
  fi
  return "$status"
}

# The first run also builds the APKs, so it gets the longer limit.
patrol_logged "$RUNNER_TEMP/patrol-android.log" 25m \
  --target patrol_test/demo_e2e_test.dart \
  --dart-define PDF_PERF_LOG=true \
  --dart-define "PDF_BUILD_COMMIT=$PDF_PATROL_BUILD_COMMIT" \
  --show-flutter-logs \
  --verbose

scenarios=(
  native-mobile-tiles
  gpu-native-pipeline-warm
  gpu-native-page-0-scene-warm
  gpu-native-page-0-first-tile
  gpu-native-page-0-canvas-tile
  gpu-native-page-0-reused-tile
  gpu-native-page-0-first-tile-readback
  gpu-native-page-0-canvas-tile-readback
  gpu-native-page-0-reused-tile-readback
)
require_one=()
for scenario in "${scenarios[@]}"; do
  require_one+=(--require-scenario-runs "$scenario=1")
done

# The performance markers are read back from the device's log buffer after
# each run, not from Patrol's live log stream: that stream stops when the
# instrumentation exits and can drop the last test's tail. (The iOS lane uses
# a trace file in the app container instead; here the test orchestrator's
# clearPackageData would wipe app files between tests.) A generous buffer
# holds a whole repetition.
adb_bounded logcat -G 16M ||
  echo "::warning::Could not enlarge the emulator log buffer"

for ((iteration = 1; iteration <= PATROL_NATIVE_PERF_REPETITIONS; iteration++)); do
  attempt_log="$RUNNER_TEMP/patrol-android-perf-$iteration.log"
  trace="$RUNNER_TEMP/patrol-android-perf-$iteration.trace"
  echo "::group::Patrol native performance repetition $iteration/$PATROL_NATIVE_PERF_REPETITIONS"
  adb_bounded logcat -c
  patrol_logged "$attempt_log" 15m \
    --target patrol_test/native_perf_e2e_test.dart \
    --dart-define PDF_PERF_LOG=true \
    --dart-define "PDF_BUILD_COMMIT=$PDF_PATROL_BUILD_COMMIT" \
    --show-flutter-logs \
    --verbose
  echo "::endgroup::"
  adb_bounded logcat -d -v raw -s flutter > "$trace"
  if ! dart ../../../tool/patrol_perf_summary.dart \
    "$trace" \
    --output "$RUNNER_TEMP/patrol-android-perf-${iteration}-summary" \
    "${require_one[@]}"; then
    echo "::error::Android Patrol repetition $iteration passed but its trace is missing performance scenarios"
    exit 1
  fi
  cat "$trace" >> "$RUNNER_TEMP/patrol-android.log"
done
