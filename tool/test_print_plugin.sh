#!/usr/bin/env bash
# Build and exercise automatic registration from a fresh, unrelated Flutter app.
# No print dialog opens and nothing is sent to a printer.
set -euo pipefail
print_platform="${1:?Usage: tool/test_print_plugin.sh macos|windows|linux}"
case "$print_platform" in
  macos|windows|linux) ;;
  *) echo "Expected macos, windows or linux" >&2; exit 2 ;;
esac
print_repo_root="$(cd "$(dirname "$0")/.." && pwd)"
print_host_dir="$(mktemp -d "${TMPDIR:-/tmp}/dart-pdf-print-host.XXXXXX")"
print_flutter="${DART_PDF_FLUTTER_BIN:-flutter}"
trap 'rm -rf "$print_host_dir"' EXIT

"$print_flutter" create --empty --project-name print_plugin_host \
  --org dev.milanko --platforms "$print_platform" --no-pub "$print_host_dir"
python3 - "$print_repo_root" "$print_host_dir" <<'PY'
from pathlib import Path
import json
import shutil
import sys
root, host = map(Path, sys.argv[1:])
plugin = root / 'packages/dart_pdf_printing'
text = '''name: print_plugin_host
publish_to: none
environment:
  sdk: ^3.5.0
dependencies:
  flutter:
    sdk: flutter
  dart_pdf_editor: ^4.3.0
  pdf_cos: ^4.3.0
  pdf_document: ^4.3.0
  dart_pdf_printing:
    path: ''' + json.dumps(str(plugin)) + '''
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
dependency_overrides:
'''
for package in ['dart_pdf_editor', 'pdf_cos', 'pdf_document', 'pdf_graphics']:
    text += f'  {package}:\n    path: {json.dumps(str(root / "packages" / package))}\n'
text += 'flutter:\n  uses-material-design: true\n'
(host / 'pubspec.yaml').write_text(text)
shutil.copyfile(plugin / 'example/main.dart', host / 'lib/main.dart')
shutil.copytree(plugin / 'example/integration_test', host / 'integration_test')
for file in (host / 'macos/Runner').glob('*.entitlements'):
    file.write_text(file.read_text().replace(
        '</dict>', '<key>com.apple.security.print</key>\n<true/>\n</dict>'))
PY
cd "$print_host_dir"
"$print_flutter" test integration_test/native_registration_test.dart -d "$print_platform"
