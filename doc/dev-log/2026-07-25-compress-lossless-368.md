# Lossless file-size compaction on save (#368, layer 1)

## What

`PdfEditor.compress()` rewrites the document into a fresh, smaller PDF and
returns a `PdfCompressionResult` (before/after bytes, object counts, streams
re-deflated, a `compacted` flag). It is the first of #368's independently
shippable layers - the **lossless structural pass**. Image recompression,
font subsetting, and cross-page dedup remain as separate follow-ups.

The pass does three lossless things:

1. **Reachability GC.** A whole-graph copy from the catalog (and `/Info`)
   into a `CosDocumentBuilder` drops every object the tree no longer
   references. Incremental edits accumulate dead objects - each revision
   appends and supersedes - so a live editing session bloats the file
   steadily. Compaction reclaims all of it.
2. **Object-stream + xref-stream packing.** The builder gained a
   `objectStreams: true` mode: non-stream objects pack into compressed
   `/ObjStm` objects (128 per stream) addressed by a PDF 1.5 xref stream;
   streams and the xref stream itself stay top-level. This is what makes the
   rewrite a *win* on modern files rather than a loss - re-emitting a
   1.5-era file as classic uncompressed objects would inflate it.
3. **Re-deflate of uncompressed streams.** A stream stored with no
   compression filter is deflated at level 9 and kept only when that
   actually shrinks it. `FlateDecode` of the result reproduces the stored
   bytes exactly, so decoded content is untouched.

## Where

- `pdf_cos/src/builder.dart` - `build(objectStreams:, deflateLevel:)`; the
  classic table split out to `_buildClassic`, the new `_buildCompressed`
  writes object streams + an xref stream (W `[1 4 2]`).
- `pdf_cos/src/compactor.dart` (new) - `CosCompactor` + `CosCompactionResult`.
  `_GraphCopier` is a boundary-free twin of page extraction's `_PageImporter`
  (follows every reference; a dead object is simply never visited).
- `pdf_document/src/editor.dart` - `PdfEditor.compress()` +
  `PdfCompressionResult`, with the never-larger gate and pending-edit
  inclusion.

## Design calls

- **From-scratch output, no `/Prev`.** Compaction is a rewrite, so it does
  not preserve prior-revision history and it invalidates existing
  signatures. That is inherent (you cannot shrink a file and keep its byte
  prefix), which is why this is an explicit action, never part of `save()`.
- **Encrypted documents are refused.** A faithful rewrite would have to
  re-encrypt (out of scope) or silently drop encryption; the caller is told
  to decrypt first. Same posture as "signing encrypted files is refused".
- **Never larger than the input.** `compress()` compares the compacted
  bytes to the current file and returns the smaller, with `compacted:false`
  when it kept the original (already-objstm files, tiny files where framing
  dominates). So it is always safe to call.
- **Pending edits included.** With unsaved changes it compacts the applied
  snapshot (`open(save())`); with none it compacts the live document
  directly (no reopen).
- **Number identity is not preserved.** Objects renumber densely from 1;
  callers must not assume a compacted object keeps its old number.

## Measured

Round-tripped every `test_corpora` PDF (226 openable, unencrypted): **0
page-count mismatches**, 3.0% aggregate saving. The aggregate is dragged
down by already-compressed image/JPEG suites; the mechanism's reach shows
per group and per file:

| corpus | before | after | saved |
|---|---|---|---|
| pdfjs | 2933K | 2015K | **31.3%** |
| ghent | 104.9M | 102.4M | 2.4% (image-dominated) |
| dartpdf | 7453K | 7394K | 0.8% (already optimized) |

Individual uncompressed-stream files: `calrgb.pdf` 315K -> 19K (93.9%),
`colorkeymask.pdf` 158K -> 2K (98.7%).

The headline case is the editor's own output. A 12-page file through 40
incremental annotation edits bloats **8.8x** (3.4K -> 29.9K); compaction
returns it to 9.7K (**67.6% off**) with all 40 annotations intact.

## Follow-ups (open #368 checkboxes)

Image downsample/recompress (opt-in lossy), embedded-font subsetting,
identical-resource dedup, and the app's "Reduce file size…" action with
ghostscript-style presets. Each layers on top of this pass without changing
it.
