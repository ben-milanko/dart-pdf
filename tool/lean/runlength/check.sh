#!/usr/bin/env bash
# Checks the RunLengthDecode proofs and that the Dart test vectors still come
# from them. Needs `lean` + `lake` (Lean 4, see lean-toolchain) on PATH; it is
# not part of CI, which has no Lean.
#
#   tool/lean/runlength/check.sh            # verify
#   tool/lean/runlength/check.sh --update   # also rewrite the vectors file
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
VECTORS="$ROOT/packages/pdf_cos/test/data/run_length_lean_vectors.txt"
# The count and seed the checked-in vectors were generated with.
COUNT=500
SEED=20261114

cd "$HERE"

echo "==> checking the proofs"
# Building the library type-checks every theorem; a proof that does not go
# through fails the build. `#print axioms` then shows what each one rests on:
# an unfinished proof would list `sorryAx`.
rm -rf .lake/build
build_log="$(lake build 2>&1)" || { echo "$build_log"; exit 1; }
echo "$build_log" | grep "depends on axioms" | sed 's/^.*: //'
if echo "$build_log" | grep -q "sorryAx\|declaration uses .sorry."; then
  echo "✗ a proof is unfinished (sorry)"; exit 1
fi
for theorem in decode_eq_spec length_decodeSpec_le decodeSpec_encode; do
  echo "$build_log" | grep -q "RunLength.$theorem' depends on axioms" ||
    { echo "✗ $theorem was not checked"; exit 1; }
done

echo "==> regenerating the test vectors from the verified decoder"
fresh="$(lake env lean --run Main.lean vectors "$COUNT" "$SEED")"
if [ "${1:-}" = "--update" ]; then
  printf '%s\n' "$fresh" > "$VECTORS"
  echo "wrote $VECTORS"
elif [ "$fresh" != "$(cat "$VECTORS")" ]; then
  echo "✗ $VECTORS is not what the model produces (run with --update)"; exit 1
fi

echo "✓ proofs check; $(printf '%s\n' "$fresh" | wc -l | tr -d ' ') vectors match"
echo "  now run: cd packages/pdf_cos && dart test test/run_length_lean_vectors_test.dart"
