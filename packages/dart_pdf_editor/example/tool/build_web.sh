#!/usr/bin/env bash
# Builds the SDK demo for the web with the off-thread render worker and
# content-hashed stable resource URLs.
set -euo pipefail

EXAMPLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$EXAMPLE_DIR/../../.." && pwd)"

cd "$EXAMPLE_DIR"

DART="${DART:-fvm dart}"
FLUTTER="${FLUTTER:-fvm flutter}"

echo "==> Building the render worker"
$DART run dart_pdf_editor:build_web_worker

echo "==> flutter build web $*"
$FLUTTER build web "$@"

echo "==> Cache-busting web entrypoints and fonts"
bash "$REPO_ROOT/tool/web_cache_bust.sh" build/web

echo "==> Done. build/web is ready for Firebase Hosting."
