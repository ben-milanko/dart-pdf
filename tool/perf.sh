#!/usr/bin/env bash
# Single front door for the dart-pdf performance suite.
#
#   tool/perf.sh sweep <scenario|corpus-path> [extra perf_sweep flags]
#   tool/perf.sh interpret <corpus> [flags]     # legacy interpret benchmark
#   tool/perf.sh render <corpus>                # Flutter raster benchmark
#   tool/perf.sh web                            # Chrome scroll loop (app/tool/perf)
#   tool/perf.sh compare-pdfium [corpus]        # dart-pdf vs PDFium tables
#   tool/perf.sh gate [--update-baseline]       # deterministic PR counter gate
#   tool/perf.sh dce                            # PDF_PERF=false tree-shake proof
#   tool/perf.sh diff <ref> [scenario]          # A/B this tree vs a git ref
#   tool/perf.sh report [--html]                # summarize local history
#
# Local results append to tool/perf/history/local.ndjson (gitignored).
# Schema: tool/perf/SCHEMA.md. Scenarios: tool/perf/scenarios.json.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HISTORY_DIR="$ROOT/tool/perf/history"
mkdir -p "$HISTORY_DIR"

DART=dart
FLUTTER=flutter
if command -v fvm >/dev/null 2>&1; then
  DART="fvm dart"
  FLUTTER="fvm flutter"
fi

cmd="${1:-help}"
shift || true

case "$cmd" in
  sweep)
    target="${1:?usage: perf.sh sweep <scenario|corpus-path> [flags]}"
    shift
    if [ -e "$ROOT/tool/perf/scenarios.json" ] &&
       grep -q "\"$target\"" "$ROOT/tool/perf/scenarios.json"; then
      sel=(--scenario "$target")
    else
      sel=("$target")
    fi
    (cd "$ROOT/packages/pdf_graphics" &&
      $DART run tool/perf_sweep.dart "${sel[@]}" \
        --append-history "$HISTORY_DIR/local.ndjson" "$@")
    ;;
  interpret)
    corpus="${1:?usage: perf.sh interpret <corpus> [flags]}"
    shift
    (cd "$ROOT/packages/pdf_graphics" &&
      $DART run tool/benchmark_interpret.dart "$corpus" "$@")
    ;;
  render)
    corpus="${1:?usage: perf.sh render <corpus>}"
    shift
    (cd "$ROOT/packages/dart_pdf_editor" &&
      PDF_BENCHMARK_DIR="$corpus" $FLUTTER test test/benchmark_render_test.dart "$@")
    ;;
  web)
    (cd "$ROOT/app/tool/perf" && ./loop.sh "${1:-1}")
    ;;
  compare-pdfium)
    (cd "$ROOT/benchmark" && ./run.sh "$@")
    ;;
  gate)
    (cd "$ROOT/packages/pdf_graphics" &&
      $DART run tool/perf_count_gate.dart "$@")
    ;;
  dce)
    "$ROOT/tool/check_perf_dce.sh"
    ;;
  diff)
    "$ROOT/tool/perf/perf_diff.sh" "$@"
    ;;
  report)
    node "$ROOT/tool/perf/report/build_report.mjs" \
      --history "$HISTORY_DIR" "$@"
    ;;
  help|*)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
