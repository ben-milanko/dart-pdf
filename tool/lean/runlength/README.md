# RunLengthDecode, verified in Lean

A proof of concept: one small decoder from this repository, specified and
proved correct in [Lean 4](https://lean-lang.org), with the Dart held to the
proof by test vectors.

The decoder is `RunLengthFilter` (`packages/pdf_cos/lib/src/filters/run_length.dart`,
ISO 32000 §7.4.5). It was chosen because it is small, pure and precisely
specified - and because its handling of damaged input is exactly the kind of
thing that is easy to get subtly wrong.

## What is proved

All in `RunLength.lean`, about 230 lines with no dependencies beyond Lean's
core library:

| | Statement |
|---|---|
| `decode_eq_spec` | The implementation model - the same index loop and output buffer the Dart runs - decodes exactly what the specification says, for **every** input: well-formed, truncated or garbage. |
| `length_decodeSpec_le` | The output is never more than 128x the input. A reader can cap its buffer from the input length alone. |
| `decodeSpec_encode` | A simple encoder round-trips: `decode (encode xs) = xs`. |

Lean also requires every function to terminate, so the loop provably ends on
all inputs.

## What is not proved

**Nothing here is a proof about the Dart code.** Lean proves things about Lean
definitions. `decodeLoop` is a hand transcription of the Dart loop, and the
link between the two is:

1. reading them side by side (the Dart source is quoted above the model), and
2. `packages/pdf_cos/test/run_length_lean_vectors_test.dart`, which runs the
   real `RunLengthFilter` over 514 inputs and expects the outputs the verified
   model produced (`test/data/run_length_lean_vectors.txt`): 14 hand-picked
   edge cases and 500 generated ones weighted towards the bytes the format
   gives meaning to.

That is a test, with a test's limits - it is just a test whose expected values
come from something proved, not from another implementation or from a person.

The specification is also this repository's reading of the standard: the
lenient cases (a run cut short, a repeat with nothing to repeat, data with no
end marker) are choices the Dart already made, written down, not requirements
of ISO 32000.

## Running it

Needs Lean 4.35 (`lean` and `lake` on PATH; see `lean-toolchain`). It is not
part of CI.

```bash
tool/lean/runlength/check.sh
```

checks the proofs, confirms none is unfinished, regenerates the vectors and
compares them with the checked-in file. Then:

```bash
cd packages/pdf_cos && fvm dart test test/run_length_lean_vectors_test.dart
```

If the decoder's behaviour is changed on purpose, change `decodeSpec` and
`decodeLoop` to match, re-prove, and run `check.sh --update`.
