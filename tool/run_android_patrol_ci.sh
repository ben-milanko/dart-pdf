#!/usr/bin/env bash

set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP must be set by GitHub Actions}"
: "${PDF_PATROL_BUILD_COMMIT:?PDF_PATROL_BUILD_COMMIT must be set}"

patrol test \
  --device emulator-5554 \
  --target patrol_test/demo_e2e_test.dart \
  --dart-define PDF_PERF_LOG=true \
  --dart-define "PDF_BUILD_COMMIT=$PDF_PATROL_BUILD_COMMIT" \
  --show-flutter-logs \
  --verbose \
  2>&1 | tee "$RUNNER_TEMP/patrol-android.log"

patrol test \
  --device emulator-5554 \
  --target patrol_test/native_perf_e2e_test.dart \
  --dart-define PDF_PERF_LOG=true \
  --dart-define "PDF_BUILD_COMMIT=$PDF_PATROL_BUILD_COMMIT" \
  --show-flutter-logs \
  --verbose \
  2>&1 | tee -a "$RUNNER_TEMP/patrol-android.log"
