#!/usr/bin/env bash
# Analyze dart_pdf_editor (and the pure-Dart packages it builds on) on the
# lowest Flutter the editor declares, so the `flutter: '>=x.y.z'` floor in its
# pubspec stays honest. CI's `floor-analyze` job runs this on that Flutter;
# every other job runs the pinned `.fvmrc` version, which says nothing about
# the floor (5.0.0 declared >=3.24.0 but used a 3.44 API for months).
#
# It has to run OUTSIDE the pub workspace: the workspace also holds
# dart_pdf_printing (flutter >=3.47.0), so it cannot resolve on the floor SDK.
# The four packages are copied to a temp dir, `resolution: workspace` is
# stripped, the inter-package dependencies become path dependencies and the
# workspace-only dev dependency (pdf_test_fixtures) is dropped. Only `lib/` is
# analyzed: tests may use newer SDK conveniences, the published API may not.
#
# Usage: tool/floor_analyze.sh            (uses `flutter` on PATH)
#        FLUTTER=~/fvm/versions/3.44.0/bin/flutter tool/floor_analyze.sh
set -euo pipefail

FLUTTER=${FLUTTER:-flutter}
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/floor_analyze.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

"$FLUTTER" --version

packages=(pdf_cos pdf_document pdf_graphics dart_pdf_editor)
for pkg in "${packages[@]}"; do
  src="$root/packages/$pkg"
  dst="$tmp/$pkg"
  mkdir -p "$dst"
  cp -R "$src/lib" "$dst/"
  cp "$src/pubspec.yaml" "$src/analysis_options.yaml" "$dst/"
  for extra in l10n.yaml shaders; do
    if [ -e "$src/$extra" ]; then cp -R "$src/$extra" "$dst/"; fi
  done
  perl -pi -e '
    $_ = "" if /^resolution:\s*workspace\s*$/;
    $_ = "" if /^\s+pdf_test_fixtures:/;
    s{^(\s+)(pdf_cos|pdf_document|pdf_graphics):\s*\S.*$}{$1$2: {path: ../$2}};
  ' "$dst/pubspec.yaml"
done

status=0
for pkg in "${packages[@]}"; do
  echo "::group::$pkg"
  (cd "$tmp/$pkg" && "$FLUTTER" pub get) || status=1
  # Infos are not fatal here: a lint that only fires on an older analyzer is
  # not a floor violation. Errors and warnings (an API missing on the floor
  # SDK) are.
  (cd "$tmp/$pkg" && "$FLUTTER" analyze --no-fatal-infos lib) || status=1
  echo "::endgroup::"
done
exit $status
