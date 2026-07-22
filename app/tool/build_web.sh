#!/usr/bin/env bash
# Builds the app for the web with a freshly regenerated bundled render worker.
#
# Consumer apps get the worker from the optional dart_pdf_editor_assets package.
# This repo script rebuilds that asset first so local source changes and deploys
# stay in sync. See doc/render_worker_web.md for the full wiring.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$APP_DIR/.." && pwd)"

cd "$APP_DIR"

DART="${DART:-fvm dart}"
FLUTTER="${FLUTTER:-fvm flutter}"

echo "==> Regenerating the bundled render worker asset"
$DART run dart_pdf_editor:build_web_worker \
  --out ../packages/dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js

echo "==> flutter build web $*"
$FLUTTER build web "$@"

echo "==> Cache-busting web entrypoints and fonts"
bash "$REPO_ROOT/tool/web_cache_bust.sh" build/web

echo "==> Done. build/web includes the dart_pdf_editor_assets worker asset."
