# 2026-11-15 - A Type3 glyph cell carries its image list

The lead from `2026-11-14-type3-per-glyph-cost.md` read "each stamp still
allocates a `PdfDrawTiledCellCommand` and two `Float64List(1)`". Profiling
the record of `type3-text-6p.pdf` (TeX PK fonts: 35,128 stamps of 156 cells)
put the cost somewhere else.

## What it was

| share of record | where |
|---|---|
| 22% | `_stampType3Cell`, everything below it |
| 17% | `RecordingPdfDevice.drawTiledCell` |
| 12% | its `walk` - re-finding the cell's images |
| 4.5% | the two `Float64List(1)` |

A recorder lists a cell's images in `imageRequests` again for every stamp:
the editor's transcript cache and image pairing walk the wire transcript and
that list in step, so the per-occurrence listing is load-bearing
(`render_worker_transcript_cache.dart` checks it). It found them by walking
the cell's commands through a local closure - once for a tiling pattern,
once *per glyph* for Type3 text.

## What it is

- `PdfDrawTiledCellCommand.cellImages` (optional): the cell's images,
  flattened, when whoever built the command already has them. Null means
  "walk the cell", which is always correct - a decoded record, a patched
  cell and a tiling pattern all leave it null.
- `_Type3Cell.images` flattens a glyph cell once, lazily, and every stamp of
  it passes that one list.
- The walk itself is one shared function (`addCellImageRequests`,
  cell_image_requests.dart, not exported) used by the recorder, the streaming
  writer and the flattening - one definition of "the order a cell's images
  are listed in".

The listing is unchanged: same requests, same order, same count. Nothing on
the wire changes.

## Measured

Record of all six pages, AOT, the two builds alternated (ABBA x 3, 8 s each):

| | min | median |
|---|---|---|
| main | 11.3 - 12.6 ms | 17.4 - 18.5 ms |
| this | 7.6 - 11.0 ms | 14.5 - 16.4 ms |

About 10-12% on the median. Other documents do not move: nothing else stamps
cells per glyph.

Two things measured and not shipped:

- Replacing the closure with a plain loop, alone: the profile said 12% -> 9%,
  and a JIT A/B "confirmed" 8% - until the order of the two runs was swapped
  and the sign flipped with it. Whichever build ran first won. That is why
  the numbers above come from prebuilt AOT binaries in ABBA order.
- The two `Float64List(1)` per stamp (4.5%): removing them needs a new
  command type through a dozen consumers (canvas, region index, retained
  scene, transcript cache, codec). Not worth it for this.

## Still there

`imageRequests` holds one entry per stamp - 35 k entries for 156 distinct
images on this document - and `decodeImages` keys and de-duplicates every one
of them on the UI side. Listing a shared cell's images once would fix both
ends, but it changes the contract the transcript cache verifies, so it is its
own change.
