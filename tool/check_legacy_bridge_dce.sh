#!/usr/bin/env bash
# Proves the legacy-host bridge's size contract
# (packages/dart_pdf_editor/lib/src/legacy/legacy_host_bridge.dart):
#
#   1. --dart-define=PDF_LEGACY_MATERIAL_BRIDGE=false compiles the bridge out
#      completely: a material_ui-hosted probe's main.dart.js is byte-identical
#      to the same probe built against an editor whose bridge is a stub with
#      no legacy imports at all.
#   2. Under a legacy (package:flutter/material.dart) MaterialApp host the
#      bridge is present by default - its marker string is in main.dart.js,
#      which also proves the grep is live - and gone with the define off.
#
# The marker is the bridge's Expando name ('pdfLegacyHostTheme'), a runtime
# string dart2js keeps verbatim while the bridge's theme mapping is live.
#
# The probes are web builds of a tiny app (dart:ui rules out plain
# `dart compile js`), made outside the workspace like tool/floor_analyze.sh:
# the editor and the pure-Dart packages it needs are copied to a temp dir
# with path dependencies. It also prints what the bridge costs a legacy host.
#
# Usage: tool/check_legacy_bridge_dce.sh            (uses fvm, else flutter)
#        FLUTTER=/path/to/flutter tool/check_legacy_bridge_dce.sh
set -euo pipefail

cd "$(dirname "$0")/.."
root=$(pwd)

if [ -z "${FLUTTER:-}" ]; then
  if command -v fvm >/dev/null 2>&1; then
    # the repo's pinned SDK (.fvmrc); fvm would pick its global one in the
    # temp dirs below
    sdk=$(fvm flutter --version --machine 2>/dev/null |
      sed -n 's/.*"flutterRoot": *"\([^"]*\)".*/\1/p')
    FLUTTER="$sdk/bin/flutter"
  else
    FLUTTER=flutter
  fi
fi

MARKER='pdfLegacyHostTheme'
DEFINE='PDF_LEGACY_MATERIAL_BRIDGE'
tmp=$(mktemp -d "${TMPDIR:-/tmp}/legacy_bridge_dce.XXXXXX")
# KEEP=1 leaves the probes and their main.dart.js files for inspection
if [ -z "${KEEP:-}" ]; then trap 'rm -rf "$tmp"' EXIT; else echo "keeping $tmp"; fi

# ---- copies of the packages, with path dependencies --------------------------
copy_packages() { # <dest>
  local dest=$1
  for pkg in pdf_cos pdf_document pdf_graphics dart_pdf_editor; do
    local src="$root/packages/$pkg" dst="$dest/$pkg"
    mkdir -p "$dst"
    cp -R "$src/lib" "$dst/"
    cp "$src/pubspec.yaml" "$dst/"
    for extra in shaders; do
      if [ -e "$src/$extra" ]; then cp -R "$src/$extra" "$dst/"; fi
    done
    perl -0pi -e '
      s/^resolution:\s*workspace\s*\n//m;
      s/^dev_dependencies:.*?(?=^\S)//ms;
      s/^(\s+)(pdf_cos|pdf_document|pdf_graphics):\s*\S.*$/$1$2: {path: ..\/$2}/mg;
      s/^(\s+)generate:\s*true\s*$//mg;
    ' "$dst/pubspec.yaml"
  done
}

copy_packages "$tmp/with"
copy_packages "$tmp/without"
# the "no bridge" editor: same API, no legacy imports, nothing to strip
cat >"$tmp/without/dart_pdf_editor/lib/src/legacy/legacy_host_bridge.dart" <<'EOF'
import 'package:material_ui/material_ui.dart';

const bool kPdfLegacyMaterialBridge =
    bool.fromEnvironment('PDF_LEGACY_MATERIAL_BRIDGE', defaultValue: true);

ThemeData? pdfLegacyHostTheme(BuildContext context) => null;

IconThemeData pdfLegacyHostIconTheme(IconThemeData data) => data;

({Color primary, Color onPrimary, Brightness? brightness})?
    pdfLegacyCupertinoHost(BuildContext context) => null;

bool pdfLegacyHostNotice(
  BuildContext context, {
  Key? key,
  required String message,
  required bool floating,
  EdgeInsetsGeometry? margin,
  required Duration duration,
  required bool showClose,
  required bool replaceCurrent,
  String? undoLabel,
  VoidCallback? onUndo,
}) =>
    false;
EOF

# ---- the probe app ------------------------------------------------------------
make_probe() { # <packages dir>
  local dir="$1/probe"
  mkdir -p "$dir/lib" "$dir/web"
  cat >"$dir/pubspec.yaml" <<'EOF'
name: legacy_bridge_dce_probe
publish_to: none
environment:
  sdk: ^3.5.0
dependencies:
  flutter:
    sdk: flutter
  material_ui: ^1.4.0
  dart_pdf_editor: {path: ../dart_pdf_editor}
EOF
  cat >"$dir/web/index.html" <<'EOF'
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><base href="$FLUTTER_BASE_HREF"></head>
<body><script src="flutter_bootstrap.js" async></script></body></html>
EOF
  # the editor's wrapper (theme/localizations/surface) and a notice: the two
  # ways in to the bridge
  local body='PdfMaterialHost(
          child: Builder(
            builder: (context) => GestureDetector(
              onTap: () => PdfEditorPresenter.of(context)
                  .notice(context, const PdfEditorNotice("hi")),
              child: const Text("probe"),
            ),
          ),
        )'
  cat >"$dir/lib/modern.dart" <<EOF
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:material_ui/material_ui.dart';

void main() => runApp(MaterialApp(home: Scaffold(body: $body)));
EOF
  cat >"$dir/lib/legacy.dart" <<EOF
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter/material.dart' as legacy;
import 'package:flutter/widgets.dart';

void main() =>
    runApp(legacy.MaterialApp(home: legacy.Scaffold(body: $body)));
EOF
  (cd "$dir" && $FLUTTER pub get >/dev/null)
}

make_probe "$tmp/with"
make_probe "$tmp/without"

build() { # <packages dir> <target> <out.js> [define]
  local dir="$1/probe" target=$2 out=$3 define=${4:-}
  local args=(build web --release --no-tree-shake-icons --no-source-maps
    --no-web-resources-cdn --no-wasm-dry-run -t "lib/$target.dart")
  if [ -n "$define" ]; then args+=("--dart-define=$define"); fi
  echo "building $target ${define:-(default defines)} ..."
  (cd "$dir" && $FLUTTER "${args[@]}" >/dev/null)
  cp "$dir/build/web/main.dart.js" "$out"
}

build "$tmp/with" modern "$tmp/modern_off.js" "$DEFINE=false"
build "$tmp/without" modern "$tmp/modern_nobridge.js" "$DEFINE=false"
if [ -n "${ONLY_IDENTITY:-}" ]; then
  cmp "$tmp/modern_off.js" "$tmp/modern_nobridge.js"; exit $?
fi
build "$tmp/with" legacy "$tmp/legacy_on.js"
build "$tmp/with" legacy "$tmp/legacy_off.js" "$DEFINE=false"
build "$tmp/with" modern "$tmp/modern_on.js"

size() { wc -c <"$1" | tr -d ' '; }
status=0

if cmp -s "$tmp/modern_off.js" "$tmp/modern_nobridge.js"; then
  echo "ok: $DEFINE=false is byte-identical to an editor without the bridge"
else
  echo "FAIL: $DEFINE=false leaves bridge code behind: main.dart.js is" \
    "$(size "$tmp/modern_off.js") bytes vs $(size "$tmp/modern_nobridge.js")" \
    "without the bridge. Check that every entry point tests" \
    "kPdfLegacyMaterialBridge FIRST." >&2
  status=1
fi

if grep -q "$MARKER" "$tmp/legacy_on.js"; then
  echo "ok: the bridge is present under a legacy MaterialApp host (grep is live)"
else
  echo "FAIL: '$MARKER' missing from the legacy-host build - the bridge is" \
    "not reached, or the marker changed, so the checks above prove nothing." >&2
  status=1
fi

if grep -q "$MARKER" "$tmp/legacy_off.js"; then
  echo "FAIL: '$MARKER' survived $DEFINE=false under a legacy host." >&2
  status=1
else
  echo "ok: $DEFINE=false strips the bridge under a legacy host too"
fi

echo "cost under a legacy host: $(($(size "$tmp/legacy_on.js") - $(size "$tmp/legacy_off.js"))) bytes of main.dart.js"
echo "material_ui host, define on vs off: $(($(size "$tmp/modern_on.js") - $(size "$tmp/modern_off.js"))) bytes" \
  "(marker $(grep -q "$MARKER" "$tmp/modern_on.js" && echo present || echo absent))"

if [ $status -eq 0 ]; then
  echo "PASS: the legacy-host bridge compiles out with $DEFINE=false"
fi
exit $status
