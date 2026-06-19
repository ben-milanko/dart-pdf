#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

flutter_version="$(
  sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc |
    head -n 1
)"

if [ -z "$flutter_version" ]; then
  echo "Could not read the Flutter version from .fvmrc" >&2
  exit 1
fi

default_flutter_home="$HOME/.cache/dart-pdf/flutter-$flutter_version"
flutter_home="${FLUTTER_HOME:-$default_flutter_home}"
bin_dir="$HOME/bin"

run_with_sudo() {
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

install_linux_packages() {
  if [ "${CODEX_SKIP_APT:-0}" = "1" ] || ! command -v apt-get >/dev/null 2>&1; then
    return
  fi

  export DEBIAN_FRONTEND=noninteractive
  run_with_sudo apt-get update
  run_with_sudo apt-get install -y --no-install-recommends \
    ca-certificates \
    clang \
    cmake \
    curl \
    git \
    libglu1-mesa \
    libgtk-3-dev \
    liblzma-dev \
    ninja-build \
    pkg-config \
    unzip \
    xz-utils \
    zip
}

install_flutter() {
  if [ -x "$flutter_home/bin/flutter" ]; then
    return
  fi

  if [ -e "$flutter_home" ] && [ "$flutter_home" != "$default_flutter_home" ]; then
    echo "FLUTTER_HOME exists but does not contain bin/flutter: $flutter_home" >&2
    exit 1
  fi

  rm -rf "$default_flutter_home"
  mkdir -p "$(dirname "$flutter_home")"
  git clone --depth 1 --branch "$flutter_version" \
    https://github.com/flutter/flutter.git "$flutter_home"
}

install_legacy_fvm_layout() {
  local legacy_version_home="$HOME/fvm/versions/$flutter_version"

  if [ "$legacy_version_home" = "$flutter_home" ]; then
    return
  fi

  if [ -e "$legacy_version_home" ] && [ ! -x "$legacy_version_home/bin/flutter" ]; then
    echo "Legacy FVM path exists but does not contain bin/flutter: $legacy_version_home" >&2
    exit 1
  fi

  if [ ! -e "$legacy_version_home" ]; then
    mkdir -p "$(dirname "$legacy_version_home")"
    ln -s "$flutter_home" "$legacy_version_home"
  fi
}

persist_agent_environment() {
  mkdir -p "$bin_dir"

  local bashrc="$HOME/.bashrc"
  local marker_start="# >>> dart-pdf Codex environment >>>"
  local marker_end="# <<< dart-pdf Codex environment <<<"
  local block
  block="$(
    cat <<EOF
$marker_start
export FLUTTER_HOME="$flutter_home"
export PATH="\$FLUTTER_HOME/bin:\$HOME/.pub-cache/bin:\$HOME/bin:\$PATH"
$marker_end
EOF
  )"

  touch "$bashrc"
  local tmp_bashrc
  tmp_bashrc="$(mktemp "${bashrc}.XXXXXX")"
  awk -v start="$marker_start" -v end="$marker_end" '
    $0 == start { skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$bashrc" >"$tmp_bashrc"
  printf '\n%s\n' "$block" >>"$tmp_bashrc"
  mv "$tmp_bashrc" "$bashrc"

  export FLUTTER_HOME="$flutter_home"
  export PATH="$FLUTTER_HOME/bin:$HOME/.pub-cache/bin:$HOME/bin:$PATH"
}

write_fvm_shim() {
  local target="$1"
  local existing_fvm=""
  if [ -e "$target" ] && ! grep -q "dart-pdf Codex FVM shim" "$target" 2>/dev/null; then
    existing_fvm="$target"
  fi

  if [ -n "$existing_fvm" ]; then
    echo "Using existing fvm at $existing_fvm"
    return
  fi

  mkdir -p "$(dirname "$target")"
  cat >"$target" <<EOF
#!/usr/bin/env bash
# dart-pdf Codex FVM shim
set -Eeuo pipefail

flutter_home="\${FLUTTER_HOME:-$flutter_home}"
cmd="\${1:-}"

case "\$cmd" in
  flutter)
    shift
    exec "\$flutter_home/bin/flutter" "\$@"
    ;;
  dart)
    shift
    exec "\$flutter_home/bin/dart" "\$@"
    ;;
  install|use)
    exit 0
    ;;
  *)
    exec "\$flutter_home/bin/flutter" "\$@"
    ;;
esac
EOF
  chmod +x "$target"
}

install_fvm_shim() {
  mkdir -p "$bin_dir"

  local existing_fvm=""
  existing_fvm="$(command -v fvm 2>/dev/null || true)"
  if [ -n "$existing_fvm" ] && ! grep -q "dart-pdf Codex FVM shim" "$existing_fvm" 2>/dev/null; then
    echo "Using existing fvm at $existing_fvm"
    return
  fi

  write_fvm_shim "$bin_dir/fvm"

  # Codex cloud command shells do not always reload ~/.bashrc before the agent
  # phase. Put the compatibility shim on the default system PATH when possible.
  if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
    write_fvm_shim /usr/local/bin/fvm
  elif command -v sudo >/dev/null 2>&1; then
    run_with_sudo mkdir -p /usr/local/bin
    if run_with_sudo test -w /usr/local/bin; then
      local tmp_shim
      tmp_shim="$(mktemp)"
      rm -f "$tmp_shim"
      write_fvm_shim "$tmp_shim"
      run_with_sudo mv "$tmp_shim" /usr/local/bin/fvm
      run_with_sudo chmod +x /usr/local/bin/fvm
    fi
  fi
}

prepare_flutter() {
  flutter config --no-analytics --enable-web >/dev/null
  dart --disable-analytics >/dev/null

  # Cloud setup is the networked phase. Fetch the artifacts agents commonly
  # need later when internet access is normally disabled.
  flutter precache --web --linux
}

install_workspace_dependencies() {
  flutter pub get
}

install_linux_packages
install_flutter
install_legacy_fvm_layout
persist_agent_environment
install_fvm_shim
prepare_flutter
install_workspace_dependencies

flutter --version
dart --version
