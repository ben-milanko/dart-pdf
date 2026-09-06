#include "platform_channels.h"

#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "file_dialogs.h"
#include "image_clipboard.h"
#include "utils.h"
#include "windows_drop.h"

namespace {

constexpr char kIncomingChannelName[] = "dev.milanko.dartpdf/incoming";
constexpr char kImageClipboardChannelName[] =
    "dev.milanko.dartpdf/image_clipboard";
constexpr char kNativePrintChannelName[] =
    "dev.milanko.dartpdf/native_print";
constexpr char kMemoryChannelName[] = "dev.milanko.dartpdf/memory";
constexpr char kWindowGeometryChannelName[] =
    "dev.milanko.dartpdf/window_geometry";
constexpr char kFileDialogChannelName[] =
    "dev.milanko.dartpdf/file_dialogs";

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

std::optional<int64_t> Integer(const flutter::EncodableValue& value) {
  if (const auto* number = std::get_if<int64_t>(&value)) return *number;
  if (const auto* number = std::get_if<int32_t>(&value)) return *number;
  return std::nullopt;
}

std::wstring OptionalString(const flutter::EncodableMap* args, const char* key) {
  if (args == nullptr) return std::wstring();
  const auto* value = Lookup(*args, key);
  if (value == nullptr) return std::wstring();
  const auto* text = std::get_if<std::string>(value);
  return text == nullptr ? std::wstring() : Utf16FromUtf8(*text);
}

// Decodes the `acceptedTypeGroups` argument: a list of
// `{label: String, extensions: [String]}` maps. Unusable entries are skipped
// rather than failing the call - a dialog with one filter missing is far
// better than no dialog.
std::vector<dart_pdf::FileTypeFilter> DecodeFilters(
    const flutter::EncodableMap* args) {
  std::vector<dart_pdf::FileTypeFilter> filters;
  if (args == nullptr) return filters;
  const auto* groups_value = Lookup(*args, "acceptedTypeGroups");
  const auto* groups =
      groups_value == nullptr
          ? nullptr
          : std::get_if<flutter::EncodableList>(groups_value);
  if (groups == nullptr) return filters;
  for (const auto& group_value : *groups) {
    const auto* group = std::get_if<flutter::EncodableMap>(&group_value);
    if (group == nullptr) continue;
    dart_pdf::FileTypeFilter filter;
    if (const auto* label = Lookup(*group, "label")) {
      if (const auto* text = std::get_if<std::string>(label)) {
        filter.label = Utf16FromUtf8(*text);
      }
    }
    if (const auto* extensions = Lookup(*group, "extensions")) {
      if (const auto* list = std::get_if<flutter::EncodableList>(extensions)) {
        for (const auto& extension : *list) {
          const auto* text = std::get_if<std::string>(&extension);
          if (text != nullptr && !text->empty()) {
            filter.extensions.push_back(Utf16FromUtf8(*text));
          }
        }
      }
    }
    if (filter.label.empty()) continue;
    filters.push_back(std::move(filter));
  }
  return filters;
}

dart_pdf::FileDialogRequest DecodeDialogRequest(
    const flutter::EncodableMap* args) {
  dart_pdf::FileDialogRequest request;
  request.filters = DecodeFilters(args);
  request.initial_directory = OptionalString(args, "initialDirectory");
  request.suggested_name = OptionalString(args, "suggestedName");
  request.confirm_button_text = OptionalString(args, "confirmButtonText");
  return request;
}

// The reply shape shared by all three dialog methods: the chosen paths (empty
// when the user cancelled) plus the one-based index of the active type filter.
flutter::EncodableValue DialogPayload(const dart_pdf::FileDialogResult& result) {
  flutter::EncodableList paths;
  paths.reserve(result.paths.size());
  for (const std::wstring& path : result.paths) {
    paths.push_back(flutter::EncodableValue(Utf8FromUtf16(path.c_str())));
  }
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("paths"), flutter::EncodableValue(paths)},
      {flutter::EncodableValue("filterIndex"),
       flutter::EncodableValue(static_cast<int64_t>(result.filter_index))},
  });
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
  windows_drop_service_ =
      std::make_unique<DartPdfWindowsDropService>(messenger);
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

  window_geometry_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kWindowGeometryChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  window_geometry_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "locateDrop") {
          result->NotImplemented();
          return;
        }
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        const auto* handles_value =
            args == nullptr ? nullptr : Lookup(*args, "handles");
        const auto* handles = handles_value == nullptr
                                  ? nullptr
                                  : std::get_if<flutter::EncodableList>(
                                        handles_value);
        if (handles == nullptr) {
          result->Error("bad_args", "locateDrop expects a handles list");
          return;
        }

        POINT point{};
        if (!::GetCursorPos(&point)) {
          result->Success();
          return;
        }
        HWND hit = ::WindowFromPoint(point);
        if (hit != nullptr) hit = ::GetAncestor(hit, GA_ROOT);
        bool registered = false;
        for (const auto& value : *handles) {
          const auto address = Integer(value);
          if (address.has_value() &&
              reinterpret_cast<HWND>(static_cast<intptr_t>(*address)) == hit) {
            registered = true;
            break;
          }
        }
        if (!registered || hit == nullptr || !::ScreenToClient(hit, &point)) {
          result->Success();
          return;
        }

        const UINT dpi = ::GetDpiForWindow(hit);
        const double scale = dpi == 0 ? 1.0 : static_cast<double>(dpi) / 96.0;
        result->Success(flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("handle"),
             flutter::EncodableValue(
                 static_cast<int64_t>(reinterpret_cast<intptr_t>(hit)))},
            {flutter::EncodableValue("x"),
             flutter::EncodableValue(point.x / scale)},
            {flutter::EncodableValue("y"),
             flutter::EncodableValue(point.y / scale)},
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
          bool use_document_page_size = false;
          if (args != nullptr) {
            if (const auto* value = Lookup(*args, "useDocumentPageSize")) {
              if (const auto* enabled = std::get_if<bool>(value)) {
                use_document_page_size = *enabled;
              }
            }
            if (const auto* value = Lookup(*args, "name")) {
              if (const auto* text = std::get_if<std::string>(value)) {
                if (!text->empty()) name = *text;
              }
            }
          }
          native_printer_.Begin(Utf16FromUtf8(name), use_document_page_size);
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

  // Native common-item dialogs. `file_selector_windows` derives the dialog
  // owner from the registrar's implicit FlutterView, which the engine-owned
  // multi-window bootstrap deliberately does not create - the plugin then
  // dereferences a null view and takes the process down the first time the
  // user opens or saves a file. The runner already knows the active window,
  // so DartPDF drives the dialogs itself (see lib/windows_file_dialogs.dart).
  file_dialog_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kFileDialogChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  file_dialog_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        const bool save = method == "getSaveLocation";
        const bool folders = method == "getDirectoryPath" ||
                             method == "getDirectoryPaths";
        const bool multiple =
            method == "openFiles" || method == "getDirectoryPaths";
        if (!save && !folders && method != "openFile" &&
            method != "openFiles") {
          result->NotImplemented();
          return;
        }

        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        dart_pdf::FileDialogRequest request = DecodeDialogRequest(args);
        request.allow_multiple = multiple;
        request.select_folders = folders;

        const HWND owner = owner_window_ ? owner_window_() : nullptr;
        const dart_pdf::FileDialogResult dialog =
            save ? dart_pdf::ShowSaveFileDialog(owner, request)
                 : dart_pdf::ShowOpenFileDialog(owner, request);
        if (!dialog.shown) {
          result->Error(
              "file_dialog_failed", "Could not show the file dialog",
              flutter::EncodableValue(std::in_place_type<int32_t>,
                                      static_cast<int32_t>(dialog.error)));
          return;
        }
        result->Success(DialogPayload(dialog));
      });
}

void DartPdfPlatformChannels::DeliverFileToFlutter(
    const std::wstring& path) {
  if (!incoming_channel_ || path.empty()) return;
  incoming_channel_->InvokeMethod(
      "openFile", std::make_unique<flutter::EncodableValue>(FilePayload(path)));
}
