# Print options and physical sheet preparation

The app's Print command (menu and Cmd/Ctrl+P) now opens the same settings
and output preview on every platform. The old Windows/Linux-only preview
accepted just an inclusive from/to range.

The dialog now offers:

- All, current, selected thumbnail pages, and comma-separated custom ranges.
  Descending ranges are supported; repeated pages are deduplicated.
- Document-sized paper or A0–A5, Letter, Legal and Tabloid, with orientation.
- Actual size, fit/reduce to paper or margins, percentage scale, quarter-turn
  rotation, centering and offsets. All dimensions are in PDF points (72/inch).
- Multiple pages per sheet, four reading orders and page borders.
- Copies, collation and reverse page order. Copies repeat physical sheets
  after n-up layout, so uncollated copies cannot accidentally occupy one sheet.
- Document and markups, document only, or markups only; independent dimming
  of document content and markups; visible hyperlink borders. Form fields
  belong to the document layer.
- Get Window: draw a rectangle on the current source-page preview, then print
  that region. The source crop box stays unchanged.
- Add Files: import PDFs into a temporary batch with their form resources.
  Defaults resets print settings without altering any open document.

`print_settings.dart` is the immutable settings snapshot.
`print_composer.dart` creates a fresh vector PDF of the physical sheets, reusing
source resources and appearance Forms across pages and copies. Print flags are
honored; the prepared file contains flattened printable artwork. Source page
rotation, crop origin and UserUnit are folded into the sheet geometry. Streams
keep their existing compression, encrypted inputs are decrypted on import,
and the original editor session never changes. The preview uses this same
composer for one sheet at a time. Print validation checks every sheet's
geometry before the dialog closes, including smaller pages in mixed-size jobs.
Print commits pending ink and inline text before the dialog takes a detached
revision, so later edits cannot change the job under its preview. Batch imports
retain each source's optional-content defaults and
print-usage rules, plus the first document's output profile. Interleaved form
fields and markups retain their original annotation stacking order, including
opacity on annotations whose appearances must be synthesized.

The native handoff carries `useDocumentPageSize` and first-sheet dimensions.
Windows maps points to physical printer pixels and updates media between
mixed-size sheets; GTK uses full-page point coordinates and per-page setup.
PDFKit disables additional scaling/rotation. Android and AirPrint start with
matching media. Desktop defaults reset copies and n-up because those choices
are already present in the prepared PDF. Windows also now honors the native
Print to File checkbox by passing `FILE:` to StartDoc.

Printer selection, tray, color, duplex, status, properties and supported media
remain with the system print UI. Actual nonprintable hardware margins cannot
be bypassed; the red preview guide represents the configured print margin,
not a measurement from the chosen device. Browser/mobile services and macOS
mixed-media jobs still negotiate paper with the OS/printer. Dim Markups applies
to all printable markups. Printer-specific processing settings remain in the
system dialog.

Validation includes settings/order/resource tests, encrypted and PDF.js corpus
inputs, widget range/crop/batch/validation tests, menu and shortcut integration
across the five native platforms, and pixel checks for content selection,
dimming, rotation, scaling and crop placement. The dialog was visually checked
at desktop and phone sizes, and a prepared n-up PDF was independently rendered
with macOS ImageIO. The macOS and Android apps build; Windows/GTK native
compilation runs in CI. Physical-printer output has not been tested.
