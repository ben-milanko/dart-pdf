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
macos_dir="$app_bundle/Contents/MacOS"
identity="${CODESIGN_IDENTITY:-${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}}"
if [[ -z "$identity" ]]; then
  identity="-"
fi

entitlements="${CODESIGN_ENTITLEMENTS:-}"
if [[ -z "$entitlements" ]]; then
  if [[ "$identity" == "-" && -f "$script_dir/Runner/AdHoc.entitlements" ]]; then
    # keychain-access-groups is restricted to provisioned Apple identities.
    # Embedding it in an ad-hoc signature passes `codesign --verify`, but AMFI
    # rejects the process at launch with security-policy error 163.
    entitlements="$script_dir/Runner/AdHoc.entitlements"
  elif [[ -f "$script_dir/Runner/Release.entitlements" ]]; then
    entitlements="$script_dir/Runner/Release.entitlements"
  fi
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

if [[ -d "$macos_dir" ]]; then
  while IFS= read -r -d '' file; do
    # `dartpdf-cli` is the compiled CLI/MCP sidecar. Sign it as nested code
    # before signing the outer app, like dylibs copied into this directory.
    if [[ "$file" == *.dylib || "$(basename "$file")" == dartpdf-cli ]] &&
        /usr/bin/file -b "$file" | grep -q 'Mach-O'; then
      sign_code "$file"
    fi
  done < <(find "$macos_dir" -maxdepth 1 -type f -print0)
fi

app_sign_args=(--force --options runtime --sign "$identity")
if [[ -n "$entitlements" ]]; then
  app_sign_args+=(--entitlements "$entitlements")
fi

echo "codesign: $app_bundle"
/usr/bin/codesign "${app_sign_args[@]}" "$app_bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_bundle"

if [[ "$identity" == "-" ]] &&
    /usr/bin/codesign -d --entitlements :- "$app_bundle" 2>&1 |
      /usr/bin/grep -q '<key>keychain-access-groups</key>'; then
  echo "error: ad-hoc app contains restricted keychain-access-groups" >&2
  exit 1
fi
