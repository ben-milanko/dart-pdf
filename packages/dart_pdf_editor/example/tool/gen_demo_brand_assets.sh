#!/usr/bin/env bash
#
# Regenerates lib/demo_brand_assets.dart — the base64-embedded brand artwork
# the feature-showcase demo stamps onto its title page. The mark is rasterized
# from the repo's master SVG; the banner is a light-mode variant of the README
# banner so it reads naturally on the demo PDF's white title page.
#
# Requires rsvg-convert (brew install librsvg).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
OUT="$SCRIPT_DIR/../lib/demo_brand_assets.dart"

tmp_logo="$(mktemp -t demo_logo).png"
tmp_banner="$(mktemp -t demo_banner).png"
tmp_banner_svg="$(mktemp -t demo_banner_light).svg"
trap 'rm -f "$tmp_logo" "$tmp_banner" "$tmp_banner_svg"' EXIT

rsvg-convert -w 160 -h 160 "$REPO_ROOT/doc/logo.svg"   -o "$tmp_logo"
sed \
  -e 's/fill="#202124"/fill="#F7FAFC"/' \
  -e 's/fill="#FFFFFF">dart-pdf/fill="#202124">dart-pdf/' \
  -e 's/fill="#9AA0A6">Pure-Dart/fill="#5F6B75">Pure-Dart/' \
  "$REPO_ROOT/doc/banner.svg" > "$tmp_banner_svg"
rsvg-convert -w 960 -h 300 "$tmp_banner_svg" -o "$tmp_banner"

logo_b64="$(base64 -i "$tmp_logo" | tr -d '\n')"
banner_b64="$(base64 -i "$tmp_banner" | tr -d '\n')"

{
  echo "// GENERATED brand artwork for the feature-showcase demo document."
  echo "// The mark is rendered from doc/logo.svg; the banner is a light-mode"
  echo "// variant of doc/banner.svg. Both are base64-embedded so buildDemoPdf"
  echo "// stays synchronous and asset-free. Regenerate with tool/gen_demo_brand_assets.sh."
  echo "import 'dart:convert';"
  echo "import 'dart:typed_data';"
  echo ""
  echo "/// 160×160 RGBA PNG of the dart-pdf app mark (doc/logo.svg)."
  echo "Uint8List demoLogoPng() => base64Decode(_logo);"
  echo ""
  echo "/// 960×300 RGB PNG of the light-mode dart-pdf banner."
  echo "Uint8List demoBannerPng() => base64Decode(_banner);"
  echo ""
  echo "const String _logo = '${logo_b64}';"
  echo ""
  echo "const String _banner = '${banner_b64}';"
} > "$OUT"

echo "wrote $OUT"
