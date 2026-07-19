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
  if ! ( cd "$wt" && $FLUTTER pub get ) >/dev/null 2>&1; then
    echo "  pub get failed; skip"; skipped="$skipped $ref"
    git -C "$ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true; continue
  fi
  if ( cd "$wt/packages/dart_pdf_editor" &&
        PDF_BENCHMARK_DIR="../../test_corpora/ghent" \
        PDF_BENCHMARK_SCALE="$SCALE" PDF_BENCHMARK_MAX_PAGES="$MAXPAGES" \
        PDF_BENCHMARK_REPEAT="$REPEAT" PDF_BENCHMARK_SCENARIO=ghent-render \
        PDF_BENCHMARK_APPEND_HISTORY="$HIST/flutter-render.ndjson" \
        $FLUTTER test test/benchmark_render_test.dart ); then
    echo "  rendered ok -> $HIST/flutter-render.ndjson"; ok=$((ok+1))
  else
    echo "  render bench failed; skip"; skipped="$skipped $ref"
  fi
  git -C "$ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
done

echo "render backfill done: $ok measured;${skipped:- none skipped}"
