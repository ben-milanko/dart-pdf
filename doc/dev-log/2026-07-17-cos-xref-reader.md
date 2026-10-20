# Extract CosXrefReader from the CosDocument god-object

Issue #315. The cross-reference machinery - `startxref` location, section
parsing (classic table vs `/XRef` stream with `/W` widths and `/Index`
ranges), and the newest-to-oldest chain walk - was ~150 lines scattered
through `CosDocument`, entangled with the object cache, encryption init,
and scan recovery. `xref.dart` held only the two pure data classes
(`CosXrefEntry`/`CosXrefSection`) and no behaviour, so "how xref works"
meant reading `document.dart`.

## What moved

`pdf_cos/lib/src/xref.dart` now carries `CosXrefReader(bytes, {shift})`,
pure over a byte buffer:

- `findStartXref()` - the tail `startxref` value (relative to the header).
- `parseSection(offset)` - one section, dispatched on the leading keyword
  (`_parseTable` / `_parseStream`, moved verbatim). Bounds-checks the
  offset.
- `walkFrom(startXref, {stopAt})` - the chain walk: newest-wins
  `putIfAbsent`, `/XRefStm` queued before `/Prev`, a visited-offset set
  guarding `/Prev` cycles. `stopAt` (a section already loaded by the
  caller) prunes the descent - the incremental-update path passes the old
  `startxref` so only the appended sections come back.
- `read()` = `walkFrom(findStartXref())`, returning `CosXref`
  (`entries` + `trailer` + `startXref`).

`document.dart` shrinks to caching/resolution/recovery orchestration:

- `_openFromXref` is three lines around `CosXrefReader(...).read()`.
- `applyIncrementalUpdate` walks with `stopAt: startXref`; `changed` is
  just the returned `entries.keys`. The old code fused the newest-wins
  guard and the eviction set into one `changed` set threaded through a
  hand-rolled walk; now the reader owns the walk and the caller owns the
  eviction. The trailer-merge guard `newStartXref != startXref` reproduces
  the old `newestTrailer != null` exactly (a section is parsed iff the
  append moved `startxref`).

## Gotchas

- `_lastIndexOf` (used only by `findStartXref`) moved into `xref.dart`;
  `document.dart` keeps its own `_indexOf`/`_lastIndexOf`... actually only
  `_indexOf` remains there (header + recovery). Top-level `_name` helpers
  are file-private in Dart, so the small duplication beats widening the
  exported surface.
- The `token.dart` import left `document.dart` (all `CosToken*` use was in
  the moved section parsers).
- `byte_source.dart` has its own parallel *async* xref reader over a
  `PdfByteSource`; out of scope for this issue and left untouched.

## Tests

New `test/xref_test.dart` drives the reader standalone - the issue's
headline win. A bare `/W [1 1 1]` + `/Index [10 2]` stream section proves
range/width decoding without a whole valid PDF; a zero-width type column
defaults to in-use; a self-referential `/Prev` proves the cycle guard
terminates; `stopAt` pruning and header `shift` are asserted directly.
Chain newest-wins reuses `CosIncrementalUpdater` to append a real second
section. Full suite green (`dart test`, `dart analyze`).
