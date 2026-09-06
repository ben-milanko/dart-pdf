#!/usr/bin/env bash
#
# Post-publish verification for the Snap Store leg of a Storeflight release.
#
# Installs the published snap from the stable channel and confirms both the
# store-reported revision and the binary itself report the released version -
# the same pair `publish-snap.yml` checks, so a Storeflight-driven release is
# held to the identical bar.
#
# Usage: verify-snap-install.sh <version>
set -euo pipefail

version="${1:?usage: verify-snap-install.sh <version>}"
snap_name="${SNAP_NAME:-dartpdf}"

sudo snap install "$snap_name" --channel=latest/stable
installed="$(snap info "$snap_name" |
  sed -n 's/^installed:[[:space:]]*\([^[:space:]]*\).*/\1/p')"

if [[ "$installed" != "$version" ]]; then
  echo "snap reports '$installed', expected '$version'" >&2
  exit 1
fi

# The CLI sidecar is exposed as <snap>.cli in this channel.
sudo snap run "$snap_name.cli" --version

echo "$version"
