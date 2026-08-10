#!/usr/bin/env bash
# Controlled-host PDFium parity acceptance suite.
#
# Absolute wall times are intentionally compared only to the interleaved
# PDFium arm from the same run. Run this on a thermally stable machine with
# hardware compositing; the result envelope records enough GPU/host metadata
# to reject unlike histories.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ITERATIONS="${PERF_PARITY_ITERATIONS:-5}"
BUILD_OUTPUT="${PERF_BUILD_OUTPUT:-${TMPDIR:-/tmp}/dartpdf-pdfium-gate}"

if [ "$#" -gt 0 ]; then
  scenarios=("$@")
else
  scenarios=(
    parity-plan
    parity-scan
    parity-text
    parity-diagram
    parity-long-cad
    parity-progressive-cad
  )
fi

export WASM="${WASM:-1}"
export PERF_WEB_BACKEND="${PERF_WEB_BACKEND:-skwasm}"
export PERF_VISUAL_CAPTURE="${PERF_VISUAL_CAPTURE:-screenshot}"
export PERF_DART_QUERY="${PERF_DART_QUERY:-domSurface=1}"
export PERF_BUILD_OUTPUT="$BUILD_OUTPUT"

echo "Building one competitive harness: $PERF_BUILD_OUTPUT"
"$ROOT/app/tool/perf/build.sh"

export PERF_NO_BUILD=1
for scenario in "${scenarios[@]}"; do
  echo "Running $scenario ($ITERATIONS interleaved samples per engine)"
  "$ROOT/tool/perf.sh" competitive "$scenario" \
    --iterations "$ITERATIONS" --gate
done

echo "All PDFium parity budgets passed."
