#!/usr/bin/env bash

set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP must be set by GitHub Actions}"
: "${PDF_PATROL_BUILD_COMMIT:?PDF_PATROL_BUILD_COMMIT must be set}"
: "${PATROL_NATIVE_PERF_REPETITIONS:=${PATROL_PERF_REPETITIONS:-3}}"

if ! [[ "$PATROL_NATIVE_PERF_REPETITIONS" =~ ^[1-9][0-9]*$ ]]; then
  echo "PATROL_NATIVE_PERF_REPETITIONS must be a positive integer" >&2
  exit 64
fi

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
