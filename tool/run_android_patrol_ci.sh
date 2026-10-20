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

patrol test \
  --device emulator-5554 \
  --target patrol_test/demo_e2e_test.dart \
  --dart-define PDF_PERF_LOG=true \
  --dart-define "PDF_BUILD_COMMIT=$PDF_PATROL_BUILD_COMMIT" \
  --show-flutter-logs \
  --verbose \
  2>&1 | tee "$RUNNER_TEMP/patrol-android.log"

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

# The performance markers are read back from the device's log buffer after
# each run, not from Patrol's live log stream: that stream stops when the
# instrumentation exits and can drop the last test's tail. (The iOS lane uses
# a trace file in the app container instead; here the test orchestrator's
# clearPackageData would wipe app files between tests.) A generous buffer
# holds a whole repetition.
adb -s emulator-5554 logcat -G 16M ||
  echo "::warning::Could not enlarge the emulator log buffer"

for ((iteration = 1; iteration <= PATROL_NATIVE_PERF_REPETITIONS; iteration++)); do
  attempt_log="$RUNNER_TEMP/patrol-android-perf-$iteration.log"
  trace="$RUNNER_TEMP/patrol-android-perf-$iteration.trace"
  echo "::group::Patrol native performance repetition $iteration/$PATROL_NATIVE_PERF_REPETITIONS"
  adb -s emulator-5554 logcat -c
  patrol test \
    --device emulator-5554 \
    --target patrol_test/native_perf_e2e_test.dart \
    --dart-define PDF_PERF_LOG=true \
    --dart-define "PDF_BUILD_COMMIT=$PDF_PATROL_BUILD_COMMIT" \
    --show-flutter-logs \
    --verbose \
    2>&1 | tee "$attempt_log"
  echo "::endgroup::"
  adb -s emulator-5554 logcat -d -v raw -s flutter > "$trace"
  if ! dart ../../../tool/patrol_perf_summary.dart \
    "$trace" \
    --output "$RUNNER_TEMP/patrol-android-perf-${iteration}-summary" \
    "${require_one[@]}"; then
    echo "::error::Android Patrol repetition $iteration passed but its trace is missing performance scenarios"
    exit 1
  fi
  cat "$trace" >> "$RUNNER_TEMP/patrol-android.log"
done
