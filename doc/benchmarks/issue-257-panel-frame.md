# Issue 257 sidebar-frame benchmark

`PdfSidebarPanelFrame` owns width/clamping/persistence, dock and sheet
geometry, grip and close policy, and scrollbar placement/clearance. Annotation,
bookmark, search, properties, and thumbnail content/controllers remain separate.

## Build and resize timing

Run from `packages/dart_pdf_editor`:

```sh
PDF_BENCHMARK_PANEL_FRAME=1 \
  fvm flutter test test/benchmark_panel_frame_test.dart --reporter expanded
```

Detached `23381f4` baseline versus this branch, nine trials after warmup:

| revision | dock/sheet build | resize frame |
| --- | ---: | ---: |
| baseline | 2,702.24 us/update | 1,089.97 us/frame |
| shared frame | 2,497.44 us/update | 767.92 us/frame |

The shared frame was 7.6% faster for repeated dock/side/sheet builds and 29.5%
faster during the synthetic resize drag. This is consistent with moving resize
state below the content panel state rather than rebuilding the panel owner.

## Behavioral performance guards

- width persistence is called exactly once at drag end (frame test)
- scroll controllers remain owned by panel content; the frame does not listen
  to scroll ticks
- the existing thumbnail test still asserts that an edit re-rasterizes only
  the page it touched
- existing shell tests cover toggling docked panels and switching to/from
  bottom-sheet layouts
- existing long sidebar/search/bookmark list tests keep row and scrollbar
  behavior at the panel-specific seams

The complete package test suite remains the final regression gate.
