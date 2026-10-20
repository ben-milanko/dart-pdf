#!/usr/bin/env bash
# Backfill the RENDER trend (full page rasterization: interpret + paint +
# toImage) for old commits. Same graft trick as backfill.sh, but drives the
# Flutter headless render benchmark instead of the VM sweep, so it captures the
# paint- and image-decode-path gains (e.g. the #282 DeviceN work) the NullDevice
# VM sweep can't see. Corpus is the checked-in ghent suite (stable across
# versions), rendered at a fixed scale so the numbers form a real trend.
#
# Run every ref in ONE job (Flutter wall-time only compares within a machine).
# Usage: tool/perf/render_backfill.sh <history-dir> <ref>...
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HIST="${1:?usage: render_backfill.sh <history-dir> <ref>...}"; shift || true
[ "$#" -ge 1 ] || { echo "usage: render_backfill.sh <history-dir> <ref>..." >&2; exit 2; }
mkdir -p "$HIST"; HIST="$(cd "$HIST" && pwd)"

FLUTTER=flutter
command -v fvm >/dev/null 2>&1 && FLUTTER="fvm flutter"

# Fixed render params (documented as scenario "ghent-render" in scenarios.json).
SCALE="${PDF_BENCHMARK_SCALE:-2}"
MAXPAGES="${PDF_BENCHMARK_MAX_PAGES:-3}"
REPEAT="${PDF_BENCHMARK_REPEAT:-2}"

# The only graft the render benchmark needs is the test file itself (the render
# API + render_smoke_test.dart's loadSystemFonts already exist back to 1.3.0).
BENCH="packages/dart_pdf_editor/test/benchmark_render_test.dart"
# Generated corpora (git-ignored) pre-seeded into every worktree.
GEN_CORPORA=(tool/perf/cache/image-heavy tool/perf/cache/devicen)

# Ensure the generated heavy docs exist (used as flutter-render corpora).
"$(dirname "$0")/gen_perf_docs.sh"

# Render scenarios: "name|corpus-relative-to-dart_pdf_editor|scale|maxPages".
RENDER_SCENARIOS=(
  "ghent-render|../../test_corpora/ghent|2|3"
  "image-render|../../tool/perf/cache/image-heavy|1.5|4"
  "devicen-render|../../tool/perf/cache/devicen|1|2"
)

ok=0; skipped=""
for ref in "$@"; do
  if ! sha="$(git -C "$ROOT" rev-parse --verify -q "$ref^{commit}")"; then
    echo "!! $ref: not a commit; skip"; skipped="$skipped $ref"; continue
  fi
  wt="$(mktemp -d)/wt"
  echo "== render backfill $ref (${sha:0:8}) =="
  if ! git -C "$ROOT" worktree add --detach "$wt" "$sha" >/dev/null 2>&1; then
    echo "  worktree add failed; skip"; skipped="$skipped $ref"; continue
  fi
  cp "$ROOT/$BENCH" "$wt/$BENCH"
  # Pre-seed the generated docs so every version renders identical input.
  for d in "${GEN_CORPORA[@]}"; do
    if [ -d "$ROOT/$d" ]; then
      mkdir -p "$wt/$d"; cp "$ROOT/$d"/*.pdf "$wt/$d/" 2>/dev/null || true
    fi
  done
  if ! ( cd "$wt" && $FLUTTER pub get ) >/dev/null 2>&1; then
    echo "  pub get failed; skip"; skipped="$skipped $ref"
    git -C "$ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true; continue
  fi
  measured=0
  for entry in "${RENDER_SCENARIOS[@]}"; do
    IFS='|' read -r name corpus scn_scale scn_max <<<"$entry"
    if ( cd "$wt/packages/dart_pdf_editor" &&
          PDF_BENCHMARK_DIR="$corpus" \
          PDF_BENCHMARK_SCALE="$scn_scale" PDF_BENCHMARK_MAX_PAGES="$scn_max" \
          PDF_BENCHMARK_REPEAT="$REPEAT" PDF_BENCHMARK_SCENARIO="$name" \
          PDF_BENCHMARK_APPEND_HISTORY="$HIST/flutter-render.ndjson" \
          $FLUTTER test test/benchmark_render_test.dart ); then
      echo "  $name ok"; measured=$((measured+1))
    else
      echo "  $name failed; skip"; skipped="$skipped $ref/$name"
    fi
  done
  [ "$measured" -gt 0 ] && ok=$((ok+1))
  git -C "$ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
done

echo "render backfill done: $ok refs measured;${skipped:- none skipped}"
