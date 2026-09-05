#!/usr/bin/env bash
#
# Post-publish verification for the Flatpak leg of a Storeflight release.
#
# Installs from the published repository and confirms `flatpak info` reports
# the released version. This reads the *installed* metainfo, so it catches the
# staged-desktop-assets trap: a repo that deployed correctly but still carries
# the previous release's AppStream version.
#
# Usage: verify-flatpak-install.sh <version>
set -euo pipefail

version="${1:?usage: verify-flatpak-install.sh <version>}"
flatpak_id="${FLATPAK_ID:-dev.milanko.dartpdf}"
base_url="${FLATPAK_BASE_URL:-https://dartpdf-flatpak.web.app}"

flatpak remote-add --user --if-not-exists --no-gpg-verify \
  dartpdf-verify "$base_url"
flatpak install --user --assumeyes --noninteractive \
  dartpdf-verify "$flatpak_id"

installed="$(LC_ALL=C flatpak info --user "$flatpak_id" |
  sed -n 's/^[[:space:]]*Version:[[:space:]]*//p')"

if [[ "$installed" != "$version" ]]; then
  echo "flatpak reports '$installed', expected '$version'" >&2
  exit 1
fi

echo "$version"
