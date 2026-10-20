# 2026-07-17 — Share the file-tail framing between builder and updater (#318)

Branch `claude/github-issue-318-wuprcy`. From the 2026-07-16 architecture
review's "also noted" list. `CosSerializer` deepened object serialization but
stopped at the object level; the *file-container* framing — the classic xref
table, the trailer, and the `startxref`/`%%EOF` epilogue — was re-implemented
in two places.

## The duplication

Both `CosDocumentBuilder.build` (`builder.dart`) and
`CosIncrementalUpdater.save` (`updater.dart`) independently emitted:

- the `NNNNNNNNNN GGGGG n ` in-use entry encoding (offset padded to ten,
  generation to five);
- the `0000000000 65535 f ` object-0 free-list head (builder only);
- the `xref` header and consecutive-run subsections;
- `trailer` + serialized dict;
- `startxref\n<offset>\n%%EOF\n`.

Each also carried its own `_writeText(BytesBuilder, String)`. The updater's
`_runsOf` (consecutive-number run grouping) was sidestepped by the builder only
because a from-scratch file always writes a single `0..N` run.

## The fix

New `CosXrefTableWriter` (`xref_writer.dart`), exported from `pdf_cos`, owns the
framing:

- `runsOf(sorted)` — the run grouping, now shared with `_writeXrefStream` too
  (the stream's `/Index` needs the same runs), so `_runsOf` is deleted.
- `writeTable(offsets, generationOf, {includeFreeHead})` — `xref` + one
  subsection per run. `includeFreeHead` prepends object 0 as the free head; it
  is the *only* structural difference between the from-scratch and incremental
  tables. Modelling the builder as "the incremental case with an empty prefix"
  (the issue's framing) is exactly this flag.
- `writeTrailer(dict)` — `trailer` + dict + `\n`. Kept **separate** from
  `writeTable` because the builder hashes the just-written table bytes into
  `/ID` (§14.4) *before* it can compose the trailer.
- `writeEpilogue(xrefOffset)` — `startxref`/`%%EOF`, shared by the table and
  the xref-stream branch of `save`.

Trailer *contents* stay per-writer (the builder computes an md5 `/ID`; the
updater copies `Root/Info/Encrypt/ID`, sets `/Prev`, applies overrides) — the
writer only frames a dict it is handed. Output is byte-identical to before: the
builder's old sequence `trailer\n<dict>\nstartxref…` is just
`writeTrailer` + `writeEpilogue` back to back.

## Tests

The framing is now asserted **once**, directly, in `xref_writer_test.dart`
(free head, entry encoding, run splitting with a non-zero generation, trailer,
epilogue, `runsOf`). `builder.dart` — which had **no test at all** — gets
`builder_test.dart` for free: object numbering, a reopenable round-trip, the
shared from-scratch framing, and caller-supplied `/Info`/version. Existing
`updater_test.dart` and the pdf_document suites still pass unchanged.

Related: #315 is the read side of the same concern.
