#include "platform_channels.h"

#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "image_clipboard.h"
#include "utils.h"

namespace {

constexpr char kIncomingChannelName[] = "dev.milanko.dartpdf/incoming";
constexpr char kImageClipboardChannelName[] =
    "dev.milanko.dartpdf/image_clipboard";
constexpr char kNativePrintChannelName[] =
    "dev.milanko.dartpdf/native_print";
constexpr char kMemoryChannelName[] = "dev.milanko.dartpdf/memory";

const flutter::EncodableValue* Lookup(const flutter::EncodableMap& map,
                                      const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

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

flutter::EncodableValue FilePayload(const std::wstring& path) {
  std::wstring name = path;
  size_t slash = path.find_last_of(L"/\\");
  if (slash != std::wstring::npos) name = path.substr(slash + 1);
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("name"),
       flutter::EncodableValue(Utf8FromUtf16(name.c_str()))},
      {flutter::EncodableValue("path"),
       flutter::EncodableValue(Utf8FromUtf16(path.c_str()))},
  });
}

}  // namespace

DartPdfPlatformChannels::DartPdfPlatformChannels(
    std::wstring initial_file, OwnerWindow owner_window)
    : initial_file_(std::move(initial_file)),
      owner_window_(std::move(owner_window)) {}

DartPdfPlatformChannels::~DartPdfPlatformChannels() = default;

void DartPdfPlatformChannels::Register(flutter::BinaryMessenger* messenger) {
  incoming_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kIncomingChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  incoming_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "getInitialFile") {
          result->NotImplemented();
          return;
        }
        if (initial_file_.empty()) {
          result->Success();
          return;
        }
        std::wstring path = initial_file_;
        initial_file_.clear();
        result->Success(FilePayload(path));
      });

  memory_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kMemoryChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  memory_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "snapshot") {
          result->NotImplemented();
          return;
        }
        MEMORYSTATUSEX status{};
        status.dwLength = sizeof(status);
        if (!::GlobalMemoryStatusEx(&status)) {
          result->Error("memory_snapshot_failed",
                        "GlobalMemoryStatusEx failed");
          return;
        }
        result->Success(flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("physicalBytes"),
             flutter::EncodableValue(
                 static_cast<int64_t>(status.ullTotalPhys))},
            {flutter::EncodableValue("availableBytes"),
             flutter::EncodableValue(
                 static_cast<int64_t>(status.ullAvailPhys))},
            {flutter::EncodableValue("lowMemory"),
             flutter::EncodableValue(status.dwMemoryLoad >= 90)},
        }));
      });

  image_clipboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kImageClipboardChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  image_clipboard_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const HWND owner = owner_window_ ? owner_window_() : nullptr;
        if (call.method_name() == "copyPng") {
          const auto* bytes =
              std::get_if<std::vector<uint8_t>>(call.arguments());
          if (bytes == nullptr) {
            result->Error("bad_args", "copyPng expects PNG bytes");
            return;
          }
          result->Success(flutter::EncodableValue(
              CopyPngToClipboard(owner, *bytes)));
        } else if (call.method_name() == "readImage") {
          std::optional<std::vector<uint8_t>> png =
              ReadImageFromClipboard(owner);
          if (png.has_value()) {
            result->Success(flutter::EncodableValue(std::move(*png)));
          } else {
            result->Success();
          }
        } else {
          result->NotImplemented();
        }
      });

  native_print_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kNativePrintChannelName,
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
            result->Error("bad_args",
                          "printPageVector expects a byte stream");
            return;
          }
          result->Success(
              flutter::EncodableValue(native_printer_.AddVectorPage(*page)));
        } else if (call.method_name() == "endJob") {
          const HWND owner = owner_window_ ? owner_window_() : nullptr;
          result->Success(
              flutter::EncodableValue(native_printer_.End(owner)));
        } else if (call.method_name() == "cancelJob") {
          native_printer_.Cancel();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

void DartPdfPlatformChannels::DeliverFileToFlutter(
    const std::wstring& path) {
  if (!incoming_channel_ || path.empty()) return;
  incoming_channel_->InvokeMethod(
      "openFile", std::make_unique<flutter::EncodableValue>(FilePayload(path)));
}
