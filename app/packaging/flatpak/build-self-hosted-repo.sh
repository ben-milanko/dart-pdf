#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-self-hosted-repo.sh \
  --archive <dartpdf-linux-x64.tar.gz> \
  --output <hosting-public-dir> \
  --version <X.Y.Z> \
  --gpg-homedir <dir> \
  --gpg-key <fingerprint> \
  [--base-url <url>]

Builds and signs the official DartPDF Flatpak repository, then writes the
repository, .flatpakrepo, .flatpakref, public key, and version metadata into
the otherwise-empty output directory.
EOF
}

archive=''
output=''
version=''
gpg_homedir=''
gpg_key=''
base_url='https://dartpdf-flatpak.web.app'

while (($#)); do
  case "$1" in
    --archive) archive="${2:?missing --archive value}"; shift 2 ;;
    --output) output="${2:?missing --output value}"; shift 2 ;;
    --version) version="${2:?missing --version value}"; shift 2 ;;
    --gpg-homedir) gpg_homedir="${2:?missing --gpg-homedir value}"; shift 2 ;;
    --gpg-key) gpg_key="${2:?missing --gpg-key value}"; shift 2 ;;
    --base-url) base_url="${2:?missing --base-url value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for value in archive output version gpg_homedir gpg_key; do
  if [[ -z "${!value}" ]]; then
    echo "Missing required argument: $value" >&2
    usage >&2
    exit 2
  fi
done

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid version: $version" >&2
  exit 2
fi
if [[ ! "$gpg_key" =~ ^[0-9A-Fa-f]{40}$ ]]; then
  echo "--gpg-key must be a full 40-character fingerprint" >&2
  exit 2
fi
if [[ ! -f "$archive" ]]; then
  echo "Linux release archive not found: $archive" >&2
  exit 2
fi
if [[ ! -d "$gpg_homedir" ]]; then
  echo "GPG home not found: $gpg_homedir" >&2
  exit 2
fi

for command in flatpak flatpak-builder gpg python3; do
  command -v "$command" >/dev/null || {
    echo "Required command not found: $command" >&2
    exit 2
  }
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
public_key="$script_dir/dartpdf-flatpak-public-key.gpg"
templates="$repo_root/flatpak-hosting/templates"

if [[ ! -f "$public_key" ]]; then
  echo "Public signing key not found: $public_key" >&2
  exit 2
fi
if [[ ! -d "$templates" ]]; then
  echo "Hosting templates not found: $templates" >&2
  exit 2
fi

mkdir -p "$output"
if find "$output" -mindepth 1 -print -quit | grep -q .; then
  echo "Refusing to write into non-empty output directory: $output" >&2
  exit 2
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
cp "$script_dir/dev.milanko.dartpdf.yml" "$work_dir/dev.milanko.dartpdf.yml"
cp -R "$script_dir/desktop-assets" "$work_dir/desktop-assets"
cp "$archive" "$work_dir/dartpdf-linux-x64.tar.gz"

# The checked-in manifest stays useful for local builds from the current
# GitHub release. CI builds the repository before/independently of that URL,
# so replace only its first archive source with the downloaded release asset.
python3 - "$work_dir/dev.milanko.dartpdf.yml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
source_start = text.index('      - type: archive', text.index('# 1) The prebuilt Linux bundle'))
source_end = text.index('      # 2) Desktop integration files', source_start)
replacement = '''      - type: archive
        path: dartpdf-linux-x64.tar.gz
'''
path.write_text(text[:source_start] + replacement + text[source_end:])
PY

flatpak-builder --user --force-clean \
  --default-branch=stable \
  --repo="$output/repo" \
  --gpg-sign="$gpg_key" \
  --gpg-homedir="$gpg_homedir" \
  "$work_dir/build-dir" "$work_dir/dev.milanko.dartpdf.yml"

# flatpak-builder signs the app commit. Sign the repository summary as well;
# clients verify both before installing or updating.
flatpak build-update-repo \
  --gpg-sign="$gpg_key" \
  --gpg-homedir="$gpg_homedir" \
  "$output/repo"

cp "$public_key" "$output/dartpdf-flatpak-public-key.gpg"
gpg_key_base64="$(base64 < "$public_key" | tr -d '\r\n')"

python3 - "$templates" "$output" "$base_url" "$version" "$gpg_key_base64" <<'PY'
from pathlib import Path
import json
import sys

templates = Path(sys.argv[1])
output = Path(sys.argv[2])
base_url = sys.argv[3].rstrip('/')
version = sys.argv[4]
gpg_key = sys.argv[5]

replacements = {
    '@BASE_URL@': base_url,
    '@VERSION@': version,
    '@GPG_KEY@': gpg_key,
}
for name in ('dartpdf.flatpakrepo', 'dartpdf.flatpakref', 'index.html'):
    text = (templates / f'{name}.in').read_text()
    for old, new in replacements.items():
        text = text.replace(old, new)
    if '@' in text:
        raise SystemExit(f'unexpanded template marker in {name}')
    (output / name).write_text(text)

(output / 'version.json').write_text(json.dumps({
    'appId': 'dev.milanko.dartpdf',
    'version': version,
    'branch': 'stable',
    'architecture': 'x86_64',
}, indent=2) + '\n')
PY

echo "Built signed Flatpak repository for DartPDF $version"
echo "Repository: $output/repo"
echo "Install ref: $output/dartpdf.flatpakref"
