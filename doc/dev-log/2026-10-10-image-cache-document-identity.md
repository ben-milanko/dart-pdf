# Shared decoded-image cache: key by document, not by object number

**Symptom (Trax).** Open scan A, then scan B from the same scanner: the viewer
and its Pages-panel thumbnail showed A's page under B's title. Every scan from
that scanner is one 3507x2480 JPEG XObject at `5 0 R`.

**Cause.** `PdfImageCache.instance` is process-wide and outlives documents.
`pdfImageContentKey` used `request.sourceReference ?? stream`, and
`CosReference` equality is `(objectNumber, generation)` only. On the
render-worker path (default) image commands come back with the stream bytes
left out and only the reference carried, so `decodeImages`' shared-cache key
was `PdfSizedImageKey(5 0 R, 3507, 2480)` for *both* files and B hit A's
master. The cache doc comment still claimed stream-identity keying.

**Fix.** `pdfDocumentImageContentKey(cos, request)` (image_decoder.dart,
exported) resolves the reference against its own `CosDocument` and keys by
the resolved `CosStream` instance; an unresolvable reference keys by
`PdfDocumentImageReference(cos, ref)` (identity on the document), never the
bare reference. `decodeImages` builds the shared-cache key from it on every
path (sized and unsized). The local path already keyed by that same
xref-cached stream instance (`CosDocument._cache` memoises loaded objects;
an appended revision evicts only the objects it redefines), so worker and local requests for
one image still meet on one entry (#451).

`pdfImageContentKey`/`pdfImageKey` are unchanged: they key the per-render maps
(`decodeImages`' returned map, retained-scene `_images`, `CanvasPdfDevice`,
reflow, vector print), each of which belongs to one page of one document.

The Flutter GPU backend's `_GpuImageCache` (shared by every scene of one
backend instance, so across documents) keyed textures by
`pdfImageContentKey` too; it now uses `pdfDocumentImageContentKey` with the
scene's document.

**Audit, provably per-document:** worker isolates' `PdfImageDecodeCache`
(identity-keyed `CosStream`, replaced on every fresh document in both
`render_worker_isolate.dart` and `render_worker_web_entry.dart`);
`compactTranscriptSourceCommands` (copies the reference, caches nothing);
`PdfPagePreviewCache` (one per viewer, `clear()`ed on any non-revision document
swap, admissions gated on `PdfPage` identity); `PdfThumbnailCache` (one per
`PdfEditingController`). Disk tiers key by `pdfDocumentKey` (a sampled content
hash), unrelated to object numbers.

Tests: `image_decoder_test.dart` group "cross-document cache isolation".
