# 2026-11-15 - A stamped cell's images are listed once

Follow-up to `2026-11-15-type3-cell-image-list.md`, which left this open:
"`imageRequests` holds one entry per stamp".

## What it was

A recorder (`RecordingPdfDevice`, `PdfStreamingCommandWriter`) keeps
`imageRequests`, the images its commands draw. For a tiled cell it listed the
cell's images again on every stamp. A tiling pattern is stamped once per
fill; a Type3 glyph cell is stamped once per letter. `type3-text-6p.pdf`
(TeX PK fonts) listed 17,424 requests for 78 distinct images.

Everything that walks the list paid per entry. The one that matters is the
editor's `decodeImages`, which keys and de-duplicates every request before it
decodes anything - on the UI isolate, per page render, also when every image
is already cached.

## What it is

A cell's images are listed the first time the cell is stamped into a
recorder, and not again. "A cell" is its command list, by identity
(`addStampedCellImageRequests`, cell_image_requests.dart).

That is not a new rule - it is the wire codec's. `_writeTiledCellReference`
writes a cell's body, images included, on its first stamp, and a
back-reference on every later one. So the listing and a wire transcript's
images are now the same sequence, image for image:

- `compactTranscriptSourceCommands` (render_worker_transcript_cache.dart)
  pairs the two. It used to step over a shared cell's repeated entries and
  verify them; now a repeated cell consumes nothing. Its final count check is
  what catches a listing that does not match the wire (it returns null and
  the caller keeps the source graph).
- `decodeImages` already de-duplicated; it just has nothing left to skip.
- `PdfRetainedScene`'s retained-pixels list no longer holds a glyph's request
  once per letter.

### The per-stamp check had to be free

The first version asked an identity `Set` "have I listed this list?" on every
stamp. That made recording the Type3 document about 10% slower (AOT, ABBA:
median 11.6-12.2 ms against 8.5-11.2) - it gave back what the previous
change had won.

So a stamp of a shared cell carries a marker: `PdfDrawTiledCellCommand.share`
(`PdfTiledCellShare`). The interpreter gives every stamp of one Type3 cell
the same one, and it remembers which recorder listed it last, so a repeat is
one comparison. The set is still the authority - a marker that points
elsewhere falls through to it - which is what makes these hold:

- a recording replayed into a second recorder lists the same images;
- two recorders fed the same stamps alternately each list them once;
- the same list stamped with and without a marker is still one cell.

`PdfDrawTiledCellCommand.cellImages`, added a day earlier in #1312, is gone:
with the walk happening once per cell there is nothing to precompute. It
could also not have stayed correct - a flattened list hides the nested cells
inside it from the "seen" set.

## Measured

`decodeImages` over all six pages of `type3-text-6p.pdf`, image cache warm,
`flutter test` on the VM, change and `main` alternated:

| | requests | min | median |
|---|---|---|---|
| main | 17,424 | 34.6 - 34.8 ms | 36.4 - 37.9 ms |
| this | 78 | 2.2 - 2.4 ms | 4.0 - 4.6 ms |

About 5.5 ms a page of UI-isolate time, on every render of such a page.

Recording, AOT, ABBA x 3: 6.4-8.3 / 9.7-11.5 ms against main's 6.9-8.5 /
8.6-11.4 (min / median) - no change. Serialize unchanged; the wire bytes are
identical.

Not measured: a real-Chrome run. No web scenario renders a Type3 document,
and adding one is its own change.

## Scope

Only documents that stamp one cell many times change: Type3 fonts whose
glyphs draw images. A tiling pattern's cell is a fresh list per fill, so its
listing is what it was.
