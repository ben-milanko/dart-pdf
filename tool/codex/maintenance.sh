#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cached Codex containers already have OS packages and Flutter artifacts from
# setup. Re-run the idempotent setup without apt to refresh PATH, the fvm shim,
# and workspace dependencies for the checked-out branch.
export CODEX_SKIP_APT="${CODEX_SKIP_APT:-1}"
exec "$script_dir/setup.sh"
