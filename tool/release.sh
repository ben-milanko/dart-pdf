#!/usr/bin/env bash
#
# Manual pub.dev release for every workspace package.
#
# Publishes packages in dependency order. Because the cross-package
# constraints are hosted, not path, so each package must be live on pub.dev
# before a dependent can resolve — the script waits for each version to appear
# before publishing the next.
#
# Usage:
#   tool/release.sh                 # dry-run every package (no publishing)
#   tool/release.sh --publish       # actually publish (prompts once)
#   tool/release.sh --publish --yes # publish without the confirmation prompt
#
# Requires `fvm` and a pub.dev session (run `fvm dart pub token add https://pub.dev`
# or `fvm dart pub login` first if you are not authenticated).

set -euo pipefail

cd "$(dirname "$0")/.."

DART=(fvm dart)

# package:directory, in publish order (dependencies first).
PACKAGES=(
  "pdf_cos:packages/pdf_cos"
  "pdf_test_fixtures:packages/pdf_test_fixtures"
  "pdf_document:packages/pdf_document"
  "pdf_graphics:packages/pdf_graphics"
  "dart_pdf_editor:packages/dart_pdf_editor"
  "pdf_ocr_vlm:packages/pdf_ocr_vlm"
  "pdf_ocr_ondevice:packages/pdf_ocr_ondevice"
)

PUBLISH=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --help|-h)
      awk '
        NR == 1 { next }
        /^#/ { sub(/^# ?/, ""); print; next }
        { exit }
      ' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

version_for() {
  pubspec_value "$1/pubspec.yaml" version
}

pubspec_name_for() {
  pubspec_value "$1/pubspec.yaml" name
}

pubspec_value() {
  local pubspec="$1" key="$2"
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key ":" {
      value = $0
      sub("^[[:space:]]*" key ":[[:space:]]*", "", value)
      sub("[[:space:]]*(#.*)?$", "", value)
      gsub(/^["'\''"]|["'\''"]$/, "", value)
      print value
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' "$pubspec"
}

validate_package_list() {
  local spec pkg dir actual
  for spec in "${PACKAGES[@]}"; do
    pkg="${spec%%:*}"
    dir="${spec#*:}"
    if [[ ! -f "$dir/pubspec.yaml" ]]; then
      echo "::error:: Missing package pubspec: $dir/pubspec.yaml" >&2
      return 1
    fi
    actual="$(pubspec_name_for "$dir")"
    if [[ "$actual" != "$pkg" ]]; then
      echo "::error:: Release list says $pkg for $dir, but pubspec name is $actual" >&2
      return 1
    fi
  done
}

# 0 if $version is already published for $package on pub.dev, 1 otherwise.
pub_has_version() {
  local package="$1" version="$2"
  curl -fsSL "https://pub.dev/api/packages/${package}" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if '$version' in [v['version'] for v in d.get('versions',[])] else 1)" \
    2>/dev/null
}

wait_for_pub() {
  local package="$1" version="$2"
  printf 'Waiting for %s %s to appear on pub.dev' "$package" "$version"
  for _ in $(seq 1 60); do
    if pub_has_version "$package" "$version"; then
      printf ' ok\n'
      return 0
    fi
    printf '.'
    sleep 10
  done
  printf '\n'
  echo "::error:: $package $version not visible on pub.dev after 10 minutes" >&2
  return 1
}

echo "==> Resolving workspace"
"${DART[@]}" pub get >/dev/null

echo "==> Static analysis"
"${DART[@]}" analyze --fatal-infos

validate_package_list

echo
echo "Release plan:"
for spec in "${PACKAGES[@]}"; do
  pkg="${spec%%:*}"; dir="${spec#*:}"; ver="$(version_for "$dir")"
  if pub_has_version "$pkg" "$ver"; then
    echo "  - $pkg $ver  (already on pub.dev — will skip)"
  else
    echo "  - $pkg $ver  (will publish)"
  fi
done
echo

if [[ "$PUBLISH" -eq 0 ]]; then
  echo "==> DRY RUN (pass --publish to release for real)"
  for spec in "${PACKAGES[@]}"; do
    pkg="${spec%%:*}"; dir="${spec#*:}"; ver="$(version_for "$dir")"
    if pub_has_version "$pkg" "$ver"; then
      echo "--- skip $pkg $ver (already published) ---"
      continue
    fi
    echo "--- dry-run $pkg $ver ---"
    ( cd "$dir" && "${DART[@]}" pub publish --dry-run )
  done
  echo
  echo "Dry run complete. Re-run with --publish to release."
  exit 0
fi

if [[ "$ASSUME_YES" -eq 0 ]]; then
  echo "This will PUBLISH the above packages to pub.dev. This is IRREVERSIBLE."
  read -r -p "Type 'release' to continue: " reply
  [[ "$reply" == "release" ]] || { echo "Aborted."; exit 1; }
fi

for spec in "${PACKAGES[@]}"; do
  pkg="${spec%%:*}"; dir="${spec#*:}"; ver="$(version_for "$dir")"

  if pub_has_version "$pkg" "$ver"; then
    echo "==> $pkg $ver already on pub.dev; skipping"
    continue
  fi

  echo "==> Publishing $pkg $ver"
  ( cd "$dir" && "${DART[@]}" pub publish --force )

  # Later packages depend on this one (^1.0.0, hosted), so it must resolve
  # before we publish them.
  wait_for_pub "$pkg" "$ver"
done

echo
echo "All packages released."
