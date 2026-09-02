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

for ((iteration = 1; iteration <= PATROL_NATIVE_PERF_REPETITIONS; iteration++)); do
  echo "::group::Patrol native performance repetition $iteration/$PATROL_NATIVE_PERF_REPETITIONS"
  patrol test \
    --device emulator-5554 \
    --target patrol_test/native_perf_e2e_test.dart \
    --dart-define PDF_PERF_LOG=true \
    --dart-define "PDF_BUILD_COMMIT=$PDF_PATROL_BUILD_COMMIT" \
    --show-flutter-logs \
    --verbose \
    2>&1 | tee -a "$RUNNER_TEMP/patrol-android.log"
  echo "::endgroup::"
done
