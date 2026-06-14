#!/usr/bin/env bash
# Builds the app for the web WITH the off-thread render worker.
#
# Flutter does not compile `web/` Dart files, so the dedicated Web Worker
# script (web/pdf_render_worker.dart) must be compiled to a standalone JS
# bundle first; `flutter build web` then copies it into build/web alongside
# the app. The app opts in by setting `pdfRenderWorkerScriptUrl` at startup
# (see lib/main.dart). See doc/render_worker_web.md for the full wiring.
set -euo pipefail

cd "$(dirname "$0")/.."

DART="${DART:-fvm dart}"
FLUTTER="${FLUTTER:-fvm flutter}"

echo "==> Compiling the render worker (web/pdf_render_worker.dart -> .js)"
$DART compile js web/pdf_render_worker.dart \
  -o web/pdf_render_worker.dart.js -O2

echo "==> flutter build web $*"
$FLUTTER build web "$@"

echo "==> Done. build/web/pdf_render_worker.dart.js is served next to index.html."
