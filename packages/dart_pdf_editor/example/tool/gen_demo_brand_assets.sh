#!/usr/bin/env bash
#
# Regenerates lib/demo_brand_assets.dart — the base64-embedded brand artwork
# the feature-showcase demo stamps onto its title page. The mark and banner
# are rasterized from the repo's master SVGs so the demo stays in sync with
# the app icon / README banner without bundling Flutter assets (keeping
# buildDemoPdf synchronous and self-contained).
#
# Requires rsvg-convert (brew install librsvg).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
OUT="$SCRIPT_DIR/../lib/demo_brand_assets.dart"

tmp_logo="$(mktemp -t demo_logo).png"
tmp_banner="$(mktemp -t demo_banner).png"
trap 'rm -f "$tmp_logo" "$tmp_banner"' EXIT

rsvg-convert -w 160 -h 160 "$REPO_ROOT/doc/logo.svg"   -o "$tmp_logo"
rsvg-convert -w 960 -h 300 "$REPO_ROOT/doc/banner.svg" -o "$tmp_banner"

logo_b64="$(base64 -i "$tmp_logo" | tr -d '\n')"
banner_b64="$(base64 -i "$tmp_banner" | tr -d '\n')"

{
  echo "// GENERATED brand artwork for the feature-showcase demo document."
  echo "// The mark and banner are rendered from doc/logo.svg / doc/banner.svg"
  echo "// (rsvg-convert) and base64-embedded so buildDemoPdf stays synchronous"
  echo "// and asset-free. Regenerate with tool/gen_demo_brand_assets.sh."
  echo "import 'dart:convert';"
  echo "import 'dart:typed_data';"
  echo ""
  echo "/// 160×160 RGBA PNG of the dart-pdf app mark (doc/logo.svg)."
  echo "Uint8List demoLogoPng() => base64Decode(_logo);"
  echo ""
  echo "/// 960×300 RGB PNG of the dart-pdf banner (doc/banner.svg)."
  echo "Uint8List demoBannerPng() => base64Decode(_banner);"
  echo ""
  echo "const String _logo = '${logo_b64}';"
  echo ""
  echo "const String _banner = '${banner_b64}';"
} > "$OUT"

echo "wrote $OUT"
