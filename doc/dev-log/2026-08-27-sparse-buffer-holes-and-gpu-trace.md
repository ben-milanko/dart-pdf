# 2026-08-27 — progressive-open holes, GPU route/trace devtools, Hand default, middle-drag pan

Five threads in one session. The big one is a multi-second UI freeze that
turned out to be the progressive-open contract meeting a viewer that reads
outside it.

## The 219 MB pack froze for 11.6 s on open

A real correlation pack (83 A3 pages, 219 MB, pypdf) beachballed the macOS app
on open. `--dart-define=PDF_PERF_LOG=true` on a profile run named it in one
line:

```
[perf 12675] JANK build=11619.1ms raster=7.3ms total=11629.5ms rss=368MB
```

One frame, 11.6 s of *build*, and no interpret/raster line inside it. A CPU
profile pulled from the VM service (`getCpuSamples` over the run's window)
gave the stack:

```
RenderSliverFixedExtentBoxAdaptor.performLayout
  SliverMultiBoxAdaptorElement._build → SliverChildBuilderDelegate.build
    _PdfViewerState._formFieldRects → PdfPage.annotations
      CosDocument.getObject → CosParser.parseIndirectObject → CosLexer.nextToken
        CosLexer.skipWhitespaceAndComments   ← 8515 of 12873 samples
```

### Root cause

`PdfSourceLoadOptions(firstPaintPages: 1)` — what `EditorScreen._openProgressive`
uses — assembles a **sparse** buffer: header, xref chain and the first page's
render closure are fetched, everything else is left as zeros. The loader's doc
comment states the assumption plainly: "free space and dead revisions are left
as zeros *the parser never reads*".

The viewer reads them. Building a page tile calls `_formFieldRects(index)` →
`PdfPage.annotations`, and annotations are not in any page's first-paint
closure. So the parse starts at an xref offset inside a hole — and **0x00 is
PDF whitespace**, so `skipWhitespaceAndComments` walks forward until the next
populated byte, up to hundreds of megabytes, per object, during layout. The
failed parses then trigger the `N G obj` rescue scan across the whole 219 MB
buffer (`objectRescueScanBuilt` in the trace).

Headless repro (`PdfDocument.openSource` + the app's options, then read what
the sliver reads):

```
page 0 annotations=218ms   count=3
page 1 annotations=13213ms count=0     ← 65 annotations in the real file
page 4 annotations=573ms   count=5
```

Note the second number: it was not only slow, it was *wrong* — a hole answers
"no annotations" rather than "not fetched".

### Fix: the document knows its holes

`_ProgressiveLoader` already merges the ranges it fetched (`_present`). Those
now travel into `CosDocument.open(bytes, populatedRanges:)` (flat sorted
`[start, end)` pairs, null = whole file), where:

- `_parseIndirectAt` refuses an offset that lies in a hole — the reference
  dangles, exactly as a not-yet-fetched compressed object already did;
- a parse that starts in a populated run is bounded to that run with
  `Uint8List.sublistView` (a view, not a copy), so an object at the tail of a
  fetched range cannot walk into the hole after it;
- `_scanObjectHeaders` skips holes, so the rescue scan costs the fetched bytes
  (7 MB here) instead of the file (219 MB).

Same repro after: **13213 ms → 0 ms**, whole 12-page sweep 16 s → 34 ms, same
answers. Tests in `pdf_cos/test/byte_source_test.dart` ("sparse buffers know
their holes"): a hole dangles instead of scanning, a hole stays authoritative
even when real bytes sit inside it, and a parse cannot run off the end of its
range.

### …and the map has to follow the buffer, not the document

That fixed the repro and changed nothing in the app: still an 11.5 s frame,
still the same stack. A `cos open` diagnostic line (kept - it is worth having)
showed why:

```
[perf 538] cos open bytes=219314443 sparse spans=110    ← the preview document
[perf 558] cos open bytes=219314443 whole-file          ← what the viewer reads
```

The app paints a preview tab with `PdfReader(bytes: tab.previewBytes!)`, and
`PdfReader` opens **its own session** over those bytes
(`PdfShellSessionLifecycle` → `PdfEditingController` → `CosDocument.open`). The
carefully-loaded sparse document is used for nothing but its byte buffer, and
a `Uint8List` cannot carry "these are the parts of me that hold real bytes".

So sparseness now belongs to the buffer: `cosSparseBufferRanges`, an `Expando`
the loader stamps and `CosDocument.open` consults when no ranges are passed.
Every later open of that exact buffer inherits the map - no signature change in
the four widgets between the loader and the parser, and nothing to remember at
a future call site.

Measured in the app, same document, same machine:

| | before | after |
|---|---|---|
| worst frame during open | 11 619 ms | 86 ms |
| page 1 on screen | ~10.4 s | 0.6 s |

The render worker still opens its own *copy* of a sparse buffer whole-file (a
copy is a different object, so it inherits nothing). It is harmless here - a
worker records page content, which is exactly what the first-paint closure
fetched - and it is off the UI thread either way. If a worker-side hole scan
ever shows up, the init message is where the ranges would go.

No viewer change was needed in the end: with holes cheap, the layout-time
`annotations` read is ~0 ms, and `_visibleAnnotCache`/`_fieldRectCache` are
already cleared on the document swap, so the preview's empty answers never
outlive the preview.

## GPU diagnostics in the devtools

- `pdfDebugShowGpuRasterRoutes` (the per-page GPU/Canvas route overlay from
  #853) was only reachable from the example app's menu. It now has a switch in
  the app's F12 panel, in the Tile raster backend section, persisted with the
  other devtools options (`gpuRouteOverlay`).
- `PdfPerfLog` gained the GPU lines a fallback diagnosis actually needs:
  `tile gpu compile` (units/draws/clips/textures/bytes/elapsed — the per-scene
  cost that used to show up only as a gap before the first tile),
  `tile gpu raster fallback` (a scene that was *accepted* and then fell back at
  raster time — previously invisible in a trace), and pipeline/scene warm-up
  completion + failure lines.
- `FlutterGpuTileBackendStats.logPerfSummary(reason)` emits one lifetime-totals
  line; the app brackets every trace with it (`trace-start` / `trace-end`) and
  stamps one on each backend switch, so an exported trace carries the GPU
  totals without the reader having to open the panel.

## Documents open in Hand mode

`DocumentTab.document` now starts its session in `activateHandMode()`: a mouse
drag pans instead of starting a text selection. Text selection is one toolbar
click away. `selection_copy_action_test.dart` leaves Hand mode first, the way
the toolbar does.

## Middle-button drag pans

Flutter's drag recognizers accept the primary button only, so a middle drag
reached no recognizer at all — the gesture was never implemented, not broken.
The viewer's pan/selection `PanGestureRecognizer` now allows
`kMiddleMouseButton`, and `_onSelectionStart` treats a middle-button drag as a
temporary hand: it grabs the page past whatever the primary button would have
meant there (text, a stroke, a marquee) without disarming the armed tool.
