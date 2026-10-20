# ObjStm header-parse dedup (issue #320, candidate 5)

Xref recovery had its own copy of the object-stream header wire-format
parse. `document.dart`'s `_ObjectStream` constructor parses the
"/N `(objectNumber, offset)` pairs, /First offset" header into `_index`,
and `_recover`'s object-stream indexing pass re-parsed the same bytes
inline (`CosParser(decodeStreamData(object))` + a manual
`expectInteger()`/`expectInteger()` loop). A lenience fix to one would
have missed the other.

## Change

- `_ObjectStream` now exposes its parsed pairs via `List<(int, int)> get
  index`.
- `_recover` still decides *which* streams to index (`/Type /ObjStm`
  filter, direct scan definitions win over compressed), but delegates the
  header parse to `_objectStream(number)` and iterates `stream.index`.
  The stream index the recovered entry points at is the position in that
  list, same as before.

Recovery now also warms the `_objectStreams` cache it used to bypass,
matching normal open.

## Leniency (the point of the dedup)

The old inline recovery loop registered each `(number, offset)` pair via
`putIfAbsent` *as it parsed*, so a header that went bad partway still
salvaged the leading compressed objects. Delegating to the
`_ObjectStream` constructor would have regressed that - it built the
whole `_index` up front and threw on the first bad pair, dropping the
entire stream. Rather than special-case recovery, the leniency now lives
in the one parse location: the constructor catches `CosParseException`
per pair and `break`s, keeping the pairs parsed so far. Both the normal
compressed-object path and recovery inherit it - exactly the
"fix-it-once" property the dedup was for. `document_test.dart` gains "a
truncated object-stream header still salvages leading objects" to lock
this in.

## Tests

`document_test.dart` gains "recovery reuses the object-stream decoder for
the header index" - resolves the deepest compressed object (stream index
2) through a smashed-startxref open, so a regression in index positions
would surface. The existing "recovers compressed objects behind a broken
xref stream" test still covers indices 0/1.

Pairs with #315 if the recovery cluster is ever lifted out of
`CosDocument`.
