# pdf_viewer_example

The demo app for `dart_pdf_editor`: a full viewer/editor with search, text
selection, the editing toolbar and sidebars, plus an interactive demo
document whose links and overlays drive the surrounding Flutter app. It is
also the reference wiring for the drop-in `PdfEditorView` / `PdfReader`
shells, file open/save, and HTTP OCR through
`pdf_ocr_vlm`.

Runs on every Flutter platform - macOS, iOS, Android, web, Windows, and
Linux:

```sh
fvm flutter run -d macos     # or: ios / android / chrome / windows / linux
```

Open a file straight away on desktop with
`--dart-define=PDF=/path/to/file.pdf`.

File access matches each platform's conventions: opening always uses the
native picker; saving uses a save dialog on desktop, a browser download
on the web, and the share sheet on iOS and Android.

## Patrol E2E tests

The `patrol_test/` suite launches the real example app and covers its core
reader/editor journeys: PDF links and live overlays, page navigation and
search, reader/editor mode switching, shape and ink creation, undo/redo and
delete, note creation and editing, and text/checkbox/radio/choice form fills.
It also checks Patrol's Flutter/native bridge. Patrol is pinned in
`pubspec.yaml`; install the matching CLI before running it:

```sh
dart pub global activate patrol_cli 4.7.0
```

Run against any connected Patrol-supported target:

```sh
patrol test --device <android-device-id>
patrol test --device <ios-simulator-id>
patrol test --device macos
patrol test --device chrome --web-headless
```

The CI web journey enables `PdfPerfLog` and uploads `patrol-perf.log`,
`patrol-perf.json`, and `patrol-perf.md` inside the `patrol-web-results`
artifact. Pull requests also show the Markdown summary in the Actions run.
These wall-clock measurements are review evidence rather than a pass/fail gate;
compare the JSON with a recent `main` run from the same hosted-runner lane.

When using this repository's FVM SDK, prefix the commands with
`PATROL_FLUTTER_COMMAND="fvm flutter"`. Patrol supports Android, iOS, macOS,
and web. Its runner does not support Windows or Linux; those platforms remain
covered by Flutter unit/widget tests and the existing build/smoke jobs.

## Web worker

The repository example self-hosts its render worker at
`web/pdf_render_worker.dart.js`. Generate it before a local web run:

```sh
fvm dart run dart_pdf_editor:build_web_worker
```

`tool/build_web.sh` does this automatically before a production build, as do
the preview, deploy, and Patrol workflows. The Patrol performance target fails
unless a real off-thread request completes, so CI cannot silently benchmark the
main-thread fallback. Published apps may instead use the prebuilt worker from
`dart_pdf_editor_assets` via `registerBundledEditorAssets()`.

## OCR

The example's **OCR...** menu item uses `pdf_ocr_vlm`: enter a dots.ocr/vLLM
chat-completions endpoint, model name, and optional bearer token, then the
example runs `PdfEditor.applyOcr` over every page and opens a new OCR'd tab.
For native offline OCR, use the product app or the `pdf_ocr_ondevice` README
as the reference flow.
