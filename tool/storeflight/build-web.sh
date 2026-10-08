#!/usr/bin/env bash
# Use the repository's FVM SDK locally and the pinned runner SDK in CI.
set -euo pipefail

: "${STOREFLIGHT_VERSION:?Storeflight must provide the release version}"
: "${STOREFLIGHT_BUILD_NUMBER:?Storeflight must provide the build number}"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT/app"

if command -v fvm >/dev/null 2>&1; then
  export DART="${DART:-fvm dart}"
  export FLUTTER="${FLUTTER:-fvm flutter}"
else
  export DART="${DART:-dart}"
  export FLUTTER="${FLUTTER:-flutter}"
fi

bash tool/build_web.sh --release \
  --build-name="$STOREFLIGHT_VERSION" \
  --build-number="$STOREFLIGHT_BUILD_NUMBER"
mkdir -p build/storeflight/web
tar czf build/storeflight/web/app-web.tar.gz -C build web
