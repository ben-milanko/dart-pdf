#!/usr/bin/env bash
# Single front door for the dart-pdf performance suite.
#
#   tool/perf.sh sweep <scenario|corpus-path> [extra perf_sweep flags]
#   tool/perf.sh interpret <corpus> [flags]     # legacy interpret benchmark
#   tool/perf.sh render <corpus>                # Flutter raster benchmark
#   tool/perf.sh web [scenario]                 # one real-Chrome scenario run
#   tool/perf.sh web build                      # (re)build the web harness bundle
#   tool/perf.sh web loop [N]                   # legacy scroll loop, N iters
#   tool/perf.sh webdiff <ref> [scenario] ...   # one-command web A/B vs a git ref
#   tool/perf.sh competitive [scenario] ...     # DartPDF vs Chromium/PDFium journey
#   tool/perf.sh pdfium-gate [scenario ...]      # all controlled-host parity budgets
#   tool/perf.sh screenshot-probe               # calibrate screenshot sample clock
#   tool/perf.sh surface-check [scenario] ...   # worker canvas pixel gate
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
    PERF_DIR="$ROOT/app/tool/perf"
    [ -d "$PERF_DIR/node_modules" ] || (cd "$PERF_DIR" && npm install)
    sub="${1:-default}"
    shift || true
    case "$sub" in
      build)
        "$PERF_DIR/build.sh" "$@" ;;
      loop)
        (cd "$PERF_DIR" && ./loop.sh "${1:-6}") ;;
      *)
        # One real-Chrome run of a named scenario (default = scenarios.json's
        # `default`). Auto-build the bundle if it's missing. Each scenario keeps
        # its own history file so single-run trends never mix workloads.
        [ -f "$ROOT/app/build/web/index.html" ] || "$PERF_DIR/build.sh"
        results="$PERF_DIR/results-$sub.ndjson"
        (cd "$PERF_DIR" && PERF_RESULTS="$results" node driver.mjs --scenario "$sub" "$@")
        echo "▸ history: $results   (trend: PERF_RESULTS=$results node $PERF_DIR/report.mjs)" ;;
    esac
    ;;
  webdiff)
    PERF_DIR="$ROOT/app/tool/perf"
    [ -d "$PERF_DIR/node_modules" ] || (cd "$PERF_DIR" && npm install)
    REF="${1:?usage: perf.sh webdiff <ref> [scenario] [--iterations N] [--threshold R] [--keep]}"
    shift
    args=(--baseline "$REF")
    if [ $# -gt 0 ] && [[ "$1" != --* ]]; then args+=(--scenario "$1"); shift; fi
    (cd "$PERF_DIR" && node bench.mjs "${args[@]}" "$@")
    ;;
  competitive|parity)
    PERF_DIR="$ROOT/app/tool/perf"
    [ -d "$PERF_DIR/node_modules" ] || (cd "$PERF_DIR" && npm install)
    SCENARIO="${1:-parity-plan}"
    shift || true
    # build.sh resolves a relative output from the caller's directory, while
    # the Node runner executes from PERF_DIR. Pin it to one absolute path
    # before either side reads it so a custom build can never serve stale
    # bytes from a same-named directory under app/tool/perf.
    if [ -n "${PERF_BUILD_OUTPUT:-}" ] && [[ "$PERF_BUILD_OUTPUT" != /* ]]; then
      export PERF_BUILD_OUTPUT="$PWD/$PERF_BUILD_OUTPUT"
    fi
    # The common-journey surface lives in the compiled harness. Rebuild by
    # default so a stale bundle can never be compared with the current source;
    # PERF_NO_BUILD=1 is the explicit fast-loop escape hatch.
    [ "${PERF_NO_BUILD:-0}" = "1" ] || "$PERF_DIR/build.sh"
    (cd "$PERF_DIR" && node competitive.mjs --scenario "$SCENARIO" "$@")
    ;;
  pdfium-gate)
    bash "$ROOT/tool/perf/pdfium_gate.sh" "$@"
    ;;
  screenshot-probe)
    PERF_DIR="$ROOT/app/tool/perf"
    [ -d "$PERF_DIR/node_modules" ] || (cd "$PERF_DIR" && npm install)
    (cd "$PERF_DIR" && node screenshot_timing_probe.mjs "$@")
    ;;
  surface-check)
    PERF_DIR="$ROOT/app/tool/perf"
    [ -d "$PERF_DIR/node_modules" ] || (cd "$PERF_DIR" && npm install)
    SCENARIO="${1:-parity-plan}"
    shift || true
    if [ -n "${PERF_BUILD_OUTPUT:-}" ] && [[ "$PERF_BUILD_OUTPUT" != /* ]]; then
      export PERF_BUILD_OUTPUT="$PWD/$PERF_BUILD_OUTPUT"
    fi
    # The worker-owned presentation target is SkWasm; build that backend unless
    # the caller explicitly selected another one or supplied a prebuilt bundle.
    export WASM="${WASM:-1}"
    [ "${PERF_NO_BUILD:-0}" = "1" ] || "$PERF_DIR/build.sh"
    (cd "$PERF_DIR" && node surface_compare.mjs \
      --scenario "$SCENARIO" --gate "$@")
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
