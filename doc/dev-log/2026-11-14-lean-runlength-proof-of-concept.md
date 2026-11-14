# 2026-11-14 - Lean proof of concept: RunLengthDecode

A small experiment in formal verification, prompted by "could Lean be applied
to PDF rendering?". One decoder, specified and proved in Lean 4, with the Dart
held to it by test vectors. Everything is in `tool/lean/runlength/` (start
with its README) plus one test in pdf_cos.

## What it is

- `RunLength.lean` - `decodeSpec` (§7.4.5 plus our leniency on damaged input,
  written plainly), `decodeLoop`/`decode` (a transcription of the index loop
  in `run_length.dart`), and three theorems: the loop equals the spec on every
  input (`decode_eq_spec`), output <= 128x input (`length_decodeSpec_le`), and
  an encoder round-trips (`decodeSpec_encode`). Core Lean only, no Mathlib.
- `Main.lean` - an oracle that prints `input output` hex pairs from the
  verified decoder.
- `packages/pdf_cos/test/run_length_lean_vectors_test.dart` - runs the real
  `RunLengthFilter` over the 514 checked-in vectors.
- `check.sh` - rebuilds the proofs, asserts none is unfinished, regenerates
  the vectors and diffs them against the checked-in file. Not in CI (no Lean
  there); the Dart test is.

## Result

The Dart decoder agrees with the verified model on every vector: no bug
found. The test does bite - four hand mutations of the decoder (257 -> 256,
EOD 128 -> 127, count off by one, dropping the end clamp) each fail it - and
`check.sh` fails on a `sorry` or on a spec changed out from under the proofs.

## What it does and doesn't buy

The proof is about the Lean model. The Dart is connected to it by reading the
two side by side and by the vectors; that link is a test. What changes is
where the expected values come from: something proved against a spec, not a
second implementation.

It costs little at this size (about 230 lines, an afternoon including the
toolchain). It would not scale to the interpreter or render pipeline, whose
"spec" is the standard plus compatibility with broken files. The next
candidates if this is worth extending are the other small pure kernels: the
ASCIIHex/ASCII85 decoders, the PNG/TIFF predictors, LZW.

## Gotchas

- `a :: b ++ c` parses as `(a :: b) ++ c` in Lean; a rewrite that expected
  `a :: (b ++ c)` silently didn't match.
- `rw [decodeSpec]` fails on a function defined by well-founded recursion with
  nested matches; state one unfolding lemma per case (`decodeSpec_eod`,
  `decodeSpec_literal`, ...) and rewrite with those.
- The Nix build of Lean cannot link native executables against the system
  libstdc++, so `check.sh` runs the oracle with `lean --run`.
- In this cloud environment Lean's GitHub release downloads are blocked by the
  network policy (so `elan` cannot fetch a toolchain); Lean 4.35 came from
  nixpkgs instead.
