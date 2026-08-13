#!/usr/bin/env bash
# Repeatable browser-worker A/B for #240. The CAD corpus remains local.
#
#   cd packages/dart_pdf_editor/example
#   bash tool/cad_web_detail_benchmark.sh
#
# Optional environment knobs:
#   CAD_PERF_PAGE=4 CAD_PERF_RATIO=3.4 CAD_PERF_SAMPLES=5
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT=../../..
PDF="$ROOT/corpus/ly9-far-cad.pdf"
PORT=${CAD_PERF_PORT:-8754}
PAGE=${CAD_PERF_PAGE:-4}
RATIO=${CAD_PERF_RATIO:-3.4}
SAMPLES=${CAD_PERF_SAMPLES:-5}
MIN_SPEEDUP=${CAD_PERF_MIN_SPEEDUP:-1.10}

[[ -f "$PDF" ]] || { echo "missing $PDF" >&2; exit 1; }

if [[ "${CAD_PERF_SKIP_WORKER_BUILD:-0}" != "1" ]]; then
  fvm dart run dart_pdf_editor:build_web_worker \
    --out ../../dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js
fi

# Flutter's app server owns a different origin, so expose the local corpus with
# a narrowly-scoped permissive CORS header for the duration of this run. The
# benchmark reports its release-mode result back to this server as a GET, which
# keeps the measurement visible in the terminal even when release Chrome does
# not forward console output to `flutter run`.
python3 - "$ROOT/corpus" "$PORT" <<'PY' &
import http.server
import os
import socketserver
import sys
import urllib.parse

root, port = sys.argv[1], int(sys.argv[2])
os.chdir(root)

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == '/__cad_web_detail_benchmark__':
            result = urllib.parse.parse_qs(parsed.query).get('result', [''])[0]
            print('\nCAD_WEB_DETAIL_BENCHMARK_' + result, flush=True)
            self.send_response(204)
            self.end_headers()
            return
        super().do_GET()

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

with socketserver.TCPServer(('127.0.0.1', port), Handler) as server:
    server.serve_forever()
PY
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

fvm flutter run -d chrome --release \
  -t lib/web_region_detail_benchmark.dart \
  --dart-define="CAD_PERF_URL=http://127.0.0.1:$PORT/ly9-far-cad.pdf" \
  --dart-define="CAD_PERF_PAGE=$PAGE" \
  --dart-define="CAD_PERF_RATIO=$RATIO" \
  --dart-define="CAD_PERF_SAMPLES=$SAMPLES" \
  --dart-define="CAD_PERF_MIN_SPEEDUP=$MIN_SPEEDUP"
