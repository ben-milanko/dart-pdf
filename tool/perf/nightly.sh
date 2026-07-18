#!/usr/bin/env bash
# Runs the CI-safe perf scenarios and appends one envelope per run to
# <history-dir>/<suite>.ndjson. Used by .github/workflows/perf-nightly.yml
# and runnable locally: tool/perf/nightly.sh tool/perf/history
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HISTORY="${1:?usage: nightly.sh <history-dir>}"
mkdir -p "$HISTORY"

DART=dart
if command -v fvm >/dev/null 2>&1; then DART="fvm dart"; fi

sweep() { # sweep <scenario>
  echo "── vm-sweep: $1"
  (cd "$ROOT/packages/pdf_graphics" &&
    $DART run tool/perf_sweep.dart --scenario "$1" \
      --append-history "$HISTORY/vm-sweep.ndjson" --out /dev/null 2>&1 |
    grep -v '^  \[' || true)
}

sweep dartpdf-corpus
sweep ghent-suite-open
sweep pdfjs-hostile
sweep save-incremental
sweep cad-138p-sweep

# Competitive column: PDFium over the same Ghent corpus, when pypdfium2 is
# importable (the workflow pip-installs it; locally it is optional).
if python3 -c 'import pypdfium2' 2>/dev/null; then
  echo "── pdfium: test_corpora/ghent"
  python3 "$ROOT/benchmark/pdfium_benchmark.py" "$ROOT/test_corpora/ghent" \
    --max-pages 10 --repeat 3 --timeout 60 \
    --out "$HISTORY/pdfium-latest.json"
  # The python harness writes pretty JSON; history wants one line per run.
  python3 -c "
import json
line = json.dumps(json.load(open('$HISTORY/pdfium-latest.json')))
open('$HISTORY/pdfium.ndjson', 'a').write(line + '\n')
"
  rm "$HISTORY/pdfium-latest.json"
else
  echo "── pdfium column skipped (pypdfium2 not installed)"
fi

echo "nightly sweeps done -> $HISTORY"
