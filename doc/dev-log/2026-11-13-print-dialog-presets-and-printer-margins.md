# Print dialog: smoother preview, named presets, printer margins

Three asks from Windows use of the print dialog
(`dart_pdf_printing/lib/src/print_preview_dialog.dart`): it felt janky, print
preferences should be savable under a name, and the preview should show the
edge the printer can't reach (as Bluebeam does).

## Jank

What the dialog did on every keystroke or dropdown change:

- **Composed the preview sheet inside `build`.** `_sheet()` ran
  `preparePrintDocument` + `PdfDocument.open` synchronously while building.
  Measured on the VM (JIT): 3-6 ms for `plan-set-16p`, ~30-40 ms for the Ghent
  CMYK sheet. Now `_sheet()` only records what it wants and composes in a
  post-frame callback (`_compose`), once per frame however many settings
  changed; the previous sheet stays on screen meanwhile.
- **Interpreted the page on the UI thread.** `PdfPageRenderer.renderImage`
  walks the content stream locally. Each composed sheet now gets its own
  `PdfRenderWorker.startUncached(bytes)` (the previous one is disposed); the
  worker records, the UI only replays + rasterizes. UI-thread time to build
  the picture, warm runs: Ghent CMYK ~155-180 ms -> ~17 ms, `plan-set-16p`
  ~36 ms -> ~13-17 ms. A superseded request returns before replay and never
  falls back to the local render. Native only (`_offThreadRenders`): a Web
  Worker boots a ~1 MB script, too slow to start per settings change.
  "Get window" renders the source document through one dialog-lifetime
  worker (`_workerForSource`).
- **Blanked / stretched between renders.** `_PagePreview` keeps the last image
  at its *own* proportions until the new page lands (`_imageOf`/`_imageSize`),
  with a progress mark that only fades in after 250 ms (`_DelayedProgress`).
  Region dragging is enabled only once the shown image is the current page.
- **Printer panel collapsed and regrew.** Choosing a printer nulled
  `_printerSettings`, so the colour/duplex/tray dropdowns vanished and came
  back, and two progress bars popped in above them. Now the previous controls
  stay (disabled, 60% opacity, from `_shownDestination`) and both loads share
  one fixed 4 px progress slot. Print stays disabled until the driver answers
  (`_destination` is still null then), and an error still clears the controls
  so a stale destination can never be printed to.

`PrintPreviewDialog.debugRenderWorkerEnabled` is the test seam (like
`PdfViewer.debugAutoRenderWorkerEnabled`): a real isolate never completes
under the widget-test clock, so the pending mark animates forever and
`pumpAndSettle` times out. Both `dart_pdf_printing/test` and `app/test` now
have a `flutter_test_config.dart` that turns it off. **Any other host whose
widget tests open this dialog needs the same line.**

## Named presets

`PrintPreferences` gained `presetNames`, `preset(name)`, `savePreset`,
`deletePreset`, `selectPreset` and `activePreset`, stored in the same
SharedPreferences JSON under `presets` / `activePreset`. A `PrintPreset` holds
the document-independent settings (same encoding as the last-used settings,
`_encodeSettings`/`_decodeSettings`) and, optionally, a `PrintDestination`
(printer + colour/duplex/tray). Page ranges and crop windows are never part of
a preset. `PrintPreset.matches` drives the "changed since saved" hint.

UI: a Presets row at the top of the options (dropdown, save, delete). Save
opens `_SavePresetDialog` (trimmed name, "replaces" hint, and on Windows an
"also select <printer>" checkbox). Applying a preset re-syncs the number
fields (`_syncNumberFields`, which Defaults now shares) and, if it names an
installed printer, selects it with the preset's options winning over that
printer's last-used ones (`_selectPrinter(preferred:)`). On open, the active
preset is selected but the last-used settings load as before, so drift shows
as "changed".

## Printer margins (Windows)

New channel method `printableArea {printer, color, duplex, tray, width,
height}` -> `{supported, left, top, right, bottom}` (points, content-up frame).
`NativePrinter::QueryPrintableArea` builds the exact DEVMODE a direct job
would use for that sheet (LoadMode -> ApplyOptions -> Merge ->
SetPreparedSheet -> Merge, mirroring Begin + `configure_sheet`), opens an
information context (`CreateICW`, no job) and reads
`PHYSICALOFFSETX/Y`, `HORZRES/VERTRES`, `PHYSICALWIDTH/HEIGHT`. Because the IC
already has `dmOrientation` applied, the offsets are in the sheet's own frame
- the same frame `RenderVectorPage` maps prepared points into
(`off = -PHYSICALOFFSET`). `supported` is `MatchesPreparedSheet`, i.e. the
check that would make `End` fail with "does not support the requested paper
size", so the dialog warns before Print instead of after.
Runs on its own thread via the shared `RunPrinterQueryAsync` (the old
`QueryPrintersAsync` body, generalized).

Dart: `loadPrintPrintableArea` / `PrintPrintableArea`. The dialog asks once per
(printer, colour, duplex, tray, sheet size) and caches for its lifetime. The
painter hatches the band outside the printable rect with a dashed inner edge;
a caption gives the four edges in points. Other platforms don't expose this
to us before the system dialog, so no overlay there.

## Validation

- `dart_pdf_printing`: 111 tests (new: preset round-trip/sort/replace/delete,
  `matches`, defensive `PrintPrintableArea.fromMap`, preset UI save/drift/
  re-apply/delete, preset selecting a printer + its options, margin caption +
  unsupported-paper warning, printer switch keeps controls in place).
- `app`: print menu/preview tests (the Windows handoff now also sees one
  `printableArea` query before `beginJob`).
- Native: both `.cpp` files pass `x86_64-w64-mingw32-g++ -std=c++17
  -fsyntax-only -Wall -Wextra -Wconversion` against Flutter 3.50's Windows
  client wrapper (`flutter precache --windows`); the only warnings are in
  Flutter's own `method_codec.h`.
- Not done: a real Windows build or a physical printer. The margin numbers
  come from the driver; virtual printers (Microsoft Print to PDF) report zero.
