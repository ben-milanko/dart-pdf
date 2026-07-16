# Windows printing crash: print a self-rendered raster copy

## Symptom

Printing crashed the whole app on Windows.

## Root cause

The app hands the current document's bytes to the `printing` plugin
(`Printing.layoutPdf`). On Windows (and Linux) that plugin prints through a
bundled **PDFium** - `FPDF_LoadMemDocument64` + `FPDF_RenderPage` in the
plugin's `windows/print_job.cpp::writeJob`. PDFium is a strict, third-party
rasteriser, and a render-time access violation inside it takes down the
process - a native crash Dart's `try/catch` around `_print` cannot catch.

This engine is deliberately *lenient* on input ("real-world PDFs are broken";
see CLAUDE.md), so it opens and renders files that PDFium chokes on. The user
opens such a file, it displays fine here, they hit Print, and PDFium crashes
on the same bytes.

Byte handling was ruled out: Windows uses the plugin's non-FFI path
(`platform_os.dart`: `useFFI = isMacOS || isIOS`), which copies via
`Uint8List.fromList(bytes)` before crossing to native, so the editor's
prefix-view `bytes` (`Uint8List.sublistView(_bytes, 0, len)`) is not the
problem. The plugin is already at 5.15.0 ("Fix Windows PDFium lifecycle"), so
a version bump does nothing.

## Fix

On Windows only, don't hand PDFium the original document. Rasterise it with
our own robust engine and print a flat, image-only PDF that any reader parses
safely.

- `rasterizePdfForPrinting` (dart_pdf_editor `print_rasterize.dart`, exported):
  renders every page to a JPEG at 200 dpi via `PdfPageExport.exportPages` and
  reassembles them with `PdfImageDocument.fromImageBytes(pages, dpi: dpi)`.
  Passing the same `dpi` to both sizes each output page back to the source
  page's point dimensions (one image pixel = 72/dpi pt). Both halves already
  existed; this just composes them.
- `printPdfBytes` (app `printing.dart`) gained a platform gate. On
  `!kIsWeb && TargetPlatform.windows` it prints the rasterised copy; **any**
  rasterisation failure falls back to the original bytes, so it is never worse
  than before. Every other platform keeps the crisp vector document - their
  native renderers are robust, and the web prints through the browser (where
  `defaultTargetPlatform` can still report Windows, hence the `kIsWeb` guard).
  `platform` / `rasterize` are `@visibleForTesting` seams.

Tradeoff: Windows prints a 200-dpi raster, not vector - no selectable text in
the spool, slightly larger jobs - but it prints instead of crashing.

Linux uses the same PDFium path and could hit the same crash; left as-is since
only Windows was reported, and the gate is a one-line extension if needed.

## Tests

- `packages/dart_pdf_editor/test/print_rasterize_test.dart`: the raster copy
  opens cleanly, keeps the page count, carries one /Image XObject per page with
  the original text gone, preserves per-page sizes, and survives broken input
  the lenient parser still renders.
- `app/test/printing_test.dart`: `printPdfBytes` prints verbatim off Windows,
  a rasterised copy on Windows, and falls back to the original bytes when the
  rasteriser throws. The mock now drives the plugin's `onLayout` callback so it
  can assert the exact bytes handed to the backend.
