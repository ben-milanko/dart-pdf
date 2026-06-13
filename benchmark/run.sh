#!/usr/bin/env bash
# Run the full dart-pdf vs PDFium render benchmark and print a comparison.
#
#   benchmark/run.sh [CORPUS_DIR] [SCALE] [MAX_PAGES]
#
# Defaults: corpus test_corpora/pdfjs, scale 2, 10 pages/file. Requires
# pypdfium2 (pip install pypdfium2) and fvm Flutter. Writes JSON to
# benchmark/out/ and prints the table to stdout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORPUS="${1:-$ROOT/test_corpora/pdfjs}"
SCALE="${2:-2}"
MAX_PAGES="${3:-10}"
OUT="$ROOT/benchmark/out"
mkdir -p "$OUT"

DART="${DART:-fvm dart}"
FLUTTER="${FLUTTER:-fvm flutter}"

echo "== Corpus: $CORPUS  (scale $SCALE, $MAX_PAGES pages/file) =="

echo "== 1/3  PDFium (pypdfium2) =="
python3 "$ROOT/benchmark/pdfium_benchmark.py" "$CORPUS" \
  --scale "$SCALE" --max-pages "$MAX_PAGES" --out "$OUT/pdfium.json"

echo "== 2/3  dart-pdf interpret (pure Dart, no raster) =="
( cd "$ROOT/packages/pdf_graphics" && \
  $DART run tool/benchmark_interpret.dart "$CORPUS" \
    --max-pages "$MAX_PAGES" --scale "$SCALE" --out "$OUT/dart-interpret.json" )

echo "== 3/3  dart-pdf render (Flutter rasterization) =="
( cd "$ROOT/packages/dart_pdf_editor" && \
  PDF_BENCHMARK_DIR="$CORPUS" PDF_BENCHMARK_SCALE="$SCALE" \
  PDF_BENCHMARK_MAX_PAGES="$MAX_PAGES" \
  PDF_BENCHMARK_OUT="$OUT/dart-render.json" \
    $FLUTTER test test/benchmark_render_test.dart )

echo
echo "== Comparison (baseline = PDFium) =="
python3 "$ROOT/benchmark/compare.py" \
  "$OUT/pdfium.json" "$OUT/dart-render.json" "$OUT/dart-interpret.json"
