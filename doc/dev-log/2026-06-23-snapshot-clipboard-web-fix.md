# Snapshot → clipboard: fix web ("Could not copy snapshot to clipboard")

Follow-up to `2026-06-22-snapshot-system-clipboard.md`. On the **web**
preview the Snapshot-tool copy always toasted *"Could not copy snapshot to
clipboard"* - `copyPngToClipboard` was throwing.

## Cause

super_clipboard is pinned to `0.1.7+6` (the win32/share_plus conflict - see
the prior note). Its transitive `super_native_extensions 0.1.8+2` ships a
**web** clipboard writer, but it's 2022-era: legacy `dart:html` +
`package:js`, building a `jsify()`'d `{mime: Promise<Blob>}` and calling
`navigator.clipboard.write`. That path is unreliable on modern Flutter web
(the jsify of an already-JS `Promise`/`Blob` map mangles the `ClipboardItem`
argument), so the write rejects and our handler reports a failed copy.

## Fix (web-only, still all in `/app`)

Bypass super_clipboard on web and call the Async Clipboard API directly with
modern interop. Split `copyPngToClipboard` behind a conditional import,
mirroring the app's existing `web_launch` stub/io/web pattern:

- `image_clipboard_io.dart` - native: super_clipboard (unchanged behaviour).
- `image_clipboard_web.dart` - web: `dart:js_interop` + `package:web`.
  Builds a `Blob([bytes], {type:'image/png'})`, a `ClipboardItem` from a
  `{ 'image/png': blob }` JS object (`setProperty` via
  `dart:js_interop_unsafe`), and `await navigator.clipboard.write([item])`.
- `image_clipboard.dart` - keeps `ImageClipboardWriter` +
  `clipboardSnapshotHandler`, and `import`/`export`s `copyPngToClipboard`
  via `if (dart.library.js_interop)`.
- Added `web: ^1.1.1` to `app/pubspec.yaml`.

super_clipboard stays for native platforms. `clipboardSnapshotHandler`'s
try/catch still turns any web rejection (insecure context, denied
permission, unsupported browser - Chromium-family browsers support image
clipboard writes; Firefox/Safari may not) into the failure toast.

## Verified

- `fvm dart analyze app` clean; `app` tests pass (the VM "default writer"
  test exercises the io variant). The injectable `imageClipboardWriter` seam
  means tests never touch real platform channels.
- `fvm flutter build web` compiles, **incl. the Wasm dry run** - so the
  js_interop/package:web path is valid for both JS and WASM web.

Note: the snapshot capture awaits a `toImage` PNG encode before the write.
Browser transient activation lasts ~5s, so a small region encodes well
within the window; if a very large/slow capture ever exceeds it, the write
would reject with `NotAllowedError` and toast the failure (acceptable).
