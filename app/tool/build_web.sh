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

# Stamp the build with its commit so a `?perf=1` trace says which build it
# came from. Without this a pasted device trace is unattributable by anything
# but timestamps, which has already produced one wrong conclusion (#451).
BUILD_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
  BUILD_COMMIT="$BUILD_COMMIT-dirty"
fi

echo "==> flutter build web (commit $BUILD_COMMIT) $*"
$FLUTTER build web --dart-define=PDF_BUILD_COMMIT="$BUILD_COMMIT" "$@"

echo "==> Cache-busting web entrypoints and fonts"
bash "$REPO_ROOT/tool/web_cache_bust.sh" build/web

echo "==> Done. build/web includes the dart_pdf_editor_assets worker asset."
