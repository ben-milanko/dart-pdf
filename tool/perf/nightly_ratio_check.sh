#!/usr/bin/env bash
# perf-nightly's baseline-rerun ratio check against ONE baseline commit
# (.github/workflows/perf-nightly.yml runs it once per baseline):
#
#   tool/perf/nightly_ratio_check.sh <label> <sha>
#   tool/perf/nightly_ratio_check.sh <label> --sha-file <file>
#
# Re-measures the VM scenarios at the baseline on this runner, interleaved
# with the working tree (tool/perf/perf_diff.sh, red above a 1.15x median),
# and writes `<label>=ok|regressed|error|skipped` to $GITHUB_OUTPUT, plus
# `<label>_sha=<full sha>` for --sha-file. Exit 0 for ok/skipped, 1 for
# regressed/error, 2 for bad usage.
#
# `regressed` needs perf_diff's own verdict line, not just its exit 1:
# perf_diff.sh also exits 1 when a side produced no envelopes
# (merge_runs.dart) or a `set -e` command fails, and a baseline whose grafted
# harness cannot run is an `error`, not a regression.
#
# A <sha> that is empty or not a commit is `skipped` (the first night, or a
# previous nightly lost to a history rewrite). A --sha-file that does not
# name exactly one commit is an `error`: that file is the reviewed accepted
# baseline, and a typo in it must not quietly switch the weekly check off.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

usage() {
  echo "usage: nightly_ratio_check.sh <label> <sha>" >&2
  echo "       nightly_ratio_check.sh <label> --sha-file <file>" >&2
  exit 2
}
[ $# -ge 2 ] || usage
LABEL="$1"
shift

# record <verdict> [why]: logs the verdict and hands it to the workflow.
record() {
  echo "$LABEL: $1${2:+ - $2}"
  echo "$LABEL=$1" >>"$OUTPUT"
}

commit_of() { git -C "$ROOT" rev-parse -q --verify "$1^{commit}" 2>/dev/null; }

if [ "$1" = --sha-file ]; then
  [ $# -eq 2 ] || usage
  file="$2"
  # Comments and blank lines aside, the file must name exactly one commit.
  entries=()
  if [ -r "$file" ]; then
    read -r -a entries <<<"$(sed 's/#.*//' "$file" | tr '\n' ' ')"
  fi
  if [ "${#entries[@]}" -ne 1 ]; then
    record error "$file names ${#entries[@]} commits, expected exactly one"
    exit 1
  fi
  if ! sha=$(commit_of "${entries[0]}"); then
    record error "$file names ${entries[0]}, which is not a commit here"
    exit 1
  fi
  echo "${LABEL}_sha=$sha" >>"$OUTPUT"
else
  [ $# -eq 1 ] || usage
  if [ -z "$1" ] || ! sha=$(commit_of "$1"); then
    record skipped "no usable baseline commit${1:+ ($1)}"
    exit 0
  fi
fi

if [ "$sha" = "$(git -C "$ROOT" rev-parse HEAD)" ]; then
  record skipped "baseline is HEAD (no new commits)"
  exit 0
fi

echo "$LABEL: ratio check vs $sha (same-runner, interleaved)"
log=$(mktemp)
trap 'rm -f "$log"' EXIT
verdict=ok
for scenario in save-incremental ghent-suite-open; do
  # ghent-suite-open carries firstPageMs, a few ms per file: two interleaved
  # runs are too thin for it night over night.
  iterations=2
  [ "$scenario" = ghent-suite-open ] && iterations=4
  "$ROOT/tool/perf/perf_diff.sh" "$sha" "$scenario" \
    --iterations "$iterations" --threshold 1.15 --clean 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  [ "$rc" = 0 ] && continue
  if [ "$rc" = 1 ] && grep -q '^VERDICT: REGRESSED' "$log"; then
    verdict=regressed
  else
    echo "$LABEL: perf_diff.sh exited $rc on $scenario without a REGRESSED verdict - an error, not a regression"
    [ "$verdict" = ok ] && verdict=error
  fi
done
record "$verdict"
[ "$verdict" = ok ]
