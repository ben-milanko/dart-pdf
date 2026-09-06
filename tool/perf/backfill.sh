#!/usr/bin/env bash
# Backfill VM-sweep perf history for OLD commits that predate the perf harness
# (PR #356, bd473c17). For each ref it checks the commit out in a throwaway
# worktree, GRAFTS the current perf harness on top (additive; the code under
# test is untouched), resolves deps, and runs the CI-safe VM scenarios.
#
# Scenarios (override with the SCENARIOS env var):
#   ghent-suite-open  parse/interpret on the checked-in ghent corpus (stable
#                     from 1.3.0 on)
#   cad-138p-sweep    heavy synthetic 138p x 6000-op doc — stresses interpret
#                     and peak RSS. The doc is DETERMINISTIC (fixed seed) and
#                     generated ONCE here with current code, then pre-seeded
#                     into every worktree's cache, so (a) all versions measure
#                     the identical input and (b) old commits don't need the
#                     generator to compile.
#
# Wall-time only compares within one machine, so run every ref in ONE job.
# The recorded rev is the ORIGINAL old commit (rev.dirty=true flags the graft).
#
# Usage: tool/perf/backfill.sh <history-dir> <ref>...
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HIST="${1:?usage: backfill.sh <history-dir> <ref>...}"; shift || true
[ "$#" -ge 1 ] || { echo "usage: backfill.sh <history-dir> <ref>..." >&2; exit 2; }
mkdir -p "$HIST"; HIST="$(cd "$HIST" && pwd)"

DART=dart; FLUTTER=flutter
if command -v fvm >/dev/null 2>&1; then DART="fvm dart"; FLUTTER="fvm flutter"; fi

SCENARIOS="${SCENARIOS:-ghent-suite-open cad-138p-sweep image-heavy}"

# Harness files grafted onto each old commit (additive; from the current tree).
GRAFT=(
  packages/pdf_cos/lib/perf.dart
  packages/pdf_cos/lib/src/perf
  packages/pdf_graphics/tool/perf_sweep.dart
  packages/pdf_graphics/tool/perf_run_context.dart
  tool/perf/scenarios.json
)

# Deterministic heavy synthetic docs (cad-138p, image-heavy) too big to commit.
# Generate once here with current code, then pre-seed the SAME bytes into every
# worktree so all versions measure identical input and old commits need no
# generator. These live under tool/perf/cache/ (git-ignored).
"$(dirname "$0")/gen_perf_docs.sh"
CAD_CACHE="tool/perf/cache/cad-138-6000-20260718.pdf"
IMG_CACHE_DIR="tool/perf/cache/image-heavy"
JBIG2_CACHE_DIR="tool/perf/cache/jbig2-scanned"

ok=0; skipped=""
for ref in "$@"; do
  if ! sha="$(git -C "$ROOT" rev-parse --verify -q "$ref^{commit}")"; then
    echo "!! $ref: not a commit; skip"; skipped="$skipped $ref"; continue
  fi
  wt="$(mktemp -d)/wt"
  echo "== backfill $ref (${sha:0:8}) =="
  if ! git -C "$ROOT" worktree add --detach "$wt" "$sha" >/dev/null 2>&1; then
    echo "  worktree add failed; skip"; skipped="$skipped $ref"; continue
  fi
  for f in "${GRAFT[@]}"; do
    mkdir -p "$wt/$(dirname "$f")"
    cp -R "$ROOT/$f" "$wt/$f"
  done
  # Pre-seed the identical synthetic docs so old commits skip generation.
  if [ -f "$ROOT/$CAD_CACHE" ]; then
    mkdir -p "$wt/$(dirname "$CAD_CACHE")"; cp "$ROOT/$CAD_CACHE" "$wt/$CAD_CACHE"
  fi
  if [ -d "$ROOT/$IMG_CACHE_DIR" ]; then
    mkdir -p "$wt/$IMG_CACHE_DIR"; cp "$ROOT/$IMG_CACHE_DIR"/*.pdf "$wt/$IMG_CACHE_DIR/" 2>/dev/null || true
  fi
  if [ -d "$ROOT/$JBIG2_CACHE_DIR" ]; then
    mkdir -p "$wt/$JBIG2_CACHE_DIR"; cp "$ROOT/$JBIG2_CACHE_DIR"/*.pdf "$wt/$JBIG2_CACHE_DIR/" 2>/dev/null || true
  fi
  if ! ( cd "$wt" && $FLUTTER pub get ) >/dev/null 2>&1; then
    echo "  pub get failed (dep drift); skip"; skipped="$skipped $ref"
    git -C "$ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true; continue
  fi
  measured=0
  for scen in $SCENARIOS; do
    if ( cd "$wt/packages/pdf_graphics" &&
          $DART run tool/perf_sweep.dart --scenario "$scen" \
            --append-history "$HIST/vm-sweep.ndjson" --out /dev/null ); then
      echo "  $scen ok"; measured=$((measured+1))
    else
      echo "  $scen failed (API drift?); skip"; skipped="$skipped $ref/$scen"
    fi
  done
  [ "$measured" -gt 0 ] && ok=$((ok+1))
  git -C "$ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
done

echo "backfill done: $ok refs measured;${skipped:- none skipped}"
