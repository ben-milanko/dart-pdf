#!/usr/bin/env bash
set -euo pipefail

# Ubuntu 22.04's AppStream 0.15 does not recognize modern developer or vcs-browser
# metadata. Keep the standard metadata and validate it with a schema-aware CLI.
# This tool lives in a disposable directory, never in the application bundle.
# Required distro development packages are installed by the calling workflow.
appstream_source=f3ccabfa4d9582b7b0baa90d79899eb93b28b10c # signed v1.0.6
libxmlb_source=d942cd68a7d78e35b312b9299e69f68f9cd2e503 # 0.3.29
validator_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/dartpdf-appstream.XXXXXX")"

python3 -m venv "$validator_dir/venv"
"$validator_dir/venv/bin/python" -m pip install --no-cache-dir meson==1.4.2

git init "$validator_dir/source"
git -C "$validator_dir/source" remote add origin https://github.com/ximion/appstream.git
git -C "$validator_dir/source" fetch --depth 1 origin "$appstream_source"
git -C "$validator_dir/source" checkout --detach FETCH_HEAD
test "$(git -C "$validator_dir/source" rev-parse HEAD)" = "$appstream_source"

# The vendor wrap points to a moving main branch. Supply an immutable dependency
# checkout and prohibit Meson from downloading any other fallback source.
git init "$validator_dir/source/subprojects/libxmlb"
git -C "$validator_dir/source/subprojects/libxmlb" remote add origin https://github.com/hughsie/libxmlb.git
git -C "$validator_dir/source/subprojects/libxmlb" fetch --depth 1 origin "$libxmlb_source"
git -C "$validator_dir/source/subprojects/libxmlb" checkout --detach FETCH_HEAD
test "$(git -C "$validator_dir/source/subprojects/libxmlb" rev-parse HEAD)" = "$libxmlb_source"

"$validator_dir/venv/bin/meson" setup "$validator_dir/build" "$validator_dir/source" \
  --prefix "$validator_dir/install" --libdir lib --buildtype release \
  --wrap-mode nodownload --force-fallback-for=libxmlb \
  -Dgir=false -Dapidocs=false -Dinstall-docs=false
"$validator_dir/venv/bin/meson" compile -C "$validator_dir/build"
"$validator_dir/venv/bin/meson" install -C "$validator_dir/build"

# Scope the validator's libraries to this one command. Do not export a global
# LD_LIBRARY_PATH that could influence the app's native smoke tests or payload.
mkdir "$validator_dir/launcher"
cat > "$validator_dir/launcher/appstreamcli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
prefix="$(cd "$(dirname "$0")/../install" && pwd)"
LD_LIBRARY_PATH="$prefix/lib:${LD_LIBRARY_PATH:-}" exec "$prefix/bin/appstreamcli" "$@"
EOF
chmod +x "$validator_dir/launcher/appstreamcli"
"$validator_dir/launcher/appstreamcli" --version | grep -F '1.0.6'
if [[ -n "${GITHUB_PATH:-}" ]]; then
  printf '%s\n' "$validator_dir/launcher" >> "$GITHUB_PATH"
fi
echo "Schema-aware AppStream validator: $validator_dir/launcher/appstreamcli"
