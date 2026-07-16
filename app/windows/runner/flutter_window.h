#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"

// Identifies WM_COPYDATA messages that carry a file path forwarded from a
// second instance of the app. The sender (runner/main.cpp) stamps the same
// value so unrelated WM_COPYDATA traffic is ignored.
constexpr ULONG_PTR kIncomingFileCopyDataMagic = 0x44504446;  // 'DPDF'

// A window that hosts a Flutter view and bridges OS file opens to Dart.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // |initial_file| is the document the app was launched with (cold start), or
  // empty; the Dart side drains it once via `getInitialFile`.
  explicit FlutterWindow(const flutter::DartProject& project,
                         std::wstring initial_file = L"");
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Hands a file path to the Dart IncomingFileService as a warm-start open
  // (a second instance forwarded it via WM_COPYDATA).
  void DeliverFileToFlutter(const std::wstring& path);

  // The project to run.
  flutter::DartProject project_;

  // The file the app was launched with, drained once by `getInitialFile`.
  // Empty when the app was launched without a file.
  std::wstring initial_file_;

  // Channel to the Dart IncomingFileService: cold-start `getInitialFile` and
  // warm-start `openFile`. Created once the engine exists in OnCreate.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      incoming_channel_;

  // Channel that copies Snapshot rasters to / reads images from the Win32
  // clipboard (`copyPng` / `readImage`). Created once the engine exists.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      image_clipboard_channel_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
