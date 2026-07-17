#!/usr/bin/env bash
# Compiles the render worker + the perf-harness web bundle into app/build/web,
# ready for tool/perf/driver.mjs to serve and drive. Run once per code change;
# the driver can then loop against the built bundle without rebuilding.
#
#   tool/perf/build.sh            # release build (default)
#   PROFILE=1 tool/perf/build.sh  # profile build (Dart asserts off, source maps)
set -euo pipefail

cd "$(dirname "$0")/../.."   # -> app/

DART="${DART:-fvm dart}"
FLUTTER="${FLUTTER:-fvm flutter}"
MODE="--release"
[ "${PROFILE:-0}" = "1" ] && MODE="--profile"

echo "==> Building the render worker (web)"
$DART run dart_pdf_editor:build_web_worker

echo "==> flutter build web $MODE (harness entrypoint, PDF_PERF_LOG=true)"
# --no-web-resources-cdn bundles CanvasKit into build/web/canvaskit instead of
# loading it from gstatic.com. The driver serves the bundle offline behind
# COOP/COEP (cross-origin isolation, which the CDN fetch fails under
# credentialless COEP anyway), so a headless/CI run has no network for the CDN.
$FLUTTER build web $MODE \
  --target tool/perf/perf_harness.dart \
  --dart-define=PDF_PERF_LOG=true \
  --no-web-resources-cdn \
  "$@"

echo "==> Done. Harness bundle in app/build/web; worker beside index.html."
