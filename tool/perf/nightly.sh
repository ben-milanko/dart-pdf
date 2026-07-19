#!/usr/bin/env bash
# Runs the CI-safe perf scenarios and appends one envelope per run to
# <history-dir>/<suite>.ndjson. Used by .github/workflows/perf-nightly.yml
# and runnable locally: tool/perf/nightly.sh tool/perf/history
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HISTORY="${1:?usage: nightly.sh <history-dir>}"
mkdir -p "$HISTORY"
# Absolutize: perf_sweep runs from packages/pdf_graphics, so a relative
# history path would land inside that package (the 2026-07-18 nightly bug -
# the append-to-perf-data step then found nothing).
HISTORY="$(cd "$HISTORY" && pwd)"

DART=dart
FLUTTER=flutter
if command -v fvm >/dev/null 2>&1; then DART="fvm dart"; FLUTTER="fvm flutter"; fi

sweep() { # sweep <scenario>
  echo "── vm-sweep: $1"
  # No output filtering: a filter pipeline's || true masked real sweep
  # failures once already. Per-file progress in the log is fine.
  (cd "$ROOT/packages/pdf_graphics" &&
    $DART run tool/perf_sweep.dart --scenario "$1" \
      --append-history "$HISTORY/vm-sweep.ndjson" --out /dev/null)
}

# Generate the heavy synthetic docs the image-heavy scenarios render/sweep.
"$(dirname "$0")/gen_perf_docs.sh"

sweep dartpdf-corpus
sweep ghent-suite-open
sweep pdfjs-hostile
sweep save-incremental
sweep cad-138p-sweep
sweep image-heavy

# Render trend (Flutter rasterization: interpret + paint + toImage). Captures
# the paint- and image-decode-path gains the NullDevice vm-sweep can't see.
# Rides `flutter test`'s headless engine; appends one flutter-render line.
render_bench() { # render_bench <scenario> <corpus-rel-to-dart_pdf_editor> <scale> <maxPages>
  echo "── render: $1 ($2)"
  (cd "$ROOT/packages/dart_pdf_editor" &&
    PDF_BENCHMARK_DIR="$2" \
    PDF_BENCHMARK_SCALE="$3" PDF_BENCHMARK_MAX_PAGES="$4" PDF_BENCHMARK_REPEAT=2 \
    PDF_BENCHMARK_SCENARIO="$1" \
    PDF_BENCHMARK_APPEND_HISTORY="$HISTORY/flutter-render.ndjson" \
    $FLUTTER test test/benchmark_render_test.dart)
}
render_bench ghent-render "../../test_corpora/ghent" 2 3
render_bench image-render "../../tool/perf/cache/image-heavy" 1.5 4

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
