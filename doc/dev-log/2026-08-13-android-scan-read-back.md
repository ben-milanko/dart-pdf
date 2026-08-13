# Android: "Scan to new document" produced nothing

"Scan to new document" (and "Insert scan") appeared to do nothing on Android:
the ML Kit scanner opened, the user captured and accepted pages, and no tab
ever showed up - with no error either.

## Cause

The whole scan flow is platform-agnostic except one step: reading back the PDF
the scanner wrote. `doc_scan_io.dart` did that with `dart:io`:

```dart
if (path.startsWith('file://')) path = Uri.parse(path).toFilePath();
else if (path.startsWith('content://')) return null;   // <- Android
final file = File(path);
if (!await file.exists()) return null;                 // <- Android
```

Two problems, and they compound:

1. **Android's location isn't reliably a path.** iOS hands back a bare
   filesystem path, but Android hands back whatever
   `GmsDocumentScanningResult.Pdf.getUri()` produced - a `content://` URI from
   ML Kit's own FileProvider on some Play Services builds, a `file://` URI into
   a scratch directory on others, and either way a location ML Kit owns rather
   than one the app may open by path. The `content://` branch returned null
   outright; the `file://` branch could miss too.
2. **A failed read was indistinguishable from a cancelled scan.** Both came
   back as `null`, and `_newDocumentFromScan` treats null as "the user backed
   out" - a deliberate silent no-op. So the failure had no toast, no dev-log
   line, nothing.

## Fix

- **Read through the ContentResolver on Android.** The app's runner already
  owns a `mobile_file` method channel with `ContentResolver`-backed helpers
  (`fileLength`/`readRange`, from the reference-based open work); it gained
  `readUri`, a whole-file read via `contentResolver.openInputStream`, which
  resolves `content://` and `file://` alike. `readScannedFile` tries the plain
  path first (the iOS shape, and the Android shape that happens to be readable)
  and falls back to `readUri` on Android only. An older runner without the
  method (`MissingPluginException`) degrades to the previous behaviour rather
  than throwing.
- **Null now means cancelled, and only cancelled.** `scanDocumentToPdf` throws
  `DocumentScanException` (carrying the location it couldn't read) when a scan
  completed but its PDF couldn't be read back. The menu handlers already catch,
  toast "Couldn't scan the document.", and log to `AppDevTools` - so the URI
  that failed now lands in the dev log instead of vanishing.

## Notes

- Read the result **immediately**: ML Kit reclaims its scratch space once the
  scanner activity is gone, so the bytes have to be pulled on the callback, not
  held as a path for later. The flow already did this; keep it that way.
- The Kotlin `readUri` handler mirrors the existing `readRange`/`fileLength`
  ones (same `fileIoExecutor`, same `read_failed` error code) and, like them,
  needs on-device verification - it can't run in `flutter test`.
- `doc_scan_io_test.dart` covers the Dart contract with a mocked channel: plain
  path wins without touching the runner, `content://` and unopenable `file://`
  go through it, an empty file counts as unreadable, and non-Android platforms
  never reach for it.
