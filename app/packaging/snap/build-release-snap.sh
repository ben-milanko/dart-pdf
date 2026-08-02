#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-release-snap.sh \
  --archive <dartpdf-linux-x64.tar.gz> \
  --output <directory>

Builds the DartPDF snap from an already digest-verified Linux release archive.
The archive's AppStream metadata supplies the application version and listing
metadata, so it must come from the matching published app release.
EOF
}

archive=''
output=''

while (($#)); do
  case "$1" in
    --archive) archive="${2:?missing --archive value}"; shift 2 ;;
    --output) output="${2:?missing --output value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$archive" || ! -f "$archive" ]]; then
  echo "Linux release archive not found: $archive" >&2
  exit 2
fi
if [[ -z "$output" ]]; then
  echo "Missing required argument: output" >&2
  exit 2
fi
command -v snapcraft >/dev/null || {
  echo "Required command not found: snapcraft" >&2
  exit 2
}

snapcraft_command=(snapcraft)
if ((EUID != 0)); then
  command -v sudo >/dev/null || {
    echo "Snapcraft destructive builds need root (sudo was not found)" >&2
    exit 2
  }
  snapcraft_command=(sudo snapcraft)
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(mktemp -d)"
cleanup() {
  if ((EUID == 0)); then
    rm -rf -- "$work_dir"
  else
    sudo rm -rf -- "$work_dir"
  fi
}
trap cleanup EXIT

mkdir -p "$work_dir/snap" "$output"
cp "$script_dir/snap/snapcraft.yaml" "$work_dir/snap/snapcraft.yaml"
cp "$archive" "$work_dir/dartpdf-linux-x64.tar.gz"

# The checked-in recipe stays reproducible from the pinned GitHub release.
# Release CI has already downloaded and verified the asset, so use that exact
# local file without depending on a second network fetch during the build.
python3 - "$work_dir/snap/snapcraft.yaml" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
text, count = re.subn(
    r'(?m)^    source: https://github\.com/[^\n]+\n'
    r'    source-type: tar\n'
    r'    source-checksum: sha256/[0-9a-f]{64}\n',
    '    source: dartpdf-linux-x64.tar.gz\n'
    '    source-type: tar\n',
    text,
    count=1,
)
if count != 1:
    raise SystemExit('could not replace the pinned release source')
path.write_text(text)
PY

(
  cd "$work_dir"
  "${snapcraft_command[@]}" pack \
    --destructive-mode \
    --output "$(cd "$output" && pwd)"
)

snap_file="$(find "$output" -maxdepth 1 -type f -name 'dartpdf_*.snap' -print -quit)"
if [[ -z "$snap_file" ]]; then
  echo "Snapcraft did not create a DartPDF snap in $output" >&2
  exit 1
fi

echo "Built $snap_file"
