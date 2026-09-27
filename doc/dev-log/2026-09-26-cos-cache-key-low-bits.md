# CosDocument object-cache key: object number in the low bits

#522 (PR #549, a8f10821) keyed `CosDocument._cache` by one packed int,
`objectNumber * 65536 + generation`, so a warm `getObject` allocates no
`CosReference`. It measured 0.98x on the Ghent suite, where a document caches a
few hundred objects. The packing had a cost that only shows on big documents.

## Why the old key was slow

The VM, AOT and dart2wasm `int.hashCode` is a multiply by 0x2D51 with a fold of
the high word. A multiply keeps trailing zero bits: `65536.hashCode` is
0x2d510000. Every `n * 65536 + 0` key therefore has zero low 16 bits, and the
only thing left in the bits the table masks with is the tiny high-word fold.
For object numbers 1..4096 under a 4096 mask that is 726 distinct first-probe
buckets instead of 4096. `compact_hash.dart` probes linearly, so the keys pile
into shared chains and a lookup walks them: about 8 us per warm hit at 29k
cached objects, against about 20 ns with a well-spread key.

Rendering never noticed. It touches a sparse subset of objects (a few hundred
to ~2k cached even on 30k-object files), so the tables stay small. The code
paths that load the whole object graph did notice:

- `PdfCompressor.optimize` ("Reduce file size", run by the native compression
  worker). It compacts, reopens the compacted output (densely renumbered, the
  worst case) and walks the full graph again for prune, dedup and font subset.
- `CosCompactor.run`, which copies every reachable object once.
- `PdfEditor.applyRedactions`, whose burn resolves every reachable object and
  which the app runs synchronously on the UI isolate.
- Any full-graph walk: xref-wide loads, encryption graph walks, deep copies.

dart2js was not immune either. `JsLinkedHashMap` sends keys at or above 2^30
(object number 16,384 and up under the old packing) to its slower bucket path,
so large documents paid a constant factor on the web too.

## The fix

`packages/pdf_cos/lib/src/document.dart`:

- `_cacheKey(n, g) => g * 0x100000000 + n`. Generation 0, which is nearly every
  object, keys by the object number itself: dense, well spread, and under 2^30
  on dart2js.
- `_objectNumberOf(key) => key % 0x100000000` replaces the one arithmetic
  decoder, `key ~/ 65536` in `applyIncrementalUpdate`'s eviction. `%`, not
  `&`: dart2js bitwise operators truncate to 32 bits.
- Only refs the key holds exactly get a packed key (`_packable`): object
  number 0..2^32-1 and generation 0..65535. Every packed key is then unique
  and below 2^48, so it is exact on dart2js too. Any other ref goes to a small
  side map, `_unpackedCache`, keyed by the `CosReference` itself. `getObject`,
  `adoptObject`, the eviction and xref recovery's reset all cover both maps.
  The hot path adds one range check (four integer compares).
- `CosDocument.debugCacheKey` exposes the packing to tests. It is not part of
  the stable API.

### Why a side map, not a guard

The first cut of this change made `getObject` return null for any object
number of 2^32 or more, on the theory that such numbers are never valid. They
are not valid by the spec (the limit is 8,388,607), but our own writer hands
them out. `CosIncrementalUpdater` numbers new objects from the trailer /Size
(or one past the highest xref entry) and distrusts /Size only on the low side.
A file whose writer stored -1 as a uint32 has /Size 4294967295, so every
object an edit added (the annotation, its appearance stream, a form value)
got a number the guard refused. The edit vanished: live, after save and
reopen, and in the render worker after `applyIncrementalUpdate`. `main`
handled those files, because `n * 65536` stays exact up to n < 2^37.
`adoptObject` also skipped the guard, so an added object 2^32 + k was stored
under the key of `k 1 R` and shadowed it.

The generation had the same problem at a different threshold. An object body
or a reference can carry any integer as its generation (only the xref field is
5 digits). The old key aliased `n 65536 R` onto `n+1 0 R` on every platform.
The low-bits key fixed that on the VM but, on dart2js, stops being exact once
the generation reaches 2^21, so `4 4194304 R` and `5 4194304 R` shared a key.

The side map keeps `main`'s behaviour for every ref the packed key can't hold
and costs nothing for sane files: it stays empty. Changing the allocator to
ignore a huge /Size would also have worked for new objects, but it would not
have covered refs loaded from a file, and it changes what the writer emits.

The cache is a `LinkedHashMap`: iteration order is insertion order and lookup
is by `==`, so the key layout changes bucket placement only. Nothing iterates
the cache except the eviction's `removeWhere`. Rendered output, extracted text
and saved bytes are identical.

## Numbers

AOT executables built from the parent commit (A) and the first cut of this
change (B, the low-bits key with the null guard) with Dart 3.13.3, one process
per run, interleaved ABBA for 5 rounds (7 for the controls). Thread-CPU
medians in ms. The documents come from a private real-world corpus and are
named here by object count. The machine was shared and loaded, which is why
thread CPU is the headline; wall clock tracked it within a few percent. The
side-map follow-up was re-measured separately (below).

| Workload | Objects | A | B | B/A |
|---|---:|---:|---:|---:|
| `PdfCompressor.optimize` (lossless) | 29,152 | 6208 | 2493 | **0.40** |
| | 14,475 | 1650 | 744 | **0.45** |
| | 17,179 | 3376 | 1905 | 0.56 |
| | 36,605 | 7236 | 5021 | 0.69 |
| | 6,535 | 1201 | 998 | 0.83 |
| `CosCompactor.run` (defaults, deflate 9) | 29,152 | 1904 | 1336 | 0.70 |
| | 14,475 | 481 | 338 | 0.70 |
| | 36,605 | 4670 | 3900 | 0.84 |
| `CosCompactor.run`, graph walk only (deflate 0, no recompress) | 29,152 | 888 | 289 | **0.33** |
| | 14,475 | 248 | 93 | 0.38 |
| | 36,605 | 995 | 304 | **0.31** |
| `applyRedactions` (one rect, page 0) | 29,152 | 1163 | 384 | **0.33** |
| | 14,475 | 355 | 165 | 0.47 |
| | 17,179 | 506 | 162 | **0.32** |
| open + `getObject` on every xref entry | 29,152 | 677 | 79 | **0.12** |
| | 36,605 | 842 | 113 | 0.13 |
| | 14,475 | 188 | 35 | 0.19 |
| | 9,632 | 97 | 12 | 0.13 |
| Control: NullDevice interpret, all 344 pages | 36,605 | 499 | 457 | 0.92 |
| Control: text extraction, all 344 pages | 36,605 | 592 | 585 | 0.99 |

Output was byte-identical in every run: the FNV hash of every optimize,
compact and redact output, and of the extracted text, matched between A and B.
The `tool/perf.sh gate` counters are unchanged (regenerating the baseline
reproduces the committed file byte for byte).

### Re-measured with the side map

Three AOT arms of one driver: the parent commit (A), the first cut (B0) and
the final code with the side map (B1). One process per run, 7 rounds, arms
interleaved with the order rotating each round, thread-CPU medians in ms.
`getObject` warm is open, one load of every object, then 100 more passes over
all of them, which isolates the hot path the range check sits on.

| Workload | Objects | A | B0 | B1 | B1/A | B1/B0 |
|---|---:|---:|---:|---:|---:|---:|
| `PdfCompressor.optimize` (lossless) | 29,152 | 6001 | 2408 | 2315 | **0.39** | 0.96 |
| | 14,475 | 1544 | 693 | 703 | **0.46** | 1.01 |
| `applyRedactions` (one rect, page 0) | 29,152 | 1113 | 331 | 341 | **0.31** | 1.03 |
| | 14,475 | 346 | 143 | 144 | 0.42 | 1.01 |
| `CosCompactor.run`, graph walk only | 29,152 | 843 | 230 | 229 | **0.27** | 1.00 |
| open + `getObject` on every xref entry | 29,152 | 687 | 79 | 77 | **0.11** | 0.97 |
| | 36,605 | 841 | 102 | 103 | **0.12** | 1.00 |
| `getObject` warm, 100 passes | 29,152 | - | 119 | 117 | - | 0.98 |
| Control: text extraction, all 344 pages | 36,605 | 571 | 565 | 558 | 0.98 | 0.99 |

B1/B0 stays within 0.96-1.03 and every B1 range overlaps its B0 range, so the
range check costs nothing measurable. Every run's output length and FNV
matched across all three arms. A separate sweep ran compaction (deflate 0) and
the every-xref-entry load through A and B1 on each of the 252 checked-in test
corpus files and the 53 private ones: 610 of 610 outputs (bytes, or the same
exception) were identical.

Reading the table:

- **Reduce file size** is the headline: 2.2-2.5x at 14k-29k objects, and
  1.2-1.8x elsewhere, where deflate and image work dominate. Optimize compacts,
  then reopens the compacted output, whose object numbers are densely
  renumbered (the worst case for the old key), and walks the whole graph again
  to prune, dedup and subset fonts.
- `CosCompactor.run` at its default deflate level 9 gains 1.2-1.4x; its graph
  walk alone gains 2.7-3.3x. The difference is recompression time the key
  can't touch.
- **Apply redactions** runs synchronously on the UI isolate. On the 29k-object
  document the freeze drops from 1.16 s to 0.38 s.
- The render controls: text extraction is flat. NullDevice interpret of the
  36.6k-object document is 0.92x (the runs do not overlap: A 490-528 ms, B
  455-464 ms). Every `Tf` resolves its font through `getObject`, and by the
  end this document's cache holds about 1k objects, enough for the old
  clustering to cost a few percent. That is below the 1.15x bar this batch
  trusts, so it is recorded as a side effect, not claimed.
- Web: a dart2js build (node) resolves 20k objects and passes the eviction
  checks with the new key. No in-situ web timing was taken. With the old key,
  object numbers at or above 16,384 left dart2js's fast numeric-key path, so
  the web gets a constant-factor lookup win on large documents.

## Tests

`packages/pdf_cos/test/document_test.dart` (group "object cache key"):

- generation-0 keys equal the object number, and a key decodes back to it;
- 4096 sequential object numbers land in more than 4000 of 4096 hash buckets
  (the old key: 726), a deterministic guard against packing the object number
  into the high bits again;
- every packed key is below 2^48;
- `getObject(2^32 + 5, 0)` and `getObject(-1, 0)` do not return object 5
  cached under generation 1 (whose key is 2^32 + 5);
- `3 65536 R`, `4 4194304 R`, `5 4194304 R` and `3 -1 R` each resolve to their
  own object (the first aliased object 4 under the old key, the next two
  aliased each other on dart2js under the first cut);
- an object adopted as 2^32 + 3 resolves, and `3 1 R` still resolves to the
  page.

`packages/pdf_cos/test/updater_test.dart` (group "a junk /Size at or past
2^32"): for /Size 0xFFFFFFFF and 2^32 + 3, on a classic-table file and an
xref-stream file, two `addObject` calls both resolve live and after save and
reopen, and `3 1 R` stays the page.

`packages/pdf_document/test/annotation_editor_test.dart`: `PdfEditor.addSquare`
on a file with /Size 0xFFFFFFFF, 2^32 or 2^32 + 3 survives save and reopen.

`packages/pdf_cos/test/incremental_update_test.dart`: an object cached under
generations 0, 1, 3, 65535, 65536 and 2^22 is evicted for every one of them by
an incremental update, and an untouched neighbour keeps its cache entry. With
the new key and the old `~/ 65536` decoder this test fails. A second test
applies two revisions in place to a file with /Size 2^32 + 3: the first adds
object 2^32 + 3, the second replaces it, and the resolve after the second sees
the new value.

These run on the VM. The pdf_cos suite can't run under dart2js (its fixtures
package imports `dart:io`), so the web cases were checked with a standalone
probe compiled with `dart compile js -O2` and run on node. It covers the junk
generations, both junk /Size values live, reopened, applied in place and
evicted. On the first cut it failed: `5 4194304 R` resolved to object 4, and
the second object added under /Size 0xFFFFFFFF did not resolve. With the side
map, all 17 checks pass.

## Gotchas

- Any code that decodes the key must change with it. There is one site
  (`applyIncrementalUpdate`); the prototype that missed it failed two pdf_cos
  tests.
- Object numbers of 2^32 and more are not valid by the spec, but they are not
  impossible either: the incremental updater allocates them from a junk
  /Size. Don't "optimise" the side map into a guard that returns null.
- Packed keys with a non-zero generation are 2^32 or more, which takes
  dart2js's float-hash path. No in-use object with a non-zero generation
  turned up in a private real-world corpus or the checked-in test corpora.
- One checked-in file has object numbers past 2^32:
  `test_corpora/pdfjs/GHOSTSCRIPT-698804-1-fuzzed.pdf`, whose fuzzed xref
  subsection starts at 4294967296. Nothing references those numbers, and the
  objects at their offsets carry different header numbers, so they resolve as
  dangling, through the side map now, exactly as they did on `main`. Its
  compacted output is byte-identical either way.
- The `tool/perf.sh gate` counters cannot see this: `objectsLoaded` counts
  cache misses, and the miss count is unchanged. Measure a change here with a
  full-graph workload (optimize, compaction, redaction), not the render sweep.
