#!/usr/bin/env bash
# CanvasKit vs skwasm web render benchmark.
#
# Builds the example's web_benchmark entrypoint twice (default = CanvasKit,
# --wasm = skwasm), serves each with cross-origin-isolation headers, drives it
# in headless Chromium via Playwright, and prints a side-by-side table.
#
#   benchmark/web/run.sh [corpus_dir] [count] [scale] [maxPages] [repeat]
#
# Defaults: corpus=test_corpora/pdfjs, count=20, scale=2, maxPages=5, repeat=3.
#
# Requirements: fvm/flutter 3.44.8, node, global playwright (+ chromium),
# python3 (for the compare table).
set -euo pipefail

CORPUS="${1:-}"
COUNT="${2:-20}"
SCALE="${3:-2}"
MAXPAGES="${4:-5}"
REPEAT="${5:-3}"
PORT="${PORT:-8099}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
EXAMPLE="$REPO/packages/dart_pdf_editor/example"
OUT="$HERE/out"
mkdir -p "$OUT"

if [[ -z "$CORPUS" ]]; then CORPUS="$REPO/test_corpora/pdfjs"; fi
CORPUS="$(cd "$CORPUS" && pwd)"

FLUTTER="${FLUTTER:-$HOME/fvm/versions/3.44.8/bin/flutter}"
export NODE_PATH="${NODE_PATH:-$(npm root -g)}"

echo "==> manifest ($COUNT files from $CORPUS, scale=$SCALE, maxPages=$MAXPAGES, repeat=$REPEAT)"
node "$HERE/gen_manifest.cjs" --corpus "$CORPUS" --count "$COUNT" \
  --scale "$SCALE" --maxPages "$MAXPAGES" --repeat "$REPEAT" \
  --out "$HERE/manifest.json"

build() {  # build <flag> <outdir>
  local flag="$1" dir="$2"
  echo "==> flutter build web $flag (-> $dir)"
  # --no-web-resources-cdn bundles canvaskit/skwasm locally instead of pulling
  # them from the gstatic CDN (the sandboxed browser can't validate the CDN's
  # TLS cert, and a fair comparison shouldn't depend on network either).
  ( cd "$EXAMPLE" && "$FLUTTER" build web --release --no-web-resources-cdn \
      $flag -t lib/web_benchmark.dart )
  rm -rf "$dir"
  cp -r "$EXAMPLE/build/web" "$dir"
  echo "    bundle size: $(du -sh "$dir" | cut -f1)"
}

drive() {  # drive <tool> <builddir> <outjson>
  local tool="$1" dir="$2" json="$3"
  echo "==> serve + drive $tool"
  node "$HERE/serve.cjs" --root "$dir" --corpus "$CORPUS" \
    --manifest "$HERE/manifest.json" --port "$PORT" &
  local srv=$!
  trap "kill $srv 2>/dev/null || true" RETURN
  sleep 1
  node "$HERE/drive.cjs" --url "http://localhost:$PORT/" --tool "$tool" \
    --out "$json" --timeout 1800000
  kill "$srv" 2>/dev/null || true
  trap - RETURN
}

build ""        "$OUT/build-canvaskit"
build "--wasm"  "$OUT/build-skwasm"

drive canvaskit "$OUT/build-canvaskit" "$OUT/web-canvaskit.json"
drive skwasm    "$OUT/build-skwasm"    "$OUT/web-skwasm.json"

echo
echo "==> comparison"
python3 "$REPO/benchmark/compare.py" "$OUT/web-canvaskit.json" \
  "$OUT/web-skwasm.json" --per-file || true
