#!/usr/bin/env bash
# Repeats the Chrome perf driver N times against the prebuilt harness, then
# prints the aggregate. Alternates a full 133-page sweep with a faster capped
# sweep so each cycle covers both steady-state and the worst raster pages.
#
#   tool/perf/build.sh        # once, after any code change
#   tool/perf/loop.sh 8       # then loop 8 iterations
#
# Env passes through to driver.mjs (PERF_HEADLESS, PERF_TIMEOUT, PERF_VERBOSE…).
set -uo pipefail
cd "$(dirname "$0")"

N="${1:-6}"
echo "▶ perf loop: $N iteration(s)"
for ((i = 1; i <= N; i++)); do
  if (( i % 2 == 1 )); then
    echo "── iter $i/$N: full sweep (133 pages) ──"
    PERF_MAX_PAGES= PERF_FAST_PASS=1 node driver.mjs || true
  else
    echo "── iter $i/$N: fast capped sweep (40 pages) ──"
    PERF_MAX_PAGES=40 PERF_FAST_PASS=1 node driver.mjs || true
  fi
done

echo "▶ aggregate over the loop:"
node report.mjs "$N"
