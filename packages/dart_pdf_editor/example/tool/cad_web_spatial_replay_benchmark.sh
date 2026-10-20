#!/usr/bin/env bash
# Release Chrome A/B for #243. Keeps the local CAD corpus out of git.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT=../../..
PDF="$ROOT/corpus/ly9-far-cad.pdf"
PORT=${CAD_PERF_PORT:-8770}
[[ -f "$PDF" ]] || { echo "missing $PDF" >&2; exit 1; }

if [[ "${CAD_PERF_SKIP_WORKER_BUILD:-0}" != "1" ]]; then
  fvm dart run dart_pdf_editor:build_web_worker \
    --out ../../dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js
fi

python3 - "$ROOT/corpus" "$PORT" <<'PY' &
import http.server, os, socketserver, sys, urllib.parse
root, port = sys.argv[1], int(sys.argv[2])
os.chdir(root)
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == '/__cad_web_spatial_replay_benchmark__':
            result = urllib.parse.parse_qs(parsed.query).get('result', [''])[0]
            print('\nCAD_WEB_SPATIAL_REPLAY_BENCHMARK_' + result, flush=True)
            self.send_response(204); self.end_headers(); return
        super().do_GET()
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()
with socketserver.TCPServer(('127.0.0.1', port), Handler) as server:
    server.serve_forever()
PY
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

fvm flutter run -d chrome --release -t lib/web_spatial_replay_benchmark.dart \
  --dart-define="CAD_PERF_URL=http://127.0.0.1:$PORT/ly9-far-cad.pdf" \
  --dart-define="CAD_PERF_PAGE=${CAD_PERF_PAGE:-20}" \
  --dart-define="CAD_PERF_RATIO=${CAD_PERF_RATIO:-3.4}" \
  --dart-define="CAD_PERF_SAMPLES=${CAD_PERF_SAMPLES:-5}" \
  --dart-define="CAD_PERF_MIN_SPEEDUP=${CAD_PERF_MIN_SPEEDUP:-1.15}" \
  --dart-define="CAD_PERF_MAX_COMMAND_FRACTION=${CAD_PERF_MAX_COMMAND_FRACTION:-0.70}"
