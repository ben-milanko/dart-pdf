#!/usr/bin/env bash
# A/B perf diff: this working tree vs a git ref, interleaved ABAB so thermal
# and background drift cancel instead of biasing one side.
#
#   tool/perf.sh diff <ref> [scenario] [--iterations N] [--threshold R] [--clean]
#
# VM suites only (vm-sweep scenarios). The ref's tree is checked out into a
# cached worktree (one `pub get` per sha, reused across invocations); pass
# --clean to remove it afterwards. Chrome-loop A/Bs stay manual (build.sh +
# loop.sh twice) - two full web builds per diff aren't worth automating yet.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REF="${1:?usage: perf_diff.sh <ref> [scenario] [--iterations N] [--threshold R] [--clean]}"
shift
SCENARIO="ghent-suite-open"
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
  SCENARIO="$1"
  shift
fi
ITERATIONS=4
THRESHOLD=1.10
CLEAN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --iterations) ITERATIONS="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --clean) CLEAN=1; shift ;;
    *) echo "unknown flag $1" >&2; exit 2 ;;
  esac
done

DART=dart
if command -v fvm >/dev/null 2>&1; then DART="fvm dart"; fi

SHA=$(git -C "$ROOT" rev-parse --short "$REF")
WORKTREE="${TMPDIR:-/tmp}/dart-pdf-perf-ab/$SHA"
if [ ! -d "$WORKTREE" ]; then
  echo "creating worktree for $REF ($SHA) at $WORKTREE..."
  mkdir -p "$(dirname "$WORKTREE")"
  git -C "$ROOT" worktree add --detach "$WORKTREE" "$REF"
  (cd "$WORKTREE" && $DART pub get >/dev/null)
else
  echo "reusing cached worktree $WORKTREE"
fi

# The measuring apparatus itself - harness scripts and the workload list, none
# of it library code. Both sides must run the SAME harness or the comparison is
# apples to oranges, and a measure or scenario added after the ref exists only
# here, so these are always overwritten (backfill.sh grafts them the same way).
HARNESS=(
  packages/pdf_cos/tool/gen_cad_pdf.dart
  packages/pdf_graphics/tool/perf_sweep.dart
  packages/pdf_graphics/tool/perf_run_context.dart
  tool/perf/scenarios.json
)
for f in "${HARNESS[@]}"; do
  mkdir -p "$WORKTREE/$(dirname "$f")"
  cp "$ROOT/$f" "$WORKTREE/$f"
done

# Bootstrap refs that predate the perf tooling with the PdfPerf facade the
# harness imports - but only when absent: this one lives in lib/, and the ref
# must keep measuring its own library code.
BOOTSTRAP=(
  packages/pdf_cos/lib/perf.dart
  packages/pdf_cos/lib/src/perf/perf.dart
)
for f in "${BOOTSTRAP[@]}"; do
  if [ ! -e "$WORKTREE/$f" ]; then
    mkdir -p "$WORKTREE/$(dirname "$f")"
    cp "$ROOT/$f" "$WORKTREE/$f"
  fi
done

# Pre-seed the generated corpora so both sides read byte-identical input and
# the ref needs no generator. -n keeps the reused-worktree path cheap.
if [ -d "$ROOT/tool/perf/cache" ]; then
  mkdir -p "$WORKTREE/tool/perf/cache"
  cp -Rn "$ROOT/tool/perf/cache/." "$WORKTREE/tool/perf/cache/" 2>/dev/null || true
fi

OUT="${TMPDIR:-/tmp}/dart-pdf-perf-ab/results-$SHA-$$"
mkdir -p "$OUT"
: > "$OUT/current.ndjson"
: > "$OUT/ref.ndjson"

run_side() { # run_side <tree-root> <history-file>
  (cd "$1/packages/pdf_graphics" &&
    $DART run tool/perf_sweep.dart --scenario "$SCENARIO" \
      --append-history "$2" --out /dev/null 2>&1 |
    grep -v '^  \[' || true)
}

for i in $(seq 1 "$ITERATIONS"); do
  echo "── iteration $i/$ITERATIONS: current tree"
  run_side "$ROOT" "$OUT/current.ndjson"
  echo "── iteration $i/$ITERATIONS: $REF"
  run_side "$WORKTREE" "$OUT/ref.ndjson"
done

# Merge each side's iterations into one envelope of per-file best-of-all-runs
# so the diff sees ABAB-cancelled numbers.
$DART "$ROOT/tool/perf/merge_runs.dart" "$OUT/ref.ndjson" > "$OUT/ref.json"
$DART "$ROOT/tool/perf/merge_runs.dart" "$OUT/current.ndjson" > "$OUT/current.json"

echo
echo "══ $SCENARIO: $REF ($SHA) → working tree, $ITERATIONS interleaved runs"
STATUS=0
$DART "$ROOT/tool/perf/diff.dart" "$OUT/ref.json" "$OUT/current.json" \
  --threshold "$THRESHOLD" --targets "$ROOT/tool/perf/targets.json" || STATUS=$?

if [ "$CLEAN" = 1 ]; then
  git -C "$ROOT" worktree remove --force "$WORKTREE"
fi
exit "$STATUS"
