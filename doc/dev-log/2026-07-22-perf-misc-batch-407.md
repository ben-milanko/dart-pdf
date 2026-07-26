# 2026-07-22 — perf misc batch (#407)

The grab-bag of small, independent wins from the architecture review. Each
stands alone; all landed in one PR since none touch the same subsystem.

## What landed

1. **Chunked signing digest** (`signature_editor.dart`). `_SignatureRevision`
   no longer pre-concatenates the two /ByteRange spans into a `signedData`
   buffer. It holds the patched `saved` buffer + the /Contents offsets and
   exposes `digestSha256()`, which feeds both spans through
   `sha256.startChunkedConversion` over `Uint8List.sublistView`s — no copy,
   no 2× peak memory per sign. Four call sites (RSA/ECDSA sign, PAdES sign +
   TSA imprint) switched to it. The validate path (`signature.dart`) was left
   alone: its concatenated buffer flows into `cmsVerify`, so removing the copy
   there is not self-contained.

2. **Text extraction.** The O(n²) `_visualLines` banding was already fixed in
   a prior PR (running centre sum + `_insertSorted` font sizes). Remaining
   here: `_bidiLine` no longer allocates a `String.fromCharCode(rune)` per
   character just to read its UTF-16 length — `rune > 0xFFFF ? 2 : 1`. The
   `quadsFor`/`positionNear` binary-search suggestion was **not** taken:
   `runs` is not guaranteed sorted by `startIndex` (both `textIn` and
   `_visualLines` sort before use), and `positionNear` is an inherently
   spatial nearest-point scan with no 1-D index.

3. **JPX inverse DWT in place** (`jpx.dart` `_synthesize1d`). Was allocating
   `result` + one `Float32List.fromList` per lift (5+ per row/column per
   resolution level). Key insight making in-place safe and **bit-exact**:
   reflection about `n-1` (`2*(n-1)-index`) preserves index parity, so every
   lift only ever reads samples of the opposite parity to the one it writes —
   never an already-updated sample. Both the 5/3 (reversible) and 9/7 lifts
   now mutate `signal` directly, no scratch buffers. The lossless KAT (5/3
   bit-perfect) and lossy 9/7 (matches OpenJPEG ±1) both still pass, which is
   the proof the arithmetic order is unchanged.

4. **PNG predictor** (`predictor.dart`). The per-byte `switch (filter)` in the
   PNG-predictor loop is hoisted into five specialised row loops (filter is
   constant per row). Filter 0 (None) is now a single `setRange`.

5. **RegExp hoisting.** The /DA-parsing getters in `annotation.dart`,
   `form.dart`, and `annotation_behavior.dart` compiled a fresh `RegExp` per
   call (these run per sidebar/field tile). All hoisted to top-level `final`s;
   `annotation_behavior` reuses `annotation.dart`'s `_daTfRe` (it's a `part`).

6. **Lexer literal strings** (`lexer.dart`). `_literalString` bulk-appends the
   run of ordinary bytes up to the next byte needing interpretation
   (`\`, `(`, `)`, CR) via `sublistView` instead of one `addByte` per char.
   The trailing plain-byte `else` became dead and was removed.

7. **`referenceTo` reverse index** (`document.dart`). Was a linear scan of
   `_cache` per call (editing code maps a mutated object back to its number
   per mutation — quadratic on large docs). Added `_reverseCache`
   (`Map.identity()`), kept in lockstep with `_cache` at every insert/remove
   site (`adoptObject`, `getObject`, the incremental-update `removeWhere`, and
   the trailer-merge `clear`). `referenceTo` is now a single map lookup.

## Correctness fix found in passing (item 8)

`signature_editor.dart` appended a new signature field to the AcroForm
`/Fields` by mutating the *resolved* array in place. When `/Fields` is an
**indirect** array, the array object was never re-staged with the updater, so
the incremental save wrote the original array bytes and the new signature was
silently dropped from `/Fields`. Fixed to rebuild the array and re-stage
whichever object owns it (`replaceObject` when indirect, inline assignment
otherwise) — the same rule `_PdfPageAnnotationList` already uses for /Annots.
Regression test: `buildIndirectFieldsPdf()` + "a new signature field is
appended when /Fields is indirect" in `signature_test.dart`.

## Ticket

Closes **#407** (all 8 items addressed; items 2's banding was pre-done, and
the `quadsFor` binary search was deliberately declined for the reason above).
