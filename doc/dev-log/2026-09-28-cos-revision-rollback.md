# COS revisions: in-place updates on recovered documents, and rollback on undo

Two costs at the COS layer made one class of revision far more expensive than
the rest:

1. **Edits on an xref-recovered document re-opened it every time.**
   `CosDocument.applyIncrementalUpdate` refused any document with
   `startXref <= 0`. So after each edit, the UI isolate and every native render
   worker re-ran the full-file recovery scan, and the worker also started its
   image and page caches cold. That was 196-202 ms per edit on a 78 MB drawing
   and 74-79 ms on a 24 MB real-world file (AOT). The scan itself was two
   passes: byte-at-a-time for `obj`, then a naive search for `trailer`.
2. **Every undo re-opened each native worker's document.** An undo delta has
   `baseLength < doc.cos.bytes.length`. The worker's in-place path only took
   `baseLength == doc.cos.bytes.length`, so it re-opened the prefix with a new
   `PdfImageDecodeCache` and evicted every page's bin, suspended-record and
   text caches. Undoing a move on a raster-underlay page then re-decoded
   221 MB of Flate: about 620 ms before the page came back.
   `2026-09-26-worker-revision-in-place.md` listed this under "Not done".

## Recovered documents fold in place (`pdf_cos` document.dart, xref.dart)

The guard was never needed for our own saves. `CosIncrementalUpdater` writes
`/Prev = document.startXref`, which is 0 on a recovered document. The walk
`walkFrom(newStartXref, stopAt: 0)` stops exactly there. The appended entries
then override the recovered ones, the same "last definition wins" rule a
recovery of the new bytes applies. After the first fold, `startXref` is our
section's real offset, so later edits chain `/Prev` to it and fold like any
intact document.

The guard is replaced by two narrower refusals, for the cases a from-scratch
open would read differently. Those still throw, and the caller re-opens:

- `walkFrom(..., floor:)`. On a recovered document the walk may not parse a
  section below the old bytes. A foreign `/Prev` into the broken original
  chain would pull that chain's entries over the recovered ones. A fresh open
  would follow the chain instead of recovering, if it parses.
- An append that parses no section (`parsedSection == false`). There is
  nothing to fold, and a re-open would rescan the appended bytes.

Semantics to know:
- A fresh open of such a file still recovers, and still says
  `startXref == 0`. The in-place document knows its real chain head. The
  objects are identical (0 diffs, below). Only `startXref` differs, and the
  file on disk is unchanged. It carries `/Prev 0` exactly as before.
- One precedence quirk goes the other way. When `_recoverTimed` rebuilds the
  trailer, the doc-level keys of old `/Type /XRef` stream dictionaries override
  every `trailer` dictionary, including the one our appended section carries.
  If an edit changes `/Info` through `_trailerOverrides` on a recovered file
  whose old revisions were xref streams, the in-place document shows the new
  `/Info` and a from-scratch recovery shows the old one. This only affects
  recovered files. The in-place answer is the right one.

**One-pass scan.** `_scanObjectHeaders` is now one Horspool pass over a 3-byte
window for both keywords (`obj`, and the `tra` of `trailer`). The window's
last byte says how far the next possible match can start (`_scanSkip`: o/t 2,
b/r 1, j/a 0, anything else 3), so most bytes are never compared. `trailer`
offsets are collected in the same pass (optional `trailers:` list).
`_parseScannedHeader`, the lazy bad-offset rescue, uses the same scan without
it. Where the old loop stepped `i = populated[hole*2] - 1` and relied on its
`i++`, the new one assigns `populated[hole*2]` directly.

Kept out on purpose:
- Writing a full xref on the first save of a recovered file. That is a
  file-format change, and any entry it missed would resolve to `CosNull` with
  no rescue.
- Skipping stream bodies by `/Length`. That changes which headers recovery
  finds, so it is not a pure speedup.

## Rollback journal (`CosDocument.rollbackTo`, `PdfDocument.rollbackTo`)

`applyIncrementalUpdate` pushes an `_AppliedUpdate` for each fold. It holds:
- the previous byte length and `startXref`;
- the previous trailer, by reference: the merge builds a new dictionary, so
  the old one stays that revision's;
- the xref entry each redefined number had, with null meaning absent;
- the populated-range list's length and last value. A fold only extends the
  last range or appends ranges, so truncating back is an exact restore at
  O(1) per entry.

The journal is capped at 256 entries (oldest dropped).

`rollbackTo(length)` returns `({Set<int> changed, int steps})`, or null
without touching anything when:
- the length was never journaled (opened there, or more than 256 updates
  back), or
- `CosXrefReader(prefix).findStartXref()` differs from the journaled
  `startXref`: the prefix is not the revision that was journaled.

The current length is `steps: 0`. It restores the entries newest-first, so a
number several undone revisions redefined ends at its oldest value. It also
restores the trailer, `startXref` and ranges (re-keying
`cosSparseBufferRanges` on the new view), and views `bytes` down to `length`.
Then it evicts through `_evictRedefined`, the block
`applyIncrementalUpdate` used to inline: the packed cache via `_objectNumberOf`
(never `key ~/ 65536` since #972), `_unpackedCache`, `_reverseCache`,
`_objectStreams`, and `_scannedHeaders = null`. Finally it bumps `_revision`.
The #963 colour context keys on `cos.revision`, so a rollback must advance
it rather than restore the old number. The encryption handler stays, as it
does across a fold.

A rollback onto a recovered base normally fails the `findStartXref` check,
because the broken prefix has no `startxref`, and the caller re-opens. If the
broken file happens to declare `startxref 0`, restoring is exact anyway.

## Worker undo (`render_worker_isolate.dart` `'update'`)

When `baseLength <= doc.cos.bytes.length`:
1. Roll back to the base if it is below the live length (`PdfDocument.rollbackTo`).
2. Fold the tail if it is non-empty.
3. Keep `imageCache`. It is keyed by `CosStream` identity, and untouched
   streams keep their instance. Undone ones are evicted from the COS cache, so
   their entries are never hit again and age out under the cache's budget.

`null`, or a throw from either step, falls back to a re-open. The fallback:
- sets `cosSparseBufferRanges[live] = nextRanges`;
- tries `doc.openAppended(live)` first, so an encrypted file does not derive
  its keys again in every worker (#975 did this for the controller);
- falls back to `PdfDocument.open(live, populatedRanges:)`;
- always starts a fresh image cache.

**Deviation from the plan's eviction rule.** The plan said: evict the update's
`changedPages` only when the tail is empty and exactly one step was undone,
otherwise evict wholesale. That rule is wrong in one coalesced shape. Say the
worker holds A, B, the host undoes B, stamps C, undoes C, and syncs once. The
worker rolls back one step, undoing B, with an empty tail, but the update
names C's pages. The update's pages describe the host's last transition. They
match the revision the worker undid only when nothing was coalesced.

So the worker keeps its own record: `_AppliedRevisionPages`, a list of
(base length, changedPages) per fold, parallel to the COS journal.
- A rollback pops the entries above the base, and their union is the undone
  pages. It falls back to all pages if a count doesn't match `steps` or an
  entry was null.
- The stale set is that union plus the update's own pages.
- In the common one-undo case this is exactly the update's pages, so untouched
  pages keep their bin, text and suspended caches.

The new test for that shape fails under the plan's literal rule, because page
1's cached text still says BRAVO.

Also new: an update whose base equals the live length with an empty tail
("unchanged": the host coalesced an edit and its undo) no longer re-opens.
The worker never saw that revision.

**Recovered documents and undo.** The controller's undo re-opens, and on a
recovered file that recovers again (`startXref` 0). Its next edit therefore
writes `/Prev 0`. A worker that rolled back in place knows a real chain head,
so that fold misses its `stopAt` and falls back to a re-open. The recovery
cost moves from the worker's undo to the edit after it, so it is not a
regression. In the random walk below it accounts for all 16 worker
append-reopens.

A redo after an undo on a recovered file also re-opens on the UI isolate: the
undo's re-open recovered, and the redo's chain reaches our earlier section
below the new floor. Base re-opened on every transition anyway.

A possible follow-up is to let a document whose journal bottom was a recovery
treat offset 0 as a second stop. Its state at any journaled revision equals a
recovery of that prefix. Not done here, because recovered files are rare.

## Numbers (AOT, `CLOCK_THREAD_CPUTIME_ID`, interleaved against origin/main)

Recovered documents, per-edit reload (add a square, save, then fold or
re-open), 4 edits. Base re-opens 4/4; the branch folds 4/4:

| file (startxref smashed) | base | branch |
| --- | ---: | ---: |
| 78 MB synthetic CAD image sheet (1.4k objects) | 196-202 ms | 0.03-0.05 ms |
| 24 MB real-world 62-page file | 74-79 ms | 0.05-0.06 ms |
| 8.7 MB real-world file, 36.6k objects | 140-143 ms | 0.03-0.04 ms |
| `test_corpora/dartpdf/broken-startxref.pdf` | 0.5-0.6 ms | <= 0.01 ms |

Every object of the in-place document serializes identically to a fresh open
of the final bytes (0 diffs on all four).

Recovery open, 5 interleaved rounds, medians of 7 opens each:

| file | base | branch | ratio |
| --- | ---: | ---: | ---: |
| 78 MB byte-heavy | 195.4 ms | 109.4 ms | 0.56x |
| 24 MB real-world | 70.4 ms | 43.3 ms | 0.61x |
| 36.6k-object file | 137.5 ms | 127.5 ms | 0.93x |

On the object-heavy file, recovery's two `getObject` passes dominate, and the
scan is a small part of the total. The recovered xref entries and trailer are
identical to base on all 305 files of `test_corpora` plus a private
real-world corpus with every `startxref` smashed (298 recover, 7 fail in
both).

Worker undo: the worker's update path on each tree, followed by the
re-record of the changed page with the worker's record parameters (decoded
images, ratio 2, its decode cache). A move of one element, then undo. The run
is 5 rounds x 5 reps, and each cell is the median undo + re-record:

| document | base (re-open) | branch (rollback) | |
| --- | ---: | ---: | ---: |
| raster-underlay-1p, content undo | 621.1 ms | 23.4 ms | 26.5x |
| raster-underlay-1p, annotation undo (thumbnail re-record) | 648.6 ms | 24.2 ms | 26.8x |
| scan-book-12p | 11.3 ms | 2.63 ms | 4.3x |
| image-scan-4p | 2.50 ms | 0.42 ms | 6.0x |
| 12 MB hybrid-xref manual (private) | 17.2 ms | 2.19 ms | 7.9x |
| AES-256 plan set (page 1) | 19.5 ms | 6.78 ms | 2.9x |
| plan-set-16p (vector) | 6.48 ms | 5.59 ms | 1.16x |
| text-report-40p | 0.73 ms | 0.51 ms | sub-ms |

The counters are deterministic:
- **Base:** the re-open loads 8-313 objects and re-inflates everything the
  page draws (221 MB of Flate on the raster underlay, 608 ms of image decode).
  On AES-256 it also re-derives the keys (11 ms).
- **Branch:** every rollback reloads exactly 1 object (the page), decodes 0
  Flate bytes and 0 images, and opens no document.

As the earlier verification found, pages whose decoded images overflow the
64 MB cache gain nothing: the warm path re-decodes too. Web workers restart on
every revision, so there is no change there.

## Safety

- The random walk from the backlog verification, in worker mode. Edits run on
  the controller's document; the worker takes bytes-only updates, rolling back
  on undo and re-opening where it must. After every step, each xref object,
  the trailer, page transcripts and annotation counts are compared with a
  fresh open of the same prefix.
- Coverage: 22 documents x 3 seeds, 1,196 edits, 998 undos, 168 redos,
  16 editor ops. The documents include classic, xref-stream, hybrid, forms,
  Type0/Type3, junk-prefix, AES-128, AES-256, a recovered file and a private
  12 MB hybrid-xref manual.
- Result: `workerMismatch = 0`. 969 undos rolled back in place. The 29
  re-opens were all rollbacks to the recovered fixture's base, refused by the
  guard as designed.
- The harness now compares `startxref` only when the fresh open was not
  itself a recovery.

## Tests

- `pdf_cos/test/incremental_update_test.dart`, group "on a recovered
  document":
  - Recovered classic and xref-stream/object-stream files fold an edit. The
    result has `startXref > 0`, every object and the trailer match a fresh
    open, and a second edit chains `/Prev` to our section.
  - Another writer's `/Prev 0` section is accepted.
  - A section reaching into the recovered bytes and an append with no section
    are refused. Removing the hardening fails both.
- `pdf_cos/test/document_test.dart`:
  - Recovered entries and trailer equal the intact chain's on four fixtures.
  - A 120-round randomized differential against a plain regex +
    `indexOf('trailer')` oracle, half the rounds sparse. The token set is
    biased toward keyword fragments (`tra`, `ttrailer`, `trailertrailer`,
    `oobj`, a header at the buffer's end).
  - Each of four seeded scan bugs (wrong skip for `r`/`b`, `i += 8` after
    `trailer`, off-by-one hole jump) fails it.
- `pdf_cos/test/rollback_test.dart`:
  - one and several steps, including untouched objects keeping identity and
    the revision bump;
  - unjournaled lengths and the no-op current length;
  - the `startxref` guard;
  - the 256 cap;
  - sparse ranges;
  - an unpacked number past 2^32;
  - AES-128 with the same handler;
  - re-applying over bytes a different edit rewrote (the worker's in-place
    buffer);
  - a recovered base.

  `expectSameAsFreshOpen` compares xref entries, not only loaded objects. A
  stale offset past the prefix still loads through the lenient header rescan,
  which hid a reversed restore order until the entries were compared.
- `dart_pdf_editor/test/render_worker_revision_test.dart`, group
  "rollback on undo". The workers report how they applied each update
  (`debugReportPdfRenderWorkerRevisions` /
  `debugPdfRenderWorkerRevisionReports`, read at spawn like the #220 cancel
  hook):
  - two undos in one sync;
  - the undo / edit / undo coalesced shape above;
  - an image page whose undo re-record makes no decoded-image cache miss.
    Resetting the cache on rollback fails it.

  The earlier coalesced undo + edit test now rolls back and appends, and
  still matches a fresh worker.

## Follow-ups

- `PdfEditingController._tryApplyIncrementalUpdate`'s doc comment still says
  recovered documents re-open. Since the first change here they fold. It was
  left alone because another branch owns `editing_controller.dart`.
- Controller-side rollback stays deferred. Two gaps from the backlog
  verification remain unfixed. `PdfEditor.stampPage` mutates a shared nested
  `/Font` dictionary without `markChanged`. An edit that throws after staging
  leaves unsaved mutations in the live graph. Today's undo re-open clears
  both; a rollback would keep them.
- The "offset 0 as a second stop" idea for documents with a recovered base
  (see above).
