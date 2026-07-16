#ifndef RUNNER_IMAGE_CLIPBOARD_H_
#define RUNNER_IMAGE_CLIPBOARD_H_

#include <windows.h>

#include <cstdint>
#include <optional>
#include <vector>

// Native side of the `dev.milanko.dartpdf/image_clipboard` method channel.
// Flutter's built-in Clipboard only carries text, so putting a Snapshot raster
// on the OS clipboard needs Win32 code. The macOS/Android runners implement the
// same channel; Windows was the missing platform (snapshots reported "Could not
// copy snapshot to clipboard").

// Writes PNG-encoded |png| bytes to the Windows clipboard so a Snapshot can be
// pasted into other apps. The image is offered both as a registered "PNG"
// clipboard format (preferred by browsers and Office) and as a CF_DIBV5 bitmap
// (understood by Paint and other legacy consumers). |owner| owns the clipboard
// for the duration of the write. Returns true on success.
bool CopyPngToClipboard(HWND owner, const std::vector<uint8_t>& png);

// Reads an image off the Windows clipboard and returns it as PNG bytes, or
// std::nullopt when the clipboard holds no image (or the conversion fails).
std::optional<std::vector<uint8_t>> ReadImageFromClipboard(HWND owner);

#endif  // RUNNER_IMAGE_CLIPBOARD_H_
