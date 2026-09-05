#!/usr/bin/env bash
# Compiles the render worker + the perf-harness web bundle into app/build/web,
# ready for tool/perf/driver.mjs to serve and drive. Run once per code change;
# the driver can then loop against the built bundle without rebuilding.
#
#   tool/perf/build.sh            # release build (default)
#   PROFILE=1 tool/perf/build.sh  # profile build (Dart asserts off, source maps)
#   WASM=1 tool/perf/build.sh     # SkWasm build (same output, JS fallback)
set -euo pipefail

INVOCATION_DIR="$PWD"
PERF_PROJECT="$(cd "$(dirname "$0")/../perf_harness" && pwd)"
APP_ROOT="$(cd "$PERF_PROJECT/../.." && pwd)"

DART="${DART:-fvm dart}"
FLUTTER="${FLUTTER:-fvm flutter}"
MODE="--release"
[ "${PROFILE:-0}" = "1" ] && MODE="--profile"
WEB_BACKEND="JS/CanvasKit"
WASM_ARGS=()
if [ "${WASM:-0}" = "1" ]; then
  WEB_BACKEND="SkWasm"
  WASM_ARGS=(--wasm)
fi
BUILD_OUTPUT="${PERF_BUILD_OUTPUT:-$APP_ROOT/build/web}"
if [[ "$BUILD_OUTPUT" != /* ]]; then
  BUILD_OUTPUT="$INVOCATION_DIR/$BUILD_OUTPUT"
fi

cd "$PERF_PROJECT"

echo "==> Building the render worker (web)"
$DART run dart_pdf_editor:build_web_worker

echo "==> flutter build web $MODE ($WEB_BACKEND harness, PDF_PERF_LOG=true)"
# --no-web-resources-cdn bundles CanvasKit into build/web/canvaskit instead of
# loading it from gstatic.com. The driver serves the bundle offline behind
# COOP/COEP (cross-origin isolation, which the CDN fetch fails under
# credentialless COEP anyway), so a headless/CI run has no network for the CDN.
$FLUTTER build web $MODE \
  --target lib/main.dart \
  --output "$BUILD_OUTPUT" \
  --dart-define=PDF_PERF_LOG=true \
  --no-web-resources-cdn \
  ${WASM_ARGS[@]+"${WASM_ARGS[@]}"} \
  "$@"

echo "==> Done. Harness bundle in $BUILD_OUTPUT; worker beside index.html."
