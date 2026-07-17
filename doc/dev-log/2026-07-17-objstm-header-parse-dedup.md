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

Behavior-preserving: both paths parsed the pairs with
`expectInteger()`; the throw-on-bad-header case is still swallowed by the
recovery loop's `try`/`catch` (previously an early `continue`). Recovery
now also warms the `_objectStreams` cache it used to bypass, matching
normal open.

## Tests

`document_test.dart` gains "recovery reuses the object-stream decoder for
the header index" - resolves the deepest compressed object (stream index
2) through a smashed-startxref open, so a regression in index positions
would surface. The existing "recovers compressed objects behind a broken
xref stream" test still covers indices 0/1.

Pairs with #315 if the recovery cluster is ever lifted out of
`CosDocument`.
