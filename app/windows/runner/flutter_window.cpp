#include "flutter_window.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <string.h>

#include <cstdint>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "image_clipboard.h"
#include "utils.h"

namespace {

// Reverse-DNS channel shared with the Dart IncomingFileService and every other
// platform runner (macOS/iOS/Android).
constexpr const char kIncomingChannelName[] = "dev.milanko.dartpdf/incoming";

// Reverse-DNS channel that carries Snapshot rasters to/from the OS clipboard,
// matching the macOS/Android runners (see image_clipboard.cpp).
constexpr const char kImageClipboardChannelName[] =
    "dev.milanko.dartpdf/image_clipboard";

// Reverse-DNS channel that streams page rasters to the GDI printer DC,
// bypassing the `printing` plugin's PDFium (see native_print.cpp).
constexpr const char kNativePrintChannelName[] =
    "dev.milanko.dartpdf/native_print";

// Looks up |key| in |map|, or returns null when absent.
const flutter::EncodableValue* Lookup(const flutter::EncodableMap& map,
                                      const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

// Converts a UTF-8 std::string to UTF-16, for Win32 wide APIs.
std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int len = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                  static_cast<int>(utf8.size()), nullptr, 0);
  if (len <= 0) return std::wstring();
  std::wstring utf16(static_cast<size_t>(len), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        utf16.data(), len);
  return utf16;
}

// Builds the {name, path} payload the Dart side's IncomingFileService decodes.
flutter::EncodableValue FilePayload(const std::wstring& path) {
  std::wstring name = path;
  size_t slash = path.find_last_of(L"/\\");
  if (slash != std::wstring::npos) {
    name = path.substr(slash + 1);
  }
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("name"),
       flutter::EncodableValue(Utf8FromUtf16(name.c_str()))},
      {flutter::EncodableValue("path"),
       flutter::EncodableValue(Utf8FromUtf16(path.c_str()))},
  });
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             std::wstring initial_file)
    : project_(project), initial_file_(std::move(initial_file)) {}

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

  // Bridge OS file opens to the Dart IncomingFileService. `getInitialFile`
  // drains the cold-start launch file; warm-start opens arrive as `openFile`
  // (see MessageHandler's WM_COPYDATA case).
  incoming_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kIncomingChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  incoming_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "getInitialFile") {
          if (initial_file_.empty()) {
            result->Success();
          } else {
            std::wstring path = initial_file_;
            initial_file_.clear();  // deliver the launch file exactly once
            result->Success(FilePayload(path));
          }
        } else {
          result->NotImplemented();
        }
      });

  // Bridge the Snapshot tool's PNG raster to the Win32 clipboard so it can be
  // pasted into other apps, and read images back for the paste providers.
  image_clipboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          kImageClipboardChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  image_clipboard_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "copyPng") {
          const auto* bytes =
              std::get_if<std::vector<uint8_t>>(call.arguments());
          if (bytes == nullptr) {
            result->Error("bad_args", "copyPng expects PNG bytes");
            return;
          }
          result->Success(flutter::EncodableValue(
              CopyPngToClipboard(GetHandle(), *bytes)));
        } else if (call.method_name() == "readImage") {
          std::optional<std::vector<uint8_t>> png =
              ReadImageFromClipboard(GetHandle());
          if (png.has_value()) {
            result->Success(flutter::EncodableValue(std::move(*png)));
          } else {
            result->Success();  // null: no image on the clipboard
          }
        } else {
          result->NotImplemented();
        }
      });

  // Bridge printing to a GDI printer DC so pages our own engine renders never
  // pass through the plugin's PDFium (which crashes on some documents). The
  // Dart side opens a job, streams one page bitmap at a time, then ends it.
  native_print_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kNativePrintChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  native_print_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (call.method_name() == "beginJob") {
          std::string name = "Document";
          if (args != nullptr) {
            if (const auto* value = Lookup(*args, "name")) {
              if (const auto* text = std::get_if<std::string>(value)) {
                if (!text->empty()) name = *text;
              }
            }
          }
          native_printer_.Begin(Utf16FromUtf8(name));
          // Report that this runner can replay the vector op stream, so the
          // Dart side sends `printPageVector` instead of rasterising. The dpi
          // is only used by the raster fallback (the printer's real dpi is not
          // known until the dialog at endJob), so 300 stays a sane default.
          result->Success(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue("dpi"), flutter::EncodableValue(300)},
              {flutter::EncodableValue("vector"),
               flutter::EncodableValue(true)},
          }));
        } else if (call.method_name() == "printPage") {
          const flutter::EncodableValue* image_value =
              args == nullptr ? nullptr : Lookup(*args, "image");
          const auto* image =
              image_value == nullptr
                  ? nullptr
                  : std::get_if<std::vector<uint8_t>>(image_value);
          if (image == nullptr) {
            result->Error("bad_args", "printPage expects image bytes");
            return;
          }
          result->Success(
              flutter::EncodableValue(native_printer_.AddPage(*image)));
        } else if (call.method_name() == "printPageVector") {
          const flutter::EncodableValue* page_value =
              args == nullptr ? nullptr : Lookup(*args, "page");
          const auto* page =
              page_value == nullptr
                  ? nullptr
                  : std::get_if<std::vector<uint8_t>>(page_value);
          if (page == nullptr) {
            result->Error("bad_args", "printPageVector expects a byte stream");
            return;
          }
          result->Success(
              flutter::EncodableValue(native_printer_.AddVectorPage(*page)));
        } else if (call.method_name() == "endJob") {
          result->Success(
              flutter::EncodableValue(native_printer_.End(GetHandle())));
        } else if (call.method_name() == "cancelJob") {
          native_printer_.Cancel();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

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
  if (!incoming_channel_ || path.empty()) {
    return;
  }
  incoming_channel_->InvokeMethod(
      "openFile", std::make_unique<flutter::EncodableValue>(FilePayload(path)));
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
