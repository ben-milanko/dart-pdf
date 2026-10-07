#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>
#include <string>
#include <vector>

#include "platform_channels.h"
#include "win32_window.h"

// Identifies WM_COPYDATA messages that carry a file path forwarded from a
// second instance of the app. The sender (runner/main.cpp) stamps the same
// value so unrelated WM_COPYDATA traffic is ignored.
constexpr ULONG_PTR kIncomingFileCopyDataMagic = 0x44504446;  // 'DPDF'
// The same, for a file from Explorer's "Combine with DartPDF" verb.
constexpr ULONG_PTR kIncomingCombineCopyDataMagic = 0x44504443;  // 'DPDC'

// A window that hosts a Flutter view and bridges OS file opens to Dart.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // |initial_files| are the documents the app was launched with (cold start);
  // the Dart side drains them once via `getInitialFiles`.
  explicit FlutterWindow(const flutter::DartProject& project,
                         std::vector<DartPdfIncomingFile> initial_files = {});
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
  void DeliverFileToFlutter(const std::wstring& path, bool combine);

  // The project to run.
  flutter::DartProject project_;

  DartPdfPlatformChannels platform_channels_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
