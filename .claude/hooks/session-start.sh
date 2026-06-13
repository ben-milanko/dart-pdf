#!/usr/bin/env bash
# SessionStart hook for Claude Code on the web.
#
# Provisions the Flutter/Dart toolchain so `dart analyze`, `dart test`,
# `flutter test` — and the repo's `fvm flutter` / `fvm dart` commands —
# work in a fresh web session.
#
# The repo pins Flutter via .fvmrc. fvm's own installer (fvm.app) is
# blocked outbound in the web sandbox, but Google's Flutter release
# storage and github.com are reachable, so we fetch the pinned SDK
# archive directly and expose a tiny `fvm` shim that forwards to it
# (matching the commands documented in CLAUDE.md).
set -euo pipefail

# Local machines already have the developer's own toolchain — only
# provision inside the remote (web) environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

log() { echo "[session-start] $*" >&2; }

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Flutter version pinned in .fvmrc (fall back to a known-good default).
FLUTTER_VERSION="$(
  grep -o '"flutter"[[:space:]]*:[[:space:]]*"[^"]*"' "$PROJECT_DIR/.fvmrc" 2>/dev/null \
    | grep -o '[0-9][0-9.]*' | head -n1 || true
)"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.2}"

SDK_DIR="$HOME/fvm/versions/$FLUTTER_VERSION"
DART_BIN="$SDK_DIR/bin/cache/dart-sdk/bin"
SHIM_DIR="$HOME/.local/bin"

# 1. Install the SDK (idempotent: skip if it is already extracted).
if [ ! -x "$SDK_DIR/bin/flutter" ]; then
  log "Installing Flutter $FLUTTER_VERSION …"
  archive="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  tmp="$(mktemp -d)"
  curl -fSL --retry 3 "$archive" -o "$tmp/flutter.tar.xz"
  rm -rf "$SDK_DIR"
  mkdir -p "$SDK_DIR"
  # archive's top-level dir is "flutter"; strip it into the version dir
  tar -xJf "$tmp/flutter.tar.xz" -C "$SDK_DIR" --strip-components=1
  rm -rf "$tmp"
else
  log "Flutter $FLUTTER_VERSION already installed."
fi

# git otherwise flags the SDK checkout as dubious ownership.
git config --global --add safe.directory "$SDK_DIR" 2>/dev/null || true

export PATH="$SDK_DIR/bin:$DART_BIN:$SHIM_DIR:$PATH"

# 2. `fvm` shim so the repo's `fvm flutter` / `fvm dart` commands resolve
#    to the provisioned SDK (the real fvm needs the blocked fvm.app
#    installer; only `flutter`/`dart` forwarding is needed here).
mkdir -p "$SHIM_DIR"
cat > "$SHIM_DIR/fvm" <<SHIM
#!/usr/bin/env bash
# Minimal fvm shim — forwards to the SDK provisioned by the session hook.
set -euo pipefail
SDK="$SDK_DIR"
case "\${1:-}" in
  flutter) shift; exec "\$SDK/bin/flutter" "\$@" ;;
  dart)    shift; exec "\$SDK/bin/dart" "\$@" ;;
  install|use) exit 0 ;;
  list)    echo "$FLUTTER_VERSION"; exit 0 ;;
  --version|version) echo "fvm shim → Flutter $FLUTTER_VERSION (\$SDK)"; exit 0 ;;
  *)       exec "\$SDK/bin/flutter" "\$@" ;;
esac
SHIM
chmod +x "$SHIM_DIR/fvm"

# 3. Materialise the bundled Dart SDK / tool artifacts (first-run fetch).
log "Priming Flutter (first-run artifacts) …"
flutter --version >&2

# 4. Persist the toolchain on PATH for the rest of the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$SDK_DIR/bin:$DART_BIN:$SHIM_DIR:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# 5. Resolve workspace dependencies so analyze/test are ready to run.
log "Resolving workspace dependencies (flutter pub get) …"
( cd "$PROJECT_DIR" && flutter pub get >&2 )

log "Ready: Flutter $FLUTTER_VERSION • $(dart --version 2>&1)"
