# DartPDF

A standalone, cross-platform PDF editor built on the
[`dart_pdf_editor`](../packages/dart_pdf_editor) SDK. Rendering is pure Dart:
no PDFium and no platform channels. Runs on iOS, Android, web, macOS, Windows, and
Linux from one codebase.

This is the **product app**. The SDK's feature showcase lives separately in
`packages/dart_pdf_editor/example`.

On Linux, the preferred installation is the official signed Flatpak:

```sh
flatpak install --from \
  https://dartpdf-flatpak.web.app/dartpdf.flatpakref
```

Ubuntu and other snapd users can use the secondary Snap Store channel:

```sh
sudo snap install dartpdf
```

AppImage and portable tarball builds remain available from
[GitHub Releases](https://github.com/ben-milanko/dart-pdf/releases/latest).

## Features

- Open PDFs from the picker, the OS ("open with" / share), drag-and-drop
  (desktop + web), recent files, or a launch argument. Recent documents can
  be browsed as a page-thumbnail grid.
- On mobile, scan straight to a new PDF or insert a scan into the current
  document, and capture a page or placed image with the camera.
- The full editing UI from the SDK: annotations, ink, shapes, free text,
  stamps, forms, redaction, page management, search, text selection,
  hyperlinks, interactive image cropping, and annotation lock/unlock.
  Keyboard shortcuts are configurable for every tool.
- Drawn signatures and certificate-backed PAdES B-B digital signatures. The
  digital-signing flow reads an RSA key and X.509 chain in memory, validates
  the result, then saves through the normal document destination.
- OCR for scanned PDFs: native builds use `pdf_ocr_ondevice` with a
  downloadable PP-OCR model that runs offline after the first download; the web
  build uses a browser-local Florence-2 bridge through Transformers.js/WebGPU
  or WASM. OCR adds an invisible selectable/searchable text layer and opens the
  result in a new tab.
- Tabs, light/dark theme, read-only mode, document compare.
- Progressive rendering reveals complex pages top-down, while faithful
  overprint and spot-color handling keeps print-oriented PDFs visually
  accurate.
- Developer tools (F12) can switch deep-zoom tiles live between Canvas and the
  optional flutter_gpu backend, tune the GPU texture/geometry ceilings, inspect
  actual GPU/fallback routes and resource pressure, and export those metrics as
  JSON. Web keeps Canvas through the companion's compile-time stub; pull-request
  web previews provide macOS, Windows, and Linux download buttons in this
  section for testing the native backend.
- Desktop builds include the native `dartpdf` CLI and stdio MCP server for
  bounded inspection, text extraction, form listing, and annotation listing.
  See [`dart_pdf_cli`](../packages/dart_pdf_cli) for installed paths and agent
  registration.
- Dirty-state tracking with a save indicator and crash recovery: unsaved
  revisions are mirrored in the background and offered for restoration after
  a restart.
- **Save** overwrites the original file in place (desktop); **Save as** and
  platform share/download flows write elsewhere. The save flow can also
  losslessly compress the PDF.
- **Print** the open document (⌘P / Ctrl+P, or the DartPDF menu) through the OS
  print dialog on every platform, including browser print on the web.
- Discard prompts on tab-close and app-quit; reopening a document restores its
  scroll position and zoom.
- Desktop releases can update in place: **Update now** downloads and applies
  the platform installer without sending the user through a browser.

## Run

From the repo root (the app is a pub-workspace member):

```sh
fvm flutter pub get
cd app
fvm flutter run -d macos      # or -d chrome, -d windows, -d linux, or a device
```

Open a specific file on startup: `fvm flutter run -d macos path/to/file.pdf`
(desktop), or use the in-app Open button anywhere.

Desktop multi-window support is enabled by default:

```sh
fvm flutter run -d macos  # or windows / linux
```

Each desktop runner always starts the required headless multi-view engine, and
Dart enables Flutter's matching framework feature before binding
initialization. This applies to debug, release, and Store builds, so dialogs
and regular windows cannot end up on incompatible engine modes. See
[the implementation notes](../doc/dev-log/2026-08-14-flutter-347-multi-window.md).

On web, `dart_pdf_editor` uses its bundled page-render worker asset
automatically. If the browser cannot load it, rendering falls back to the main
thread.

## Test & analyze

```sh
fvm dart analyze app
cd app && fvm flutter test
```

## Build

`flutter build <apk|appbundle|ios|macos|windows|linux|web> --release`. The three
desktop native projects compile and bundle the `dartpdf` CLI/MCP sidecar as part
of the ordinary build. Releases are automated on `app-v*` tags. See
[RELEASING.md](RELEASING.md).

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
| Print via the OS dialog (⌘P / Ctrl+P) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| Digitally sign with PEM/DER key + certificate | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| Reopen restores viewport | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

\* In-place save is desktop-only today; mobile/web fall back to share/download
(see RELEASING.md and the save notes in the source).
