# Paste on web — fix text paste (⌘V/Ctrl+V did nothing in the browser)

## Symptom

In the browser, ⌘V/Ctrl+V with something on the system clipboard (a copied
line of text, most commonly) pasted nothing — even after the browser's
clipboard-read permission prompt was accepted. Desktop pasted fine.

## Cause

`_pasteSystemClipboard` (`pdf_viewer.dart`) tries an image paste first, then
falls back to text via **Flutter's `Clipboard.getData(kTextPlain)`**. Two
problems compound on the web:

1. `Clipboard.getData` is unreliable on Flutter web — it does not read text
   back the way the platform-channel path does off-web.
2. Even where a browser read would work, the fallback is a **second**
   gesture-gated clipboard read: the image path already awaited
   `navigator.clipboard.read()` (which is what raises the permission prompt),
   and by the time the text read runs the transient user activation from the
   Ctrl+V keystroke is gone, so the browser rejects it.

So: image on the clipboard → pasted (single read, works). Text on the
clipboard → image read finds nothing, text read fails → nothing happens. The
permission prompt the user saw and accepted was the image read; the failure
was the silent text fallback.

## Fix

Bypass Flutter's web clipboard for text the same way `copyPngToClipboard`
already bypasses it for images (see `2026-06-23-snapshot-clipboard-web-fix.md`),
and read the clipboard **once** per paste so there is no second gesture-gated
call.

- New seam `PdfViewer.systemTextPasteProvider`
  (`PdfSystemTextPasteProvider`, in `text_prompt.dart`), threaded through
  `PdfEditorView`. `_pasteSystemClipboardText` uses it in preference to
  `Clipboard.getData` when set; unset keeps the old Flutter-clipboard path
  (native still works through it, and existing tests are unchanged).
- App wires it (`editor_screen.dart`) via a conditional-import
  `readTextFromClipboard`, behind a `textClipboardReader` test seam mirroring
  `imageClipboardReader`:
  - `image_clipboard_io.dart` — native: delegates to `Clipboard.getData`.
  - `image_clipboard_web.dart` — web: `navigator.clipboard.read()` through
    `package:web`, extracting `text/plain` (`Blob.text()`).
- **Single read shared across the pair.** A paste calls the image reader then
  the text reader. On web `readImageFromClipboard` now does one
  `navigator.clipboard.read()`, extracts both image (png/jpeg) and text, and
  stashes the result; `readTextFromClipboard` consumes that stash instead of
  reading again. The image reader always runs first and overwrites the stash,
  so the text reader never sees a stale payload; a lone text read (no image
  provider) reads directly.

## Verified

- `fvm dart analyze packages/dart_pdf_editor app` clean.
- `fvm flutter build web` compiles, **incl. the Wasm dry run**, so the
  `Blob.text()` js_interop path is valid for JS and WASM.
- `editing_clipboard_test.dart`: text provider preferred over the platform
  channel (channel never touched), and the no-image → text fallthrough (the
  web case) pastes a FreeText box. `snapshot_clipboard_test.dart`: the default
  native text reader reads Flutter's clipboard.

The browser still needs a secure context and the clipboard-read permission; a
denied read surfaces as null (silent no-op), unchanged.
