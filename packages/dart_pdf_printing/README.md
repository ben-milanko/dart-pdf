# dart_pdf_printing

Optional PDF printing for Flutter apps using `dart_pdf_editor`. Includes the
same layout preview and native printing used by the DartPDF app. The viewer
and editor packages do not depend on this plugin: add it only when your app
needs printing. No PDFium or other bundled PDF engine is added.

## Install

Requires Flutter 3.47 or later. Add the plugin alongside the editor:

```yaml
dependencies:
  dart_pdf_editor: ^4.3.0
  dart_pdf_printing: ^0.1.0
```

During development before the first pub.dev release, use a local checkout:

```yaml
  dart_pdf_printing:
    path: /path/to/dart-pdf/packages/dart_pdf_printing
```

Run `flutter pub get` and rebuild the app. Flutter registers the platform
implementation automatically; there is no runner code to copy or registration
function to call. This follows Flutter's [plugin packaging model](https://docs.flutter.dev/packages-and-plugins/developing-packages).

## Preview and print

```dart
import 'package:dart_pdf_printing/dart_pdf_printing.dart';

await printPdfWithPreview(
  context,
  document: document,
  title: 'Report.pdf',
  currentPage: viewerController.currentPage, // zero-based
  selectedPages: editingController.selectedPages,
);
```

Put this call in your own Print button or Cmd/Ctrl+P action. For an active
editing session, unfocus the inline editor, apply pending focus changes and
call `editingController.finishInk()` before passing
`editingController.document`. See [the complete host example](example/main.dart).
The preview captures a separate revision; printing never edits the source.
Catch errors from the returned future to present your app's error UI.

The preview includes all/current/selected/custom page ranges, document paper
or A0–A5/Letter/Legal/Tabloid, orientation, scaling, margins, offsets, rotation,
cropping, n-up layout, copies, collation, reverse order, document/markup
selection, dimming and hyperlink borders. Its preview and print output use
the same sheet composer. `addFiles` is an optional async callback returning
`List<PdfDocument>` for batch printing; your app handles file selection and
passwords. Omit it to hide Add Files.

On Windows, the preview also selects the printer, color, duplex mode and paper
source, then submits directly to that queue. Printer properties opens the
driver's advanced settings only when requested. A missing saved printer must
be replaced explicitly. Other platforms keep their native print dialogs.

Print choices persist across app launches, including changes made before
Cancel. Common options and per-printer choices use `shared_preferences`;
Windows also saves the complete driver preferences for each queue. Defaults
resets document options while retaining the printer. Crop regions and added
batch files apply only to the current job.

## Use your own UI

Print PDF bytes directly, opening only the system print dialog:

```dart
await printPdfBytes(bytes: pdfBytes, title: 'Report.pdf');
```

Or compose physical sheets programmatically, then print them:

```dart
final sheets = preparePrintDocument(
  document,
  PrintSettings(
    pages: [0, 2, 3], // zero-based, in output order
    paperSize: PrintPaperSize.a4,
    scaling: PrintScaling.multiple,
    pagesPerSheet: 2,
  ),
);
await printPdfWithProgress(
  context,
  bytes: sheets,
  title: 'Report.pdf',
  useDocumentPageSize: true,
);
```

`showPrintPreviewDialog` returns `PrintPreviewResult?` for hosts that want to
handle the confirmed document/settings themselves. Cancel returns `null`.
It also returns the Windows `destination`: pass it to `printPdfBytes` or
`printPdfWithProgress`. When composing a duplex job, pass `twoSided: true` to
`preparePrintDocument` so copies repeat front/back pairs and odd copies get
blank backs. `printPdfWithPreview` handles both steps automatically.

For a custom Windows printer picker, use `listPrintPrinters`,
`loadPrintPrinterSettings`, and `showPrintPrinterProperties`, then pass a
`PrintDestination` to the print call. These printer discovery and driver APIs
are Windows-only. Omitting `destination` keeps the system print dialog.

`printPdfBytes` also accepts `onProgress(rendered, total)` for desktop page
preparation. System dialog cancellation is a normal completion; the API does
not claim that a physical printer finished the job. Concurrent native jobs on
one channel fail with `PlatformException(code: 'print_in_progress')`.

## Localization

Print widgets default to English when no delegate is registered. To use the
bundled translations, add `DartPdfPrintingLocalizations.delegate` to your
`MaterialApp.localizationsDelegates` and include its `supportedLocales` in
your app's locale list. For a small standalone host:

```dart
MaterialApp(
  localizationsDelegates: [
    ...DartPdfPrintingLocalizations.localizationsDelegates,
    DartPdfEditorLocalizations.delegate,
  ],
  supportedLocales: DartPdfPrintingLocalizations.supportedLocales,
  home: yourScreen,
)
```

## Platforms

| Platform | Print backend | Host setup |
| --- | --- | --- |
| macOS 12+ | PDFKit / AppKit | Enable `com.apple.security.print` in both entitlements files for sandboxed apps. |
| iOS / iPadOS | UIKit / AirPrint | iOS 15+; the plugin anchors the iPad popover to the registrar's view controller. |
| Android | Android PrintManager | API 24+; requires an attached Activity and a system print service. |
| Windows | GDI vector replay with direct queue selection | Normal Flutter Windows build tools; no downloaded native PDF library. |
| Linux | GTK / Cairo vector replay | GTK 3 development libraries, as required by Flutter Linux. |
| Web | Browser PDF viewer and print dialog | Browser must support inline PDF printing and permit the print action. |

For sandboxed macOS hosts, add this inside the `<dict>` in both
`macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<key>com.apple.security.print</key>
<true/>
```

Apple, Android and browser backends receive the PDF itself. Windows and Linux
receive drawing operations from this engine, including outlined embedded
fonts; unsupported advanced effects can be flattened or approximated by the
vector encoder. Raster fallback is available for backends without vector
capability. Printer media, duplex, trays and hardware margins remain under
system/printer control; Windows reports incompatible paper substitutions
instead of clipping composed sheets. Virtual PDF printers can still request
an output filename. Browser/mobile services and mixed-media macOS jobs
may negotiate paper sizes or scaling differently from the prepared preview.

The backend uses channel `dev.milanko.dart_pdf_printing`. Native registration
supports ordinary Flutter hosts and desktop engines without an implicit view.
Each native plugin owns its job state; Windows print preferences are scoped
to the embedding application's executable rather than shared with DartPDF.

## Development

From the repository root, run `flutter pub get`, then from this directory run
`flutter test`. The app at `../../app` consumes this plugin and exercises
native registration in its platform builds. The package's tests cover sheet
composition, pixel output, layout preview, localization, native protocol and
job isolation. Physical-printer output still depends on the printer/driver.

`tool/test_print_plugin.sh macos` (or `windows` / `linux`) creates a temporary
plain Flutter host and checks native registration through the plugin's channel.
On headless Linux, run it under `xvfb-run -a`. Set `DART_PDF_FLUTTER_BIN` if
Flutter is not on PATH. These checks also run in the desktop CI matrix and
never submit an actual print job.
