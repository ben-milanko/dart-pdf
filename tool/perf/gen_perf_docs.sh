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
CADWIDE="$ROOT/tool/perf/cache/cad-wide-850000-8-20260718.pdf"
IMG="$ROOT/tool/perf/cache/image-heavy/image-heavy-24p.pdf"
DN="$ROOT/tool/perf/cache/devicen/devicen-8p.pdf"
CADIMG="$ROOT/tool/perf/cache/cad-images/cad-images-1386-20260720.pdf"
CADIMGMIX="$ROOT/tool/perf/cache/cad-images/cad-images-mixed-200-20260720.pdf"

if [ ! -f "$CAD" ]; then
  echo "gen cad-138p -> $CAD"
  mkdir -p "$(dirname "$CAD")"
  ( cd "$ROOT" && $DART run packages/pdf_cos/tool/gen_cad_pdf.dart "$CAD" 138 6000 20260718 )
fi

if [ ! -f "$CADWIDE" ]; then
  echo "gen cad-wide-1p (single ultra-wide strip) -> $CADWIDE"
  mkdir -p "$(dirname "$CADWIDE")"
  ( cd "$ROOT" && $DART run packages/pdf_test_fixtures/tool/gen_cad_wide_pdf.dart "$CADWIDE" 850000 8 20260718 )
fi

if [ ! -f "$IMG" ]; then
  echo "gen image-heavy -> $IMG"
  mkdir -p "$(dirname "$IMG")"
  ( cd "$ROOT" && $DART run packages/pdf_cos/tool/gen_image_pdf.dart "$IMG" 24 1240 1650 )
fi

if [ ! -f "$CADIMG" ]; then
  echo "gen cad-images (image-heavy wide CAD sheet) -> $CADIMG"
  mkdir -p "$(dirname "$CADIMG")"
  ( cd "$ROOT" && $DART run packages/pdf_test_fixtures/tool/gen_cad_image_pdf.dart \
      "$CADIMG" faithful )
fi

# The mixed-codec variant needs cjpeg + opj_compress, which CI does not have -
# generate it locally and pre-seed like the others. Skipped (not failed) when
# the encoders are missing, so a plain `gen_perf_docs.sh` still succeeds.
if [ ! -f "$CADIMGMIX" ]; then
  if command -v cjpeg >/dev/null 2>&1 && command -v opj_compress >/dev/null 2>&1; then
    echo "gen cad-images-mixed (DCT + JPX tiles) -> $CADIMGMIX"
    mkdir -p "$(dirname "$CADIMGMIX")"
    ( cd "$ROOT" && $DART run packages/pdf_test_fixtures/tool/gen_cad_image_pdf.dart \
        "$CADIMGMIX" mixed 200 2048 1754 100000 )
  else
    echo "skip cad-images-mixed: cjpeg/opj_compress not on PATH" >&2
  fi
fi

if [ ! -f "$DN" ]; then
  echo "gen devicen -> $DN"
  mkdir -p "$(dirname "$DN")"
  ( cd "$ROOT" && $DART run packages/pdf_cos/tool/gen_devicen_pdf.dart "$DN" 8 1240 1650 )
fi

# Raster-underlay sheet, DCTDecode variant: two 9460x2918 JPEG underlays under
# non-DCT gray soft masks + 71 OCG layers - the shape that forces the platform
# JPEG codec at native resolution (the committed corpus twin is FlateDecode).
# Needs cjpeg, which CI lacks - skipped (not failed) when it is missing.
UNDERLAY="$ROOT/tool/perf/cache/raster-underlay/raster-underlay-mixed-2x9460x2918.pdf"
if [ ! -f "$UNDERLAY" ]; then
  if command -v cjpeg >/dev/null 2>&1; then
    echo "gen raster-underlay-mixed (DCT underlays) -> $UNDERLAY"
    mkdir -p "$(dirname "$UNDERLAY")"
    ( cd "$ROOT" && $DART run packages/pdf_test_fixtures/tool/gen_raster_underlay_pdf.dart \
        "$UNDERLAY" mixed 2 9460 2918 71 6000 20260722 )
  else
    echo "skip raster-underlay-mixed: cjpeg not on PATH" >&2
  fi
fi

echo "perf docs ready under $ROOT/tool/perf/cache"
