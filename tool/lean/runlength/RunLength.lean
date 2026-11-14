/-!
# RunLengthDecode (ISO 32000 §7.4.5), specified and verified

A proof of concept for `packages/pdf_cos/lib/src/filters/run_length.dart`.

* `decodeSpec` is the specification: the standard's three cases, plus this
  codebase's leniency on damaged input, written as plainly as possible.
* `decodeLoop` / `decode` is the implementation model: the same index-driven
  loop over a byte array with an output accumulator that the Dart code runs.
* `decode_eq_spec` proves the two agree on every input.
* `length_decodeSpec_le` bounds the output: no input can expand by more than
  128x (the decompression-bomb bound).
* `decodeSpec_encode` proves a simple encoder round-trips.
-/

namespace RunLength

/-! ## Specification -/

/-- RunLengthDecode on a list of bytes.

A length byte `n`:
* `n = 128` ends the data (EOD); anything after it is ignored.
* `n < 128` copies the next `n + 1` bytes literally. A run cut short by the
  end of the data yields the bytes that are there (lenient, as the Dart is).
* `n > 128` repeats the next byte `257 - n` times. A repeat with no byte to
  repeat yields nothing (lenient).

Data that ends without an EOD marker simply ends. -/
def decodeSpec : List UInt8 → List UInt8
  | [] => []
  | n :: rest =>
    if n = 128 then []
    else if n < 128 then
      rest.take (n.toNat + 1) ++ decodeSpec (rest.drop (n.toNat + 1))
    else
      match rest with
      | [] => []
      | b :: rest' => List.replicate (257 - n.toNat) b ++ decodeSpec rest'
termination_by xs => xs.length
decreasing_by
  all_goals simp_wf
  all_goals omega

/-! ## Implementation model

The loop of `RunLengthFilter.decode`: a read index `i` into `data` and an
output buffer `out`.

```dart
while (i < data.length) {
  final length = data[i++];
  if (length == 128) break;
  if (length < 128) {
    final count = length + 1;
    final end = i + count > data.length ? data.length : i + count;
    out.add(Uint8List.sublistView(data, i, end));
    i = end;
  } else {
    if (i >= data.length) break;
    out.add(Uint8List(257 - length)..fillRange(0, 257 - length, data[i]));
    i++;
  }
}
```
-/

def decodeLoop (data : Array UInt8) (i : Nat) (out : Array UInt8) : Array UInt8 :=
  if h : i < data.size then
    let length := data[i]
    if length = 128 then out
    else if length < 128 then
      let count := length.toNat + 1
      let stop := if i + 1 + count > data.size then data.size else i + 1 + count
      decodeLoop data stop (out ++ data.extract (i + 1) stop)
    else
      if h' : i + 1 < data.size then
        decodeLoop data (i + 2) (out ++ Array.replicate (257 - length.toNat) data[i + 1])
      else out
  else out
termination_by data.size - i
decreasing_by
  all_goals simp_wf
  all_goals (try split) <;> omega

/-- The decoder: the loop from the start of the data with an empty buffer. -/
def decode (data : Array UInt8) : Array UInt8 := decodeLoop data 0 #[]

/-! ## The specification, one case at a time -/

@[simp] theorem decodeSpec_nil : decodeSpec [] = [] := by
  unfold decodeSpec; rfl

theorem decodeSpec_eod (rest : List UInt8) : decodeSpec (128 :: rest) = [] := by
  unfold decodeSpec; simp

theorem decodeSpec_literal (n : UInt8) (rest : List UInt8) (h : n < 128) :
    decodeSpec (n :: rest) =
      rest.take (n.toNat + 1) ++ decodeSpec (rest.drop (n.toNat + 1)) := by
  have hne : n ≠ 128 := by
    intro hEq; subst hEq; exact absurd h (by decide)
  rw [decodeSpec.eq_def]; simp [hne, h]

theorem decodeSpec_repeat_nil (n : UInt8) (hEod : n ≠ 128) (hLit : ¬n < 128) :
    decodeSpec [n] = [] := by
  rw [decodeSpec.eq_def]; simp [hEod, hLit]

theorem decodeSpec_repeat (n b : UInt8) (rest : List UInt8) (hEod : n ≠ 128)
    (hLit : ¬n < 128) :
    decodeSpec (n :: b :: rest) = List.replicate (257 - n.toNat) b ++ decodeSpec rest := by
  rw [decodeSpec.eq_def]; simp [hEod, hLit]

/-! ## The implementation agrees with the specification -/

/-- The tail of the data from an in-range index starts with the byte there. -/
theorem drop_cons (data : Array UInt8) (i : Nat) (h : i < data.size) :
    data.toList.drop i = data[i] :: data.toList.drop (i + 1) := by
  rw [List.drop_eq_getElem_cons (by simpa using h)]
  simp

/-- The loop invariant: running the loop from index `i` with buffer `out`
appends to `out` exactly what the specification decodes from the rest of the
data. -/
theorem decodeLoop_toList (data : Array UInt8) (i : Nat) (out : Array UInt8) :
    (decodeLoop data i out).toList = out.toList ++ decodeSpec (data.toList.drop i) := by
  fun_induction decodeLoop data i out with
  | case1 i out h length hEod =>
    have hEod' : data[i] = 128 := hEod
    rw [drop_cons data i h, hEod', decodeSpec_eod]
    simp
  | case2 i out h length hEod hLit count stop ih =>
    have hLit' : data[i] < 128 := hLit
    rw [ih, drop_cons data i h, decodeSpec_literal _ _ hLit']
    simp only [Array.toList_append, List.append_assoc, List.append_cancel_left_eq]
    congr 1
    · simp only [stop, count, length]
      split
      · rw [Array.toList_extract, List.extract_eq_take_drop]
        rw [List.take_of_length_le (by simp <;> omega), List.take_of_length_le (by simp <;> omega)]
      · rw [Array.toList_extract, List.extract_eq_take_drop]
        congr 1
        omega
    · simp only [stop, count, length]
      split
      · rw [List.drop_of_length_le (by simp), List.drop_of_length_le (by simp <;> omega)]
      · rw [List.drop_drop]
  | case3 i out h length hEod hLit h' ih =>
    have hEod' : data[i] ≠ 128 := hEod
    have hLit' : ¬data[i] < 128 := hLit
    rw [ih, drop_cons data i h, drop_cons data (i + 1) h',
      decodeSpec_repeat _ _ _ hEod' hLit']
    simp [length]
  | case4 i out h length hEod hLit h' =>
    have hEod' : data[i] ≠ 128 := hEod
    have hLit' : ¬data[i] < 128 := hLit
    have hnil : data.toList.drop (i + 1) = [] := List.drop_of_length_le (by simp <;> omega)
    rw [drop_cons data i h, hnil, decodeSpec_repeat_nil _ hEod' hLit']
    simp
  | case5 i out h =>
    have hnil : data.toList.drop i = [] := List.drop_of_length_le (by simp <;> omega)
    simp [hnil]

/-- **The implementation model decodes exactly what the specification says**,
for every input - well-formed, truncated or garbage. -/
theorem decode_eq_spec (data : Array UInt8) :
    (decode data).toList = decodeSpec data.toList := by
  simp [decode, decodeLoop_toList]

/-! ## No decompression bomb -/

/-- The output is at most 128 times the input: a repeat packet turns 2 bytes
into at most 128, and a literal packet never grows. A reader can size or cap
its buffer from the input length alone. -/
theorem length_decodeSpec_le (xs : List UInt8) :
    (decodeSpec xs).length ≤ 128 * xs.length := by
  fun_induction decodeSpec xs with
  | case1 => simp
  | case2 rest => simp
  | case3 n rest hEod hLit ih =>
    simp only [List.length_append, List.length_take, List.length_cons, List.length_drop] at ih ⊢
    omega
  | case4 n hEod hLit => simp
  | case5 n hEod hLit b rest ih =>
    simp only [List.length_append, List.length_replicate, List.length_cons] at ih ⊢
    have : 128 ≤ n.toNat := by
      have := UInt8.not_lt.mp hLit
      exact UInt8.le_iff_toNat_le.mp this
    omega

/-! ## Round trip -/

/-- A simple encoder: literal runs of at most 128 bytes, then EOD. -/
def encode (xs : List UInt8) : List UInt8 :=
  if _h : xs = [] then [128]
  else
    UInt8.ofNat ((xs.take 128).length - 1) :: (xs.take 128 ++ encode (xs.drop 128))
termination_by xs.length
decreasing_by
  simp_wf
  have : 0 < xs.length := List.length_pos_iff.mpr (by assumption)
  omega

/-- Decoding what `encode` produced gives back the original bytes. -/
theorem decodeSpec_encode (xs : List UInt8) : decodeSpec (encode xs) = xs := by
  fun_induction encode xs with
  | case1 => simp [decodeSpec_eod]
  | case2 xs h ih =>
    have hpos : 0 < xs.length := List.length_pos_iff.mpr h
    have hlen : (xs.take 128).length - 1 < 128 := by
      simp only [List.length_take]; omega
    have htoNat : (UInt8.ofNat ((xs.take 128).length - 1)).toNat = (xs.take 128).length - 1 := by
      simp only [UInt8.toNat_ofNat']
      omega
    have hlt : UInt8.ofNat ((xs.take 128).length - 1) < 128 := by
      rw [UInt8.lt_iff_toNat_lt, htoNat]
      exact hlen
    rw [decodeSpec_literal _ _ hlt, htoNat]
    have hcount : (xs.take 128).length - 1 + 1 = (xs.take 128).length := by
      simp only [List.length_take]; omega
    rw [hcount, List.take_left', List.drop_left', ih, List.take_append_drop]
    · rfl
    · rfl

end RunLength

/-! ## What the proofs rest on

Lean's three standard axioms only - in particular no `sorryAx`, which is what
an unfinished proof would show up as. `check.sh` asserts this. -/

#print axioms RunLength.decode_eq_spec
#print axioms RunLength.length_decodeSpec_le
#print axioms RunLength.decodeSpec_encode
