#!/usr/bin/env bash
# Proves the PdfPerf zero-overhead contract's strongest tier: building with
# --dart-define=PDF_PERF=false dead-code-eliminates the whole facade.
#
# Compiles packages/pdf_cos/tool/perf_dce_probe.dart to JS twice and greps
# for PdfPerf.debugDceMarker ('PdfPerf:compiled-in', referenced only from
# guarded perf code):
#   1. -DPDF_PERF=false  -> the marker MUST be absent (facade tree-shaken)
#   2. default build     -> the marker MUST be present (proves the grep
#                           actually detects the facade, i.e. no vacuous pass)
set -euo pipefail

cd "$(dirname "$0")/.."

DART=dart
if command -v fvm >/dev/null 2>&1; then
  DART="fvm dart"
fi

MARKER='PdfPerf:compiled-in'
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

echo "compiling probe with -DPDF_PERF=false..."
(cd packages/pdf_cos &&
  $DART compile js -DPDF_PERF=false -O2 -o "$OUT/off.js" \
    tool/perf_dce_probe.dart >/dev/null)
if grep -q "$MARKER" "$OUT/off.js"; then
  echo "FAIL: '$MARKER' survived a -DPDF_PERF=false build - the facade" >&2
  echo "      is no longer dead-code-eliminable. Check that every entry" >&2
  echo "      point tests kPdfPerfCompiledIn FIRST (const operand before" >&2
  echo "      the mutable bool)." >&2
  exit 1
fi
echo "ok: facade absent from the compiled-out build"

echo "compiling probe with the default (compiled-in) define..."
(cd packages/pdf_cos &&
  $DART compile js -O2 -o "$OUT/on.js" tool/perf_dce_probe.dart >/dev/null)
if ! grep -q "$MARKER" "$OUT/on.js"; then
  echo "FAIL: '$MARKER' missing from the default build - the grep no longer" >&2
  echo "      detects the facade, so the check above proves nothing." >&2
  echo "      Did PdfPerf.debugDceMarker change?" >&2
  exit 1
fi
echo "ok: marker present in the default build (grep is live)"
echo "PASS: PDF_PERF=false fully eliminates the perf facade"
