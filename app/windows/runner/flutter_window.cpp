#include "flutter_window.h"

#include <string.h>

#include <optional>
#include <string>
#include <utility>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             std::wstring initial_file)
    : project_(project),
      platform_channels_(std::move(initial_file),
                         [this]() { return GetHandle(); }) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  platform_channels_.Register(flutter_controller_->engine()->messenger());

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::DeliverFileToFlutter(const std::wstring& path) {
  platform_channels_.DeliverFileToFlutter(path);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;

    case WM_COPYDATA: {
      // A second instance forwarded a file to open in a new tab (see
      // runner/main.cpp). Decode the path and hand it to Dart, then surface
      // this window so the user sees the freshly opened document.
      auto* cds = reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if (cds != nullptr && cds->dwData == kIncomingFileCopyDataMagic &&
          cds->lpData != nullptr && cds->cbData >= sizeof(wchar_t)) {
        const wchar_t* data = reinterpret_cast<const wchar_t*>(cds->lpData);
        size_t max_chars = cds->cbData / sizeof(wchar_t);
        std::wstring path(data, ::wcsnlen(data, max_chars));
        if (!path.empty()) {
          DeliverFileToFlutter(path);
          if (::IsIconic(hwnd)) {
            ::ShowWindow(hwnd, SW_RESTORE);
          }
          ::SetForegroundWindow(hwnd);
        }
      }
      return TRUE;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
