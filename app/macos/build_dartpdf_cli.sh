#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${FLUTTER_ROOT:-}" || -z "${TARGET_BUILD_DIR:-}" ||
      -z "${WRAPPER_NAME:-}" ]]; then
  echo "error: build_dartpdf_cli.sh must run from the macOS Runner target" >&2
  exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../.." && pwd)"
dart="$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart"
# APFS is normally case-insensitive, so `dartpdf` would collide with the GUI's
# `DartPDF` executable. macOS uses an explicit `dartpdf-cli` sidecar name.
output="$TARGET_BUILD_DIR/$WRAPPER_NAME/Contents/MacOS/dartpdf-cli"

# `dart compile exe` embeds the standalone Dart runtime, whose bundled
# libunwind imports Apple's private __dyld_find_unwind_sections SPI. App Store
# validation rejects that import under guideline 2.5.1. Do not post-process the
# runtime or disable its unwind lookup: archive actions omit this optional
# CLI/MCP sidecar instead. Ordinary builds (including the CI DMG build) retain
# the sidecar.
if [[ "${ACTION:-}" == "install" ]]; then
  rm -f "$output"
  echo "Skipping dartpdf-cli in the App Store archive (private Dart runtime SPI)."
  exit 0
fi

# A Dart SDK compiles macOS executables for its native CPU. Local universal
# Flutter builds therefore carry a host-native sidecar. Release CI builds a
# second slice on the other native GitHub runner and replaces this file with a
# universal lipo merge before signing the app.
case "$(uname -m)" in
  arm64|aarch64) target_arch=arm64 ;;
  x86_64|amd64) target_arch=x64 ;;
  *)
    echo "error: unsupported DartPDF CLI host architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

"$dart" "$repository_root/tool/build_desktop_cli.dart" \
  --output "$output" \
  --target-os macos \
  --target-arch "$target_arch"
