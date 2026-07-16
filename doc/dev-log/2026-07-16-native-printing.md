# Native printing on every platform; drop `printing` / PDFium

## Symptom

Printing crashed the whole app on Windows.

## Root cause

The app handed the document bytes to the `printing` plugin
(`Printing.layoutPdf`). Its desktop backend spools by rendering the PDF
through a **bundled PDFium** (`FPDF_LoadMemDocument64` + `FPDF_RenderPage`).
PDFium is a strict, third-party rasteriser, and a render-time access
violation inside it takes down the process - a native crash Dart's
`try/catch` cannot catch. This engine is deliberately *lenient* and opens
broken-but-renderable files that PDFium chokes on, so a document that
displays fine here crashes when handed to the plugin.

## Fix

Remove the `printing` dependency (and thus PDFium) entirely and print
through each platform's **own** print system, feeding it pages this engine
renders itself. PDFium is gone on every platform.

### Uniform protocol

One method channel, `dev.milanko.dartpdf/native_print`, with the same
contract everywhere:

- `beginJob({name})` → resets the job, returns a target `{dpi}`.
- `printPage({image})` → one page as JPEG bytes; the runner accumulates it.
- `endJob()` → shows the platform print UI and prints the accumulated pages;
  returns false if the user cancels.
- `cancelJob()` → discards the accumulated pages.

The Dart side (`app/lib/native_print_io.dart`, `printDocumentPages`) renders
each page with our own engine (`PdfPageExport`, JPEG at the returned dpi) and
streams it. `native_print_web.dart` is the browser path (render to PNG, lay
out in a hidden iframe, `window.print()`); `native_print.dart` picks io vs web
by conditional import, mirroring `image_clipboard.dart`. `printing.dart` just
opens the document and calls `printDocumentPages`.

### Per-platform runners (all accumulate JPEGs, print at `endJob`)

- **Windows** (`windows/runner/native_print.cpp`): `PrintDlg` → `StartDoc`;
  each page decoded with WIC (as `image_clipboard.cpp` already does) and
  blitted with `StretchDIBits`; `EndDoc`. Links `comdlg32`/`gdi32`.
- **macOS** (`macos/Runner/MainFlutterWindow.swift`): an `NSView` that draws
  one image per page, run through `NSPrintOperation`.
- **iOS** (`ios/Runner/AppDelegate.swift`): `UIPrintInteractionController` with
  the JPEG `Data` array as `printingItems` (channel registered off the
  implicit engine's plugin registrar).
- **Android** (`MainActivity.kt`): `PrintManager` + a `PrintDocumentAdapter`
  that draws the bitmaps into the framework's own `android.graphics.pdf.
  PdfDocument` (the OS engine, not a bundled PDFium).
- **Linux** (`linux/runner/my_application.cc`): `GtkPrintOperation`; each page
  decoded with `GdkPixbufLoader` and painted onto the Cairo print context.

Each runner registers the channel next to its existing ones (incoming-file,
image-clipboard), so no new plugin plumbing.

Tradeoff: prints are 300-dpi rasters (200 on web), not vector - no selectable
text in the spool, slightly larger jobs - but they print instead of crashing,
and the same broken-but-renderable inputs this engine opens now print too.

## Retained utility

`rasterizePdfForPrinting` (dart_pdf_editor) - flatten a document to an
image-only PDF - stays as a public utility with its test, though the app no
longer routes printing through it.

## Follow-ups

- Large documents made the app unresponsive while printing: the loop renders
  and JPEG-encodes every page on the UI isolate (the encode is synchronous), so
  a big doc holds the isolate too long. `printDocumentPages` now yields
  (`await Future.delayed(Duration.zero)`) before each page so the engine can
  service input and paint between pages. Fuller offloading (encode in an
  isolate) is possible future work.
- Rasterized output loses selectable text and is heavier than vector - tracked
  as a follow-up enhancement (#303) to print vector content without
  reintroducing a third-party PDF engine.

## Validation

- Dart is fully checked: `dart analyze --fatal-infos` clean; app + dart_pdf_
  editor suites green. `native_print_io_test.dart` mocks the channel and
  asserts the begin/stream/end handshake, cancel, missing-plugin, and
  page-rejection paths; `printing_test.dart` drives `printPdfBytes` end to end
  through the mocked channel; `print_rasterize_test.dart` covers the utility.
- The native runner code (Swift/Kotlin/C++/GTK) could not be compiled in this
  environment, and PR CI builds only web + Dart on Ubuntu - it does not
  compile the desktop/mobile runners. **Validate each platform's build and a
  real print on device/CI before release.**
