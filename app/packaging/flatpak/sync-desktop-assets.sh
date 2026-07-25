#!/usr/bin/env bash
# Regenerate desktop-assets/ from the authoritative sources in app/linux/.
#
# app/linux/ is the single source of truth for the .desktop entry, the
# AppStream metainfo, and the hicolor icons (one copy, shared by the raw
# bundle, the release tarball, and packaging). The Flatpak manifest installs
# them from copies staged here because those copies get committed into the
# flathub/flathub PR alongside the manifest. Run this whenever app/linux/
# changes so the staged copies do not drift.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
linux="$here/../../linux"
out="$here/desktop-assets"

install -d "$out" "$out/icons"
cp "$linux/dev.milanko.dartpdf.desktop"      "$out/"
cp "$linux/dev.milanko.dartpdf.metainfo.xml" "$out/"
for sz in 64 128 256 512; do
  cp "$linux/icons/hicolor/${sz}x${sz}/apps/dev.milanko.dartpdf.png" "$out/icons/dartpdf-${sz}.png"
done

echo "Synced desktop-assets/ from app/linux/:"
find "$out" -type f | sort | sed "s#$here/#  #"
