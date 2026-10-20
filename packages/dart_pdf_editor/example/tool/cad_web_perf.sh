#!/usr/bin/env bash
# Self-driven web perf harness for the heavy CAD sheet.
# Builds the example web app so it auto-opens corpus/ly9-far-cad.pdf, stages the
# PDF same-origin (no CORS), and serves build/web on :8753. Then drive Chrome to
# http://127.0.0.1:8753/?perf=1 and read the [perf ...] console logs.
#
#   bash tool/cad_web_perf.sh            # build + stage + serve (foreground)
#   bash tool/cad_web_perf.sh --serve    # skip rebuild, just (re)serve
set -euo pipefail
cd "$(dirname "$0")/.."                       # packages/dart_pdf_editor/example
ROOT=../../..
PDF="$ROOT/corpus/ly9-far-cad.pdf"
PORT=8753

if [[ "${1:-}" != "--serve" ]]; then
  [[ -f "$PDF" ]] || { echo "missing $PDF" >&2; exit 1; }
  fvm dart run dart_pdf_editor:build_web_worker \
    --out ../../dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js
  fvm flutter build web --release --dart-define=PDF=cad.pdf
  cp "$PDF" build/web/cad.pdf
fi
echo "serving http://127.0.0.1:$PORT/?perf=1  (Ctrl-C to stop)"
exec python3 -m http.server "$PORT" --bind 127.0.0.1 --directory build/web
