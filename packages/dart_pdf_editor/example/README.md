# pdf_viewer_example

The demo app for `dart_pdf_editor`: a full viewer/editor with search, text
selection, the editing toolbar and sidebars, plus an interactive demo
document whose links and overlays drive the surrounding Flutter app. It is
also the reference wiring for the drop-in `PdfEditorView` / `PdfReader`
shells, web render worker setup, file open/save, and HTTP OCR through
`pdf_ocr_vlm`.

Runs on every Flutter platform — macOS, iOS, Android, web, Windows, and
Linux:

```sh
fvm flutter run -d macos     # or: ios / android / chrome / windows / linux
```

Open a file straight away on desktop with
`--dart-define=PDF=/path/to/file.pdf`.

File access matches each platform's conventions: opening always uses the
native picker; saving uses a save dialog on desktop, a browser download
on the web, and the share sheet on iOS and Android.

## Web worker

For web runs on heavy PDFs, build the optional render worker once from this
directory before `flutter run -d chrome` or `flutter build web`:

```sh
dart run dart_pdf_editor:build_web_worker
```

`lib/main.dart` already sets `pdfRenderWorkerScriptUrl` to the generated
`web/pdf_render_worker.dart.js`. If the file is absent the app still works,
but page interpretation and image decode run on the browser main thread.

## OCR

The example's **OCR...** menu item uses `pdf_ocr_vlm`: enter a dots.ocr/vLLM
chat-completions endpoint, model name, and optional bearer token, then the
example runs `PdfEditor.applyOcr` over every page and opens a new OCR'd tab.
For native offline OCR, use the product app or the `pdf_ocr_ondevice` README
as the reference flow.
