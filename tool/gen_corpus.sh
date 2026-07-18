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
ls -la "$OUT" | awk 'NR>1 {print "  " $NF "\t" $5 " bytes"}' | grep -v '^\s*\.'
