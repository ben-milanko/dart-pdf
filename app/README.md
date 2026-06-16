# DartPDF

A standalone, cross-platform PDF editor built on the
[`dart_pdf_editor`](../packages/dart_pdf_editor) SDK. Rendering is pure Dart:
no PDFium and no platform channels. Runs on iOS, Android, web, macOS, Windows, and
Linux from one codebase.

This is the **product app**. The SDK's feature showcase lives separately in
`packages/dart_pdf_editor/example`.

## Features

- Open PDFs from the picker, the OS ("open with" / share), drag-and-drop
  (desktop + web), recent files, or a launch argument.
- The full editing UI from the SDK: annotations, ink, shapes, free text,
  stamps, forms, redaction, page management, search, text selection.
- OCR for scanned PDFs: native builds use `pdf_ocr_ondevice` with a
  downloadable PP-OCR model that runs offline after the first download; the web
  build uses a browser-local Florence-2 bridge through Transformers.js/WebGPU
  or WASM. OCR adds an invisible selectable/searchable text layer and opens the
  result in a new tab.
- Tabs, light/dark theme, read-only mode, document compare.
- Dirty-state tracking with a save indicator; **Save** overwrites the original
  file in place (desktop), **Save as** / share / download elsewhere.
- Discard prompts on tab-close and app-quit; reopening a document restores its
  scroll position and zoom.

## Run

From the repo root (the app is a pub-workspace member):

```sh
fvm flutter pub get
cd app
fvm flutter run -d macos      # or -d chrome, -d windows, -d linux, or a device
```

Open a specific file on startup: `fvm flutter run -d macos path/to/file.pdf`
(desktop), or use the in-app Open button anywhere.

For web performance testing, build the optional page-render worker before
running or building the web app:

```sh
cd app
dart run dart_pdf_editor:build_web_worker
fvm flutter run -d chrome
```

`lib/app.dart` points web builds at `web/pdf_render_worker.dart.js`. If the
file is missing, rendering falls back to the browser main thread.

## Test & analyze

```sh
fvm dart analyze app
cd app && fvm flutter test
```

## Build

`flutter build <apk|appbundle|ios|macos|windows|linux|web> --release`. Releases
are automated on `app-v*` tags. See [RELEASING.md](RELEASING.md).

## Manual device-test matrix

Automated builds cover macOS, iOS (simulator), Android (APK), and web. The
native OS-integration paths still want on-device confirmation:

| Check | iOS | Android | macOS | Windows | Linux | Web |
|---|---|---|---|---|---|---|
| Open via "open with" / association | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ (installed PWA) |
| Receive a shared PDF | ☐ | ☐ | n/a | n/a | n/a | n/a |
| Drag-and-drop onto window | n/a | n/a | ☐ | ☐ | ☐ | ☐ |
| Edit → Save overwrites the original | n/a* | n/a* | ☐ | ☐ | ☐ | n/a* |
| OCR a scanned PDF | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| Reopen restores viewport | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

\* In-place save is desktop-only today; mobile/web fall back to share/download
(see RELEASING.md and the save notes in the source).
