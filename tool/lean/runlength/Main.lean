import RunLength

/-!
The oracle: runs the verified `RunLength.decode` and prints `input output`
pairs as hex, one per line (`-` for no bytes), for the Dart decoder to be
tested against.

    lake exe oracle vectors <count> <seed>   # generated inputs
    lake exe oracle decode                   # hex inputs on stdin, one per line
-/

open RunLength

def hexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat (48 + n) else Char.ofNat (87 + n)

def toHex (bytes : Array UInt8) : String :=
  if bytes.isEmpty then "-"
  else String.ofList (bytes.toList.flatMap fun b =>
    [hexDigit (b.toNat / 16), hexDigit (b.toNat % 16)])

def hexValue (c : Char) : Option Nat :=
  if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - 48)
  else if 'a' ≤ c ∧ c ≤ 'f' then some (c.toNat - 87)
  else if 'A' ≤ c ∧ c ≤ 'F' then some (c.toNat - 55)
  else none

def fromHex (s : String) : Option (Array UInt8) :=
  if s = "-" then some #[] else
  let rec go : List Char → Array UInt8 → Option (Array UInt8)
    | [], acc => some acc
    | [_], _ => none
    | hi :: lo :: rest, acc => do
      let h ← hexValue hi
      let l ← hexValue lo
      go rest (acc.push (UInt8.ofNat (h * 16 + l)))
  go s.toList #[]

/-- A 64-bit LCG (Knuth's MMIX constants); the top bits are the useful ones. -/
def next (state : UInt64) : UInt64 :=
  state * 6364136223846793005 + 1442695040888963407

def draw (state : UInt64) (bound : Nat) : Nat × UInt64 :=
  let s := next state
  ((s >>> 33).toNat % bound, s)

/-- One byte, weighted towards the values the format gives meaning to: short
literal runs, the EOD marker and its neighbours, and long/short repeats. -/
def drawByte (state : UInt64) : UInt8 × UInt64 :=
  let (kind, s) := draw state 20
  if kind < 8 then let (v, s) := draw s 6; (UInt8.ofNat v, s)
  else if kind < 12 then let (v, s) := draw s 6; (UInt8.ofNat (250 + v), s)
  else if kind < 14 then let (v, s) := draw s 3; (UInt8.ofNat (127 + v), s)
  else let (v, s) := draw s 256; (UInt8.ofNat v, s)

def drawInput (state : UInt64) : Array UInt8 × UInt64 := Id.run do
  let (len, s) := draw state 25
  let mut s := s
  let mut out := #[]
  for _ in [0:len] do
    let (b, s') := drawByte s
    out := out.push b
    s := s'
  return (out, s)

/-- Inputs every implementation should be asked about, whatever the seed. -/
def fixed : List (Array UInt8) := [
  #[],                       -- nothing at all
  #[128],                    -- EOD alone
  #[128, 0, 65],             -- data after EOD is ignored
  #[0, 65],                  -- shortest literal run
  #[2, 65, 66, 67, 128],     -- literal run, then EOD
  #[2, 65, 66, 67],          -- no EOD: the data just ends
  #[2, 65],                  -- literal run cut short
  #[5],                      -- literal length with no bytes behind it
  #[255, 65],                -- shortest repeat (2 copies)
  #[129, 65],                -- longest repeat (128 copies)
  #[254],                    -- repeat with no byte to repeat
  #[0, 65, 254],             -- the same, after good data
  #[127] ++ Array.replicate 128 7,  -- longest literal run
  #[127] ++ Array.replicate 100 7   -- longest literal run, cut short
]

def emit (input : Array UInt8) : IO Unit :=
  IO.println s!"{toHex input} {toHex (decode input)}"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["vectors", count, seed] =>
    let some count := count.toNat? | IO.eprintln "count must be a number"; return 2
    let some seed := seed.toNat? | IO.eprintln "seed must be a number"; return 2
    for input in fixed do emit input
    let mut state := UInt64.ofNat seed
    for _ in [0:count] do
      let (input, s) := drawInput state
      state := s
      emit input
    return 0
  | ["decode"] =>
    let stdin ← IO.getStdin
    let mut line ← stdin.getLine
    while line != "" do
      let text := line.trimAscii.toString
      if text != "" then
        match fromHex text with
        | some input => emit input
        | none => IO.eprintln s!"not hex: {text}"; return 2
      line ← stdin.getLine
    return 0
  | _ =>
    IO.eprintln "usage: oracle vectors <count> <seed> | oracle decode"
    return 2
