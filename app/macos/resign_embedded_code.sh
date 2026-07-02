#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 path/to/DartPDF.app" >&2
  exit 64
fi

app_bundle="$1"
if [[ ! -d "$app_bundle/Contents" ]]; then
  echo "error: not a macOS .app bundle: $app_bundle" >&2
  exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
frameworks_dir="$app_bundle/Contents/Frameworks"
identity="${CODESIGN_IDENTITY:-${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}}"
if [[ -z "$identity" ]]; then
  identity="-"
fi

entitlements="${CODESIGN_ENTITLEMENTS:-}"
if [[ -z "$entitlements" && -f "$script_dir/Runner/Release.entitlements" ]]; then
  entitlements="$script_dir/Runner/Release.entitlements"
fi

sign_code() {
  local path="$1"
  echo "codesign: $path"
  /usr/bin/codesign --force --sign "$identity" "$path"
}

if [[ -d "$frameworks_dir" ]]; then
  while IFS= read -r -d '' file; do
    if /usr/bin/file -b "$file" | grep -q 'Mach-O'; then
      sign_code "$file"
    fi
  done < <(find "$frameworks_dir" -type f -print0)

  while IFS= read -r -d '' framework; do
    sign_code "$framework"
  done < <(find "$frameworks_dir" -depth -type d -name '*.framework' -print0)
fi

app_sign_args=(--force --options runtime --sign "$identity")
if [[ -n "$entitlements" ]]; then
  app_sign_args+=(--entitlements "$entitlements")
fi

echo "codesign: $app_bundle"
/usr/bin/codesign "${app_sign_args[@]}" "$app_bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_bundle"
