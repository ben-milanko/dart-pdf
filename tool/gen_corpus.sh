#!/usr/bin/env bash
# Regenerates the dart-pdf public test corpus (test_corpora/dartpdf/).
# The committed bytes are the measurement contract - rerun this only for a
# deliberate corpus change and review the git diff like a baseline update.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/test_corpora/dartpdf"

DART=dart
if command -v fvm >/dev/null 2>&1; then DART="fvm dart"; fi

echo "generating public corpus into $OUT"
(cd "$ROOT/packages/pdf_document" &&
  $DART run tool/gen_public_corpus.dart --out "$OUT")
# Dense CAD sheet: same generator/params family as the perf scenarios, small
# enough to commit (8 A1 pages).
(cd "$ROOT" &&
  $DART packages/pdf_cos/tool/gen_cad_pdf.dart "$OUT/cad-sheet-8p.pdf" \
    8 6000 20260718)
# Diagram-dense sheets: the rail/utility circuit-diagram class profiled from
# a real (unredistributable) ARTC overhead-wiring diagram - ~280k content
# ops per page, ~5 MB decoded content per page, tokenizer/interpreter
# saturation. Same generator, density cranked 5x.
(cd "$ROOT" &&
  $DART packages/pdf_cos/tool/gen_cad_pdf.dart "$OUT/diagram-dense-3p.pdf" \
    3 80000 20260721)
# Plan-set sheets: the multi-sheet territory-plan class profiled from a real
# (unredistributable) 58-sheet rail plan - sustained ~80k ops/page across
# the whole set, high peak RSS. 16 committed pages carry the per-sheet
# density; FULL-set scale (memory pressure, prefetch) lives in the
# generated cad-138p-sweep scenario, not in the repo.
(cd "$ROOT" &&
  $DART packages/pdf_cos/tool/gen_cad_pdf.dart "$OUT/plan-set-16p.pdf" \
    16 23000 20260722)
# Raster-underlay sheet: the giant-image survey/CAD class profiled from a real
# (unredistributable) ~8 MB single-page drawing - two 9460x2918 DeviceRGB
# underlays, each with a full-size non-DCT grayscale soft mask, under 71 OCG
# layers (~221 MB RGBA if decoded at native resolution). The committed variant
# is FlateDecode (hermetic); the DCTDecode variant that reproduces the
# platform-JPEG decode pathology is a generated perf-cache doc, not committed.
(cd "$ROOT" &&
  $DART packages/pdf_test_fixtures/tool/gen_raster_underlay_pdf.dart \
    "$OUT/raster-underlay-1p.pdf" faithful 2 9460 2918 71 6000 20260722)
# Hatched-sections sheets: tiling-pattern (PatternType 1) fills - ~70 regions
# per A1 page over four shared pattern cells, the per-tile re-interpretation
# workload behind #524 (hatch-sections-sweep / scroll-hatch scenarios).
(cd "$ROOT" &&
  $DART packages/pdf_cos/tool/gen_hatch_pdf.dart \
    "$OUT/hatch-sections-4p.pdf" 4 70 20260724)
# Type3-font text: the TeX-era CharProc-per-glyph class - half vector procs,
# half 1-bit inline ImageMasks (#535; type3-text-sweep / type3-text-render).
(cd "$ROOT" &&
  $DART packages/pdf_cos/tool/gen_type3_pdf.dart \
    "$OUT/type3-text-6p.pdf" 6 9000 20260724)
ls -la "$OUT" | awk 'NR>1 {print "  " $NF "\t" $5 " bytes"}' | grep -v '^\s*\.'
