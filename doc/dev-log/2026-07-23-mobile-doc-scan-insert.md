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
- `doc_scan_io.dart` launches the scanner **once** and returns the pages as a
  PDF. **One scan session is the whole design constraint:** every
  `FlutterDocScanner` method (`getScannedDocumentAsImages`,
  `getScannedDocumentAsPdf`, …) launches its *own* camera, so calling more than
  one re-opens the scanner after the user has already accepted their pages. We
  call exactly `getScannedDocumentAsPdf()` and read the returned file back with
  `readScannedFile`.
- The plugin (0.0.21) returns **typed models**, not raw maps:
  `getScannedDocumentAsPdf()` → `PdfScanResult?` with `.pdfUri` (null on
  cancel). The location is a bare filesystem path on iOS
  (`pdfFilePath.path`) and a `file://` URI on Android (ML Kit writes the PDF to
  the app cache); `readScannedFile` normalises `file://` → path and reads it.
  A `content://` URI (unreadable via `dart:io`) or a missing file degrades to
  `null`, so the caller toasts "couldn't scan" rather than throwing.
- **Gotcha that cost a device round-trip:** an earlier version parsed the
  result leniently (Map/List/String) and, when the *images* route came back
  "empty", fell back to a *second* `getScannedDocumentAsPdf()` call. Because the
  plugin actually returns typed `ImageScanResult`/`PdfScanResult` objects, the
  lenient parser never matched, so the images route was always "empty" and the
  fallback re-opened the camera after every accepted scan (and inserted
  nothing). The fix is to use the typed API and make exactly one scan call.
- iOS needs `NSCameraUsageDescription` in `app/ios/Runner/Info.plist` -
  VisionKit opens the camera and iOS hard-aborts (`abort_with_payload`) if the
  privacy string is missing. Android's ML Kit scanner runs in Play Services and
  needs no host camera permission.

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
