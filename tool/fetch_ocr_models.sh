#!/usr/bin/env bash
#
# Put the PP-OCRv5 mobile OCR models into a Flutter web build, so the app's
# browser OCR (web/index.html's onnxruntime-web bridge) can load them from its
# own origin - GitHub release downloads send no CORS headers, so a browser
# can't fetch them from the release directly.
#
#   tool/fetch_ocr_models.sh [build-web-dir]     (default: app/build/web)
#
# Writes <dir>/ocr/pp-ocrv5-mobile/{det.onnx,rec.onnx,dict.txt} (~21 MB),
# each verified against the SHA-256 that pdf_ocr_ondevice pins for the native
# download (PdfOcrModels.ppOcrV5Mobile; test/fetch_ocr_models_test.dart keeps
# the two in step). OCR_MODELS_SRC=<dir> copies from a directory holding the
# release files instead of downloading them. For `flutter run -d chrome`, point
# it at app/web (git-ignored there).
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [build-web-dir]" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$REPO_ROOT/app/build/web}/ocr/pp-ocrv5-mobile"
BASE_URL="https://github.com/ben-milanko/dart-pdf/releases/download/ocr-models-v1"

# local name | release asset | sha256
MODELS=(
  "det.onnx|PP-OCRv5_mobile_det.onnx|d5de5df358366210d16419b9636a2fc1efa5d7a20688f38a7869ec7b1a4f4f7d"
  "rec.onnx|PP-OCRv5_mobile_rec.onnx|0030c6b05fbe29b07a93701503938d637efe7423325e2efb2bd7c8f220d40a8d"
  "dict.txt|ppocrv5_dict.txt|d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b"
)

sha256() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

mkdir -p "$DEST"
for entry in "${MODELS[@]}"; do
  IFS='|' read -r name asset want <<<"$entry"
  out="$DEST/$name"
  if [[ -f "$out" && "$(sha256 "$out")" == "$want" ]]; then
    echo "ok      $name (already present)"
    continue
  fi
  tmp="$out.part"
  if [[ -n "${OCR_MODELS_SRC:-}" ]]; then
    cp "$OCR_MODELS_SRC/$asset" "$tmp"
  else
    curl -fsSL --retry 4 -o "$tmp" "$BASE_URL/$asset"
  fi
  got="$(sha256 "$tmp")"
  if [[ "$got" != "$want" ]]; then
    rm -f "$tmp"
    echo "error: $asset sha256 $got, expected $want" >&2
    exit 1
  fi
  mv "$tmp" "$out"
  echo "fetched $name"
done
