# AES: 32-bit T-table rounds (about 7x)

`Aes` (`packages/pdf_cos/lib/src/crypto/aes.dart`) worked a byte at a time:
SubBytes, ShiftRows, MixColumns and AddRoundKey each looped over a 16-byte
`Uint8List`, and CBC decrypt copied every block with `Uint8List.fromList`. It
ran at 12-18 MB/s AOT. That rate is paid on every AES-128/AES-256 stream a
render worker or the UI isolate decodes (content, fonts, images, the text
layer), and inside Algorithm 2.B, which runs on every R6 (AES-256) open: the
UI open, each worker's open and each undo reopen.

## Prior art

#400 proposed dropping the per-block copy. #439 shipped only the object-key
memo: it measured the copy removal as flat (60.1 vs 60.9 ms/MB) and noted
that "the block cipher dominates". That result is correct and is the reason
for this change. The rounds were the cost, not the allocation.

## What changed

The standard word-oriented formulation:

- `_te0..3` / `_td0..3`: `static final Uint32List(256)` tables built from the
  existing `_sbox` / `_invSbox` with `_gfMul`. `_te0[x]` is the MixColumns
  column of `S(x)`, rows (2s, s, s, 3s). `_td0[x]` is the InvMixColumns column
  of `S^-1(x)`, rows (14i, 9i, 13i, 11i). The other three are rotations by
  8/16/24 bits. 8 KB per isolate, built on first use.
- The state is four big-endian words in locals. An inner round is 16 table
  lookups XORed with the round key. The last round uses the plain S-box with
  ShiftRows folded into the byte selection (`_lastRound`).
- Decryption uses the equivalent inverse cipher (FIPS 197 §5.3.5): the
  schedule is reversed and InvMixColumns is applied to the inner round keys
  (`_td*[_sbox[b]]` is InvMixColumns of byte `b`). These keys are a
  `late final`, so encrypt-only users, meaning Algorithm 2.B with its fresh
  `Aes` per round, never compute them.
- CBC chaining lives in four locals. Decrypt keeps the previous ciphertext
  words it already loaded and reads `data` in place, so there is no
  per-block copy.
- The public API is unchanged, and so is `assert(len % 16 == 0)`.

Behaviour kept on purpose:

- **IV bytes.** `iv` is a `List<int>`. The old code XORed each element into a
  byte buffer, so only its low byte counted. `_ivWord` masks with `& 0xFF`,
  which gives the same result for out-of-range elements.
- **Empty input.** Both CBC calls return early on empty data before reading
  the IV. The old code only touched the IV when a block used it, so a short
  IV with no data never threw, and it still doesn't.
- **Misaligned input.** The loop runs `off < data.length`, not up to a
  rounded-down end, so a misaligned tail still reads past the end and throws
  in release builds. The old code threw a `StateError` on decrypt and a
  `RangeError` on encrypt; the new code throws `RangeError` on both. An
  earlier prototype silently truncated the tail and left zeros in the output.
  No in-library caller passes misaligned data: `decryptContent` aligns, and
  Algorithm 2.B's input is a multiple of 64.
- **dart2js.** Only `>>>`, `&` and `^` on values of at most 32 bits, and
  stores go through `Uint8List`/`Uint32List`. `_rotate` masks the left shift
  so that the VM's 64-bit ints match.

## Correctness

- **New KATs in `crypto_test.dart`.** FIPS 197 C.1 decrypt, C.2 (AES-192)
  both directions, C.3 decrypt, and SP 800-38A F.2.6 (4-block AES-256-CBC
  decrypt).
- **New round-trip tests.** A multi-block round trip for every key size,
  with input as offset views and one instance used for both directions. An
  `encryptContent` -> `decryptContent` round trip at every padding length
  from 0 to 48 bytes. An empty-input test with a short IV.
- **Where the tests pass.** The VM and `-p node`.
- **Differential harness.** A scratch harness compared the new cipher with
  a verbatim copy of the old one: the KATs, 3,000 random trials (16/24/32-byte
  keys, 0-19 blocks, offset views, `List<int>` and out-of-range IVs,
  `encryptContent`/`decryptContent` at random lengths), a shared instance
  alternating directions, empty input with short IVs, and the
  misaligned-throws check. Output was byte-identical under JIT, AOT and
  dart2js `-O2`, `-O3` (the web worker's level) and `-O4`.
- **Real encrypted files.** Every indirect object in every encrypted file of
  the pdf.js test suite was hashed after decryption: all strings, and every
  stream payload, with JPEG/JPX payloads taken before their image filter.
  That is 9 files (RC4 R3, AES-128 R4, AES-256 R6), and the hashes matched
  the base build. The same check matched on AES-128 copies of plan-set-16p,
  scan-book-12p, photo-jpeg-6p and text-report-40p and an AES-256 copy of
  plan-set-16p (about 60 MB decrypted).
- **Record path.** The record+serialize buffers from the A/B below hash the
  same on both builds.
- **Output identity.** Rendered output, extracted text and saved bytes are
  unchanged by construction: the decrypted bytes are the same.

## Measurements

Method:

- Base worktree at 861fe54c (main) against this branch.
- AOT executables.
- Thread CPU time (`CLOCK_THREAD_CPUTIME_ID`).
- Runs interleaved ABAB with alternating order, and the result is the median
  of the per-round ratios.
- Machine load average was 10-19 on 10 cores throughout the runs.

Encrypted copies were made with `appendPagesFrom` into a
`buildEncryptedPdf(revision: 4|6)` base and then saved, so they are
encrypted on write. Page counts are the source pages plus the base's one
page.

Cipher, 8 MB, 7 rounds, in-process against a verbatim copy of the old class:

| | old MB/s | new MB/s | ratio |
|---|---|---|---|
| AES-128 decrypt | 17.8 | 126.7 | 7.13x |
| AES-128 encrypt | 18.6 | 133.7 | 7.19x |
| AES-256 decrypt | 12.8 | 93.9 | 7.32x |
| AES-256 encrypt | 13.4 | 99.6 | 7.44x |

dart2js `-O3` (the web worker's level) in node, 4 MB: AES-128 decrypt
26.5 -> 220.8 MB/s (8.3x), encrypt 7.1x; AES-256 decrypt 8.8x, encrypt
7.2x. An earlier run measured 6.8-10.3x at `-O2` and 5.3-6.2x at `-O4`.

`decryptContent` per call, with a fresh key schedule each call as the
security handler does:

| payload | AES-128 | AES-256 |
|---|---|---|
| 32 B (one block) | 1.68x | 1.70x |
| 80 B (four blocks) | 3.59x | 3.74x |
| 1 KB | 6.72x | 6.93x |
| 16 KB | 7.16x | 7.36x |

End to end. Record is a cold open followed by record + serialize with
`decodeImages` on every page, the render worker's first pass. Open is
`PdfDocument.open` + `pageCount` + page 0 content.

| workload (rounds) | base ms | new ms | new/base |
|---|---|---|---|
| record, plan-set-16p AES-128 (7) | 231.3 | 133.1 | 0.575 (1.74x) |
| record, plan-set-16p AES-256 (7) | 300.5 | 148.8 | 0.494 (2.02x) |
| record, photo-jpeg-6p AES-128 (7) | 83.3 | 12.1 | 0.143 (6.97x) |
| record, scan-book-12p AES-128 (5) | 166.3 | 143.7 | 0.861 (1.16x) |
| record, text-report-40p AES-128 (5) | 23.5 | 21.0 | 0.910 (1.10x) |
| open, R6 copy of plan-set (7) | 28.9 | 9.8 | 0.339 (2.95x) |
| open, AES-128 copy of plan-set (7) | 0.13 | 0.13 | 1.00 (noise) |
| record, plan-set-16p unencrypted (7) | 115.1 | 115.5 | 1.005 (noise) |
| record, text-report-40p unencrypted (5) | 20.6 | 20.4 | 1.003 (noise) |

Notes on these numbers:

- The photo copy is almost all decrypt, because JPEG bytes pass through to
  the platform codec undecoded.
- The encrypted vector plan set now costs 1.16x its unencrypted self, down
  from 2.0x.

## Gotchas / what this does not fix

- **The R6 open on the web is SHA-2-bound.** An R6 open under dart2js
  `-O3` in node went from 88 to 73 ms (1.2x, 7 interleaved rounds).
  Algorithm 2.B's SHA-384/512 from package:crypto emulates 64-bit arithmetic
  and dominates there. A VM profile from the investigation puts the remaining
  ~10 ms native at roughly half SHA-2 and half AES plus `_hash2B`'s list
  spreads.
- **Reopening is the real lever for that cost.** Reopen with the
  authenticated handler (`openAppended` / `keysFrom`) on undo and in the
  worker's shrink reopen. That is a separate change; passing key material to
  workers over the port has its own trust question.
- **Not done here.**
  - Caching one `Aes` per key in `StandardSecurityHandler`. Key setup is
    microseconds, and even one-block strings are already 1.7x faster.
  - Reworking `_hash2B`'s per-round allocations. Measure it first.
- **Workload spread.** Encrypted files are a minority in real-world sets
  (none in a private real-world corpus of about 50 files; 10 of 171 in the
  pdf.js suite). The change helps whenever an AES document is opened and
  costs nothing otherwise, with no effect on RC4 or unencrypted documents.
- **No constant-time claim.** Table lookups are not constant-time. That does
  not matter for decrypting a document the user opened locally, and the
  byte-wise version was not constant-time either, because it used the same
  kind of S-box lookups.
