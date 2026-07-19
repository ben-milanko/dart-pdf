#!/usr/bin/env bash
# Generates the deterministic heavy synthetic docs the perf scenarios use but
# are too big to commit (git-ignored under tool/perf/cache/). Idempotent: skips
# a doc that already exists. Run once with CURRENT code, then pre-seed the same
# bytes into every backfill worktree so all versions measure identical input.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DART=dart
command -v fvm >/dev/null 2>&1 && DART="fvm dart"

CAD="$ROOT/tool/perf/cache/cad-138-6000-20260718.pdf"
IMG="$ROOT/tool/perf/cache/image-heavy/image-heavy-24p.pdf"

if [ ! -f "$CAD" ]; then
  echo "gen cad-138p -> $CAD"
  mkdir -p "$(dirname "$CAD")"
  ( cd "$ROOT" && $DART run packages/pdf_cos/tool/gen_cad_pdf.dart "$CAD" 138 6000 20260718 )
fi

if [ ! -f "$IMG" ]; then
  echo "gen image-heavy -> $IMG"
  mkdir -p "$(dirname "$IMG")"
  ( cd "$ROOT" && $DART run packages/pdf_cos/tool/gen_image_pdf.dart "$IMG" 24 1240 1650 )
fi

echo "perf docs ready under $ROOT/tool/perf/cache"
