# Snapshot tool → system clipboard (app)

The Snapshot tool (`PdfEditTool.snapshot`) already kept a **vector** copy of
the captured region on the in-app clipboard for paste-back, and the engine
already exposed `PdfViewer.onSnapshot` / `PdfEditorView.onSnapshot` (which
hands the host a `PdfSnapshot` carrying both `pngBytes` and the vector). The
**app** simply never passed a handler, so snapshots never reached the OS
clipboard. Wired that up.

## What changed (all in `/app`, per the request)

- `app/lib/image_clipboard.dart` (new): `copyPngToClipboard` (the default
  `ImageClipboardWriter`) drops PNG bytes on the system clipboard via
  super_clipboard; `clipboardSnapshotHandler({writer, onResult})` builds the
  `PdfSnapshotHandler` the screen passes to the viewer. The `writer` seam is
  what tests fake (the plugin's platform channel is dead under `flutter test`).
- `editor_screen.dart`: passes `onSnapshot:` to `PdfEditorView`, toasting
  "Snapshot copied to clipboard" / "Could not copy…". Added an
  `imageClipboardWriter` constructor seam, matching the existing
  `printDocument` / `updateService` test-injection pattern.
- `android/app/src/main/AndroidManifest.xml`: declared the
  `com.superlist.super_native_extensions.DataProvider` content provider —
  Android needs it for *image* clipboard writes (text works without it).
- `app/test/snapshot_clipboard_test.dart`: unit-tests the handler
  (success / writer-returns-false / writer-throws → all reported correctly)
  plus an integration test that drives the real Snapshot-tool drag through
  `PdfViewer` and asserts a real PNG (magic number `89 50 4E 47`) reaches the
  fake writer while the vector half still lands on the in-app clipboard.

## Gotcha: super_clipboard version is pinned to 0.1.7+6

The latest super_clipboard (0.8.x–0.9.x) can't resolve in this workspace:
its transitive `device_info_plus` caps `win32 < 6.0.0`, but `share_plus
^13.1.0` (used by the app *and* by `packages/.../example`, a dev-dep) needs
`win32 ^6.0.1`. Bumping share_plus down is blocked by the example package's
own `^13.1.0`, which is outside `/app`. The only super_clipboard that resolves
cleanly is `0.1.7+6` (its 0.1.x `super_native_extensions` doesn't pull
device_info_plus). That version's API is `ClipboardWriter.instance.write([...])`
(not the newer `SystemClipboard.instance`), but `Formats.png` + all-platform
support (incl. web) are present, so it's fully functional. If share_plus/the
example are ever realigned on win32 6, super_clipboard can move to 0.9.x — only
`copyPngToClipboard` needs the `SystemClipboard.instance` rename.

## Native build prerequisites (super_clipboard)

super_clipboard builds Rust during native app builds, so Windows/macOS/
Linux/Android/iOS releases need a Rust toolchain on the build machine (and
Android needs NDK). Pure-Dart / `flutter test` runs don't trigger it. The web
build needs nothing extra.
