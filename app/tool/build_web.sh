#!/usr/bin/env bash
# Builds the app for the web WITH the off-thread render worker.
#
# Flutter does not compile the dedicated Web Worker script, so build it first
# with the tool dart_pdf_editor ships, then `flutter build web` copies the
# resulting web/pdf_render_worker.dart.js into build/web alongside the app.
# The app opts in by setting `pdfRenderWorkerScriptUrl` at startup (lib/main.dart).
# See doc/render_worker_web.md for the full wiring.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$APP_DIR/.." && pwd)"

cd "$APP_DIR"

DART="${DART:-fvm dart}"
FLUTTER="${FLUTTER:-fvm flutter}"

echo "==> Building the render worker"
$DART run dart_pdf_editor:build_web_worker

echo "==> flutter build web $*"
$FLUTTER build web "$@"

echo "==> Cache-busting web entrypoints and fonts"
bash "$REPO_ROOT/tool/web_cache_bust.sh" build/web

echo "==> Done. build/web/pdf_render_worker.dart.js is served next to index.html."
