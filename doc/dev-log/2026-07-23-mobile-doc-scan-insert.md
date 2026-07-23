# Mobile document scanning: scan to new document / insert scan

Added two mobile/tablet-only entry points to the DartPDF app that turn a
device camera document scan into PDF pages:

- **Scan to new document** - opens the captured pages as a fresh tab.
- **Insert scan** - splices the captured pages into the open document's edit
  session, after the page currently in view (one undoable step).

Both live in the app menu (`app/lib/editor_screen.dart`) and only appear where
scanning is available.

## How it's wired

- New dependency: `flutter_doc_scanner` (Google ML Kit Document Scanner on
  Android, VisionKit `VNDocumentCameraViewController` on iOS). Phone/tablet
  only; iOS 13+ / Android already satisfy its minimums.
- `app/lib/doc_scan.dart` is the facade: a `DocumentScanner` typedef
  (`Future<Uint8List?> Function()` returning a ready-to-open PDF) plus a
  conditional export - `doc_scan_io.dart` on native, `doc_scan_stub.dart` on
  web (and anywhere without `dart:io`), so the plugin is never referenced on
  the web build.
- `doc_scan_io.dart` launches the scanner, pulls the pages back **as images**,
  and stitches them into a PDF with our own pure-Dart
  `PdfImageDocument.fromImageBytes` (one page per shot, JPEGs pass through
  verbatim) so page sizing stays under our control. If the image route yields
  nothing it falls back to the scanner's own PDF export.
- The plugin's result shape varies by version/platform (a `Map` keyed by
  `images`/`pdfUri`, or a bare path/URI, or a list), and page locations can be
  `file://` URIs or bare paths. Extraction and file reads are deliberately
  lenient; `content://` URIs (unreadable via `dart:io`) and missing files are
  skipped, and any failure degrades to `null` so the caller toasts
  "couldn't scan" rather than throwing.

## Injection seam

`EditorScreen` gained a `documentScanner` seam (defaults to the platform
scanner when `documentScanSupported`, else null - which hides the menu
entries). Tests inject a fake returning a known PDF, since the real scan needs
the native ML Kit / VisionKit channels. `_newDocumentFromScan` /
`_insertScan` hold the flow (cancel = silent no-op, failure = toast).

## Test gotcha

`doc_scan_menu_test.dart` opens the menu **by key** (`dartpdf-app-menu`), not
`find.byTooltip` - byTooltip enables the semantics tree, and the document swap
on insert re-renders the viewer, which trips a debug semantics-build assertion
(`node.built is not true`). The success toast's SnackBar announcement enables
semantics the same way, so the insert test asserts the scanner was invoked
(recording fake + a single `pump`) rather than settling through the mutated
render - matching `drop_insert_test`'s "assert the synchronous branch, leave
the page copy to the editor-package tests" stance.
