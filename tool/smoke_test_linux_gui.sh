#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: smoke_test_linux_gui.sh --cmd "<command>" [--timeout <seconds>]

Smoke-tests a Linux GUI application launch (Snap, Flatpak, AppImage, or standalone bundle).
Verifies that:
1. The process starts up without GTK-CRITICAL assertions or D-Bus AccessDenied errors.
2. A GTK window titled "DartPDF" or matching class "dev.milanko.dartpdf" is mapped and created.
EOF
}

cmd=""
timeout_secs=15
is_xvfb_child=0

while (($#)); do
  case "$1" in
    --cmd) cmd="${2:?missing --cmd value}"; shift 2 ;;
    --timeout) timeout_secs="${2:?missing --timeout value}"; shift 2 ;;
    --xvfb-child) is_xvfb_child=1; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$cmd" ]]; then
  echo "Missing required argument: --cmd" >&2
  exit 2
fi

# Force isolated Xvfb server execution unless already inside the child wrapper
if (( is_xvfb_child == 0 )); then
  exec env -u DISPLAY xvfb-run -a -s "-screen 0 1280x1024x24" "$0" --cmd "$cmd" --timeout "$timeout_secs" --xvfb-child
fi

log_file="$(mktemp /tmp/dartpdf-gui-smoke-XXXXXX.log)"
cleanup() {
  rm -f "$log_file"
}
trap cleanup EXIT

echo "Starting GUI smoke test on DISPLAY=${DISPLAY:-none}: $cmd"

bash -c "$cmd" >"$log_file" 2>&1 &
app_pid=$!

pass=0
start_time=$(date +%s)

while true; do
  current_time=$(date +%s)
  elapsed=$((current_time - start_time))

  # 1. Check for fatal GTK / GLib / D-Bus error logs
  if grep -qE "Gtk-CRITICAL|GLib-GObject-CRITICAL|AccessDenied|GTK_IS_WIDGET" "$log_file" 2>/dev/null; then
    echo "ERROR: Critical GTK / D-Bus error detected during launch:" >&2
    cat "$log_file" >&2
    kill -9 "$app_pid" 2>/dev/null || true
    exit 1
  fi

  # 2. Check for X11 window creation on isolated DISPLAY
  if command -v xwininfo >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    if xwininfo -display "$DISPLAY" -root -tree 2>/dev/null | grep -iE "DartPDF|dev\.milanko\.dartpdf" >/dev/null 2>&1; then
      echo "SUCCESS: GTK window detected after ${elapsed}s."
      pass=1
      break
    fi
  fi

  # 3. Check if process exited prematurely
  if ! kill -0 "$app_pid" 2>/dev/null; then
    wait "$app_pid" || status=$?
    status=${status:-0}
    if [[ "$status" -ne 0 ]]; then
      echo "ERROR: App process exited prematurely with status $status:" >&2
      cat "$log_file" >&2
      exit 1
    fi
  fi

  if (( elapsed >= timeout_secs )); then
    break
  fi

  sleep 1
done

kill -9 "$app_pid" 2>/dev/null || true

if (( pass != 1 )); then
  echo "ERROR: GUI smoke test timed out after ${timeout_secs}s without detecting GTK window." >&2
  cat "$log_file" >&2
  exit 1
fi
