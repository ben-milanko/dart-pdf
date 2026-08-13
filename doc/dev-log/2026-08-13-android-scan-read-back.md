# Android document scan: read-back, and making failures say what failed

Two separate things, both reported as "Scan to new document doesn't work on
Android". Keeping them apart matters, because they have the same symptom from
the outside and completely different causes.

## 1. The read-back was wrong on Android (fixed)

The whole scan flow is platform-agnostic except one step: reading back the PDF
the scanner wrote. `doc_scan_io.dart` did that with `dart:io`:

```dart
if (path.startsWith('file://')) path = Uri.parse(path).toFilePath();
else if (path.startsWith('content://')) return null;   // <- Android
final file = File(path);
if (!await file.exists()) return null;                 // <- Android
```

iOS hands back a bare filesystem path, but Android hands back whatever
`GmsDocumentScanningResult.Pdf.getUri()` produced — a `content://` URI from ML
Kit's own FileProvider on some Play Services builds, a `file://` URI into a
scratch directory on others, and either way a location ML Kit owns rather than
one the app may open by path. The `content://` branch bailed outright; the
`file://` branch could miss too.

Worse, **a failed read was indistinguishable from a cancelled scan**: both
returned `null`, and `_newDocumentFromScan` treats `null` as "the user backed
out" — a deliberate silent no-op. No tab, no toast, no dev-log line.

Fix:

- `readUri` on the runner's `mobile_file` channel (`MainActivity.kt`): a
  whole-file read via `contentResolver.openInputStream`, which resolves
  `content://` and `file://` alike, on the same IO executor as the existing
  ranged reads.
- `readScannedFile` tries the plain path first (the iOS shape, and the Android
  shape that happens to be readable) and falls back to `readUri` on Android
  only. An older runner without the method degrades to the previous behaviour.
- `scanDocumentToPdf` throws `DocumentScanException` (carrying the location)
  when a scan completed but its PDF could not be read. `null` means cancelled
  and only cancelled.

Read the result **immediately**: ML Kit reclaims its scratch space once the
scanner activity is gone, so the bytes have to be pulled on the callback, not
held as a path for later. The flow already did this; keep it that way.

## 2. The camera not opening at all is a *different* failure

Reported after the above landed: pressing "Scan to new document" shows the
error snack bar instantly and no camera ever appears. That is upstream of the
read-back — `FlutterDocScanner().getScannedDocumentAsPdf()` threw before the
scanner activity launched. The plugin's Android side can fail there in three
ways, and the old UI could not tell them apart because the toast was a fixed
sentence and the reason only went to `AppDevTools`:

- `SCAN_FAILED` from `getStartScanIntent`'s failure listener — Google Play
  services unavailable or too old (**every emulator image without the Play
  Store**), the doc-scanner module not yet downloaded (it is fetched on demand,
  so the first call can fail while it downloads), or `MlKitException UNSUPPORTED`
  on a device with less than 1.7 GB total RAM, which the API requires.
- `SCAN_IN_PROGRESS` — the plugin keeps a single `pendingResult` and rejects a
  second request while one is outstanding. It is cleared on success, on error,
  and on `onDetachedFromActivity`; a scan whose activity result never comes back
  leaves it set, and then *every* later press errors instantly with no camera
  until the process restarts. Force-stopping the app and pressing once
  distinguishes this from the launch failures above.
- `NO_ACTIVITY` — no foreground activity attached.

So this session's second half is about making the failure legible rather than
guessing:

- `_runScan` in `editor_screen.dart` is now the single scan entry point for both
  menu actions. Its toast appends the error's own `toString()` (trimmed to 140
  chars) to the localized sentence — `DocScanException(SCAN_FAILED): Unable to
  start document scanner` is exactly the string that identifies the cause — and
  runs for 6s instead of 2 so it can be read. No new ARB keys, so no
  20-locale churn.
- `_scanInFlight` guards re-entrancy, so the app can never manufacture a
  `SCAN_IN_PROGRESS` itself from a double tap.

`_toast` gained an optional `duration` for this; everything else keeps the 2s
default.

## Notes

- The Kotlin `readUri` handler mirrors the existing `readRange`/`fileLength`
  ones and, like them, needs on-device verification — it can't run in
  `flutter test`.
- `doc_scan_io_test.dart` covers the Dart read-back contract with a mocked
  channel; `doc_scan_menu_test.dart` covers the toast carrying the reason and
  the re-entrancy guard.
- The ML Kit doc scanner has no `com.google.mlkit.vision.DEPENDENCIES`
  manifest meta-data to pre-download it (that mechanism is for the bundled
  vision APIs) — checked, don't add one.
