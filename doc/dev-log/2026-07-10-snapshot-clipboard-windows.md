# Snapshot → clipboard: implement the Windows native channel

**Bug (1.4.0, Windows):** taking a Snapshot toasts "Could not copy snapshot
to clipboard".

## Root cause

`c7f63c1` ("remove super_clipboard dependency") replaced the cross-platform
`super_clipboard` writer with an app-owned method channel,
`dev.milanko.dartpdf/image_clipboard` (`copyPng` / `readImage`, see
`app/lib/image_clipboard_io.dart`). Native handlers were added for **macOS**
(`MainFlutterWindow.swift`) and **Android** (`ImageClipboardProvider.kt`), but
**Windows and Linux got none**. On Windows the `copyPng` invocation therefore
throws `MissingPluginException`; `clipboardSnapshotHandler` catches it, reports
`copied = false`, and the screen toasts the failure. (Web is fine - it uses the
Async Clipboard API directly in `image_clipboard_web.dart`.)

## Fix (Windows runner only)

New `app/windows/runner/image_clipboard.{h,cpp}` implement the channel with
Win32 + WIC:

- **`CopyPngToClipboard`** decodes the PNG through WIC
  (`GUID_WICPixelFormat32bppBGRA`), then places **two** clipboard formats so a
  paste works everywhere: a registered `"PNG"` format (the raw bytes - what
  browsers/Office prefer) and a `CF_DIBV5` bottom-up BGRA bitmap with the alpha
  mask set (Paint and legacy consumers). Returns true if either format was
  accepted; frees any handle `SetClipboardData` rejects (it only takes
  ownership on success).
- **`ReadImageFromClipboard`** (for the paste providers, matching macOS's
  `readImage`) prefers the registered `"PNG"` format, else re-encodes the
  system-synthesized `CF_BITMAP` (`CreateBitmapFromHBITMAP`,
  `WICBitmapIgnoreAlpha` so DDB-derived bitmaps with a zeroed alpha don't come
  back fully transparent) to PNG.

Wiring:

- `flutter_window.cpp` `OnCreate` registers the channel next to the existing
  `incoming` channel, dispatching `copyPng`/`readImage` to the helpers with
  `GetHandle()` as the clipboard owner. `flutter_window.h` holds the new
  `image_clipboard_channel_` member.
- `CMakeLists.txt` compiles `image_clipboard.cpp` and links
  `windowscodecs.lib` + `ole32.lib` (WIC + `CreateStreamOnHGlobal`). COM is
  already initialized process-wide in `wWinMain`
  (`CoInitializeEx(COINIT_APARTMENTTHREADED)`), and the channel handler runs on
  that same UI thread.

## Not touched

Linux has the identical gap (no `fl_method_channel` handler in
`my_application.cc`); left for a follow-up since the report and this branch are
Windows-scoped. The Dart side, macOS, Android, and web are unchanged.
