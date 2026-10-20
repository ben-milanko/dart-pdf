# 2026-07-19 — Web file-open hang on app.dart-pdf.com (COEP × blob-URL XHR)

## Symptom

On the deployed 2.0.0 app (app.dart-pdf.com), opening a **large** PDF hung
forever on the "Opening <name>…" spinner. Small PDFs opened fine. The tab UI
stayed responsive (you could switch to other tabs), no error surfaced in the
browser console or the app's own F12 devtools log, and PdfPerf showed no
samples — i.e. parsing never started.

It reproduced **only on the deployed build**. Locally, both
`flutter run -d chrome` (debug/DDC) and `flutter run --release -d chrome`
(dart2js) opened a 24 MB file in ~100–260 ms.

## Diagnosis path

Added temporary `open-trace:` milestones to the open path
(`EditorScreen._openLoadedBytes` / `_pickAndOpen` / `_materializeDeferred`,
logged via `AppDevTools.addLog`, visible + exportable from the F12 panel).
Deployed them and captured the trace on prod:

```
open-trace: picked "…Quickstart.pdf" (declared 24121963 B); starting readAsBytes
open-trace: "…Quickstart.pdf" placeholder shown, awaiting bytes
   ← stops here; "bytes ready" never prints
```

So `await file.readAsBytes()` never completes on the deployed build.

Ruled out along the way: the deploy pipeline (assets, cache-bust, freshly
built worker are byte-identical to the committed one), the multi-worker pool
(pool size 1 still hung), COS parsing (`PdfDocument.open` of the 12 MB Ghent
X4 file is 19 ms in pure Dart), and the edit-session build
(`PdfEditingController` is just that open plus listener wiring).

## Root cause

`file_selector_web` (0.9.5) hands back **path-only** XFiles:
`_convertFileToXFile` does `XFile(URL.createObjectURL(file))` with no bytes.
`cross_file` (0.3.5+4) `XFile.readAsBytes()` therefore goes through its
`_blob` getter, which re-hydrates the blob by firing an `XMLHttpRequest` at
the `blob:` URL (`html.dart` lines ~119–138).

The deployed site sets cross-origin isolation in `app/firebase.json`
(`Cross-Origin-Opener-Policy: same-origin` +
`Cross-Origin-Embedder-Policy: credentialless`, added so skwasm's
multithreaded renderer can use `SharedArrayBuffer`). Under that isolation the
XHR against the `blob:` URL never fires `onLoad`/`onError`, so the completer
never completes and `readAsBytes` hangs. Local `flutter run` sets no such
headers, so the same XHR works — which is why it only reproduced on prod. The
current deploy builds **CanvasKit**, which doesn't even need the isolation.

## Fix

New web-only picker (`app/lib/web_file_picker.dart`, with
`web_file_picker_stub.dart` for non-web via the
`if (dart.library.js_interop)` import) that builds its own
`<input type=file>` and reads each chosen `web.File` **directly** with
`File.arrayBuffer()` (in-memory blob read, no `createObjectURL`, no XHR),
returning in-memory `XFile.fromData(bytes)`. Those XFiles keep their bytes, so
any later `readAsBytes()` takes cross_file's fast `_browserBlob` path and never
touches the XHR. `pickPdfFile()` / `pickPdfFiles()` in `file_io.dart` route to
it on `kIsWeb`; native platforms keep `file_selector`. This keeps the
cross-origin isolation headers intact (OCR / future skwasm threading unaffected).

## Follow-ups

- Drag-and-drop and other web read paths (image/stamp-bundle picks) still go
  through `file_selector`/`cross_file`; audit them for the same blob-URL XHR
  under isolation.
- The eager read means a multi-file web pick reads every file's bytes at pick
  time (the deferred-parse loop already did this, so no net regression).
- Remove the temporary `open-trace:` logging once the deployed fix is verified
  (it was committed to help confirm the fix on prod).
