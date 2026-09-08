#include "platform_channels.h"

#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <exception>
#include <optional>
#include <string>
#include <thread>
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
constexpr char kFileAccessChannelName[] =
    "dev.milanko.dartpdf/file_access";

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

NativePrinter::Options PrintOptions(const flutter::EncodableMap* args) {
  NativePrinter::Options options;
  options.printer = OptionalString(args, "printer");
  if (args == nullptr) return options;
  if (const auto* value = Lookup(*args, "color")) {
    if (const auto* color = std::get_if<bool>(value)) options.color = *color;
  }
  const std::wstring duplex = OptionalString(args, "duplex");
  if (duplex == L"simplex") options.duplex = static_cast<short>(DMDUP_SIMPLEX);
  if (duplex == L"longEdge") options.duplex = static_cast<short>(DMDUP_VERTICAL);
  if (duplex == L"shortEdge") options.duplex = static_cast<short>(DMDUP_HORIZONTAL);
  if (const auto* value = Lookup(*args, "tray")) {
    const auto tray = Integer(*value);
    if (tray.has_value() && *tray >= 0 && *tray <= 32767) {
      options.tray = static_cast<short>(*tray);
    }
  }
  return options;
}

flutter::EncodableValue PrinterSettingsPayload(const NativePrinter::Settings& settings) {
  flutter::EncodableList trays;
  for (const auto& tray : settings.trays) {
    trays.push_back(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("id"), flutter::EncodableValue(tray.id)},
        {flutter::EncodableValue("name"),
         flutter::EncodableValue(Utf8FromUtf16(tray.name.c_str()))},
    }));
  }
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("color"), flutter::EncodableValue(settings.color)},
      {flutter::EncodableValue("duplex"),
       flutter::EncodableValue(settings.duplex == DMDUP_VERTICAL ? "longEdge" :
                               settings.duplex == DMDUP_HORIZONTAL ? "shortEdge" : "simplex")},
      {flutter::EncodableValue("tray"), flutter::EncodableValue(settings.tray)},
      {flutter::EncodableValue("supportsColor"), flutter::EncodableValue(settings.supports_color)},
      {flutter::EncodableValue("supportsDuplex"), flutter::EncodableValue(settings.supports_duplex)},
      {flutter::EncodableValue("trays"), flutter::EncodableValue(trays)},
  });
}

// Flutter's desktop client wrapper owns the messenger reference behind each
// MethodResult. Its reply callback is explicitly safe on any thread: it locks
// the messenger and drops a late reply if the engine has already been destroyed
// (client_wrapper/core_implementations.cc, ForwardToHandler). Each query owns a
// separate NativePrinter and captures no channel service or window pointer.
// Slow/unreachable network printer drivers therefore cannot freeze the window,
// race a print job, or retain a dangling service when the window closes.
void QueryPrintersAsync(
    bool list_printers, NativePrinter::Options options,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto reply =
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
  try {
    std::thread([list_printers, options = std::move(options), reply]() {
      const HRESULT initialized = ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
      if (FAILED(initialized)) {
        reply->Error("print_failed", "Could not initialize the printer query");
        return;
      }
      struct ComScope {
        ~ComScope() { ::CoUninitialize(); }
      } com_scope;
      try {
        NativePrinter printer;
        if (list_printers) {
          std::vector<NativePrinter::Destination> printers;
          if (!printer.ListPrinters(&printers)) {
            reply->Error("print_failed", printer.error());
            return;
          }
          flutter::EncodableList destinations;
          for (const auto& destination : printers) {
            destinations.push_back(flutter::EncodableValue(flutter::EncodableMap{
                {flutter::EncodableValue("name"),
                 flutter::EncodableValue(Utf8FromUtf16(destination.name.c_str()))},
                {flutter::EncodableValue("isDefault"),
                 flutter::EncodableValue(destination.is_default)},
            }));
          }
          reply->Success(flutter::EncodableValue(destinations));
        } else {
          NativePrinter::Settings settings;
          if (!printer.PrinterSettings(nullptr, options, false, &settings)) {
            reply->Error("print_failed", printer.error());
            return;
          }
          reply->Success(PrinterSettingsPayload(settings));
        }
      } catch (const std::exception& error) {
        reply->Error("print_failed", error.what());
      }
    }).detach();
  } catch (const std::exception& error) {
    reply->Error("print_failed", error.what());
  }
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
        } else if (call.method_name() == "markLocalCopy") {
          MarkLocalClipboardCopy();
          result->Success();
        } else if (call.method_name() == "copySnapshot") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          const auto* pdf_value = args ? Lookup(*args, "pdf") : nullptr;
          const auto* png_value = args ? Lookup(*args, "png") : nullptr;
          const auto* pdf = pdf_value ? std::get_if<std::vector<uint8_t>>(pdf_value) : nullptr;
          const auto* png = png_value ? std::get_if<std::vector<uint8_t>>(png_value) : nullptr;
          if (pdf == nullptr || png == nullptr) {
            result->Error("bad_args", "copySnapshot expects PDF and PNG bytes");
            return;
          }
          result->Success(flutter::EncodableValue(
              CopySnapshotToClipboard(owner, *pdf, *png)));
        } else if (call.method_name() == "readPdf") {
          auto pdf = ReadExternalPdfFromClipboard(owner);
          if (pdf.has_value()) {
            result->Success(flutter::EncodableValue(flutter::EncodableMap{
                {flutter::EncodableValue("pdf"), flutter::EncodableValue(std::move(pdf->bytes))},
                {flutter::EncodableValue("changeToken"), flutter::EncodableValue(static_cast<int64_t>(pdf->sequence))},
            }));
          } else {
            result->Success();
          }
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
        if (call.method_name() == "listPrinters") {
          QueryPrintersAsync(true, {}, std::move(result));
        } else if (call.method_name() == "printerSettings" ||
                   call.method_name() == "printerProperties") {
          const auto options = PrintOptions(args);
          if (options.printer.empty()) {
            result->Error("bad_args", "Printer settings require a printer name");
            return;
          }
          if (call.method_name() == "printerSettings") {
            QueryPrintersAsync(false, options, std::move(result));
            return;
          }
          const HWND owner = owner_window_ ? owner_window_() : nullptr;
          NativePrinter::Settings settings;
          if (!native_printer_.PrinterSettings(
                  owner, options, call.method_name() == "printerProperties", &settings)) {
            if (native_printer_.error().empty()) {
              result->Success();  // The driver's Preferences dialog was cancelled.
            } else {
              result->Error("print_failed", native_printer_.error());
            }
            return;
          }
          result->Success(PrinterSettingsPayload(settings));
        } else if (call.method_name() == "beginJob") {
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
          const auto options = PrintOptions(args);
          if (args != nullptr && Lookup(*args, "printer") != nullptr &&
              options.printer.empty()) {
            result->Error("bad_args", "Direct printing requires a printer name");
            return;
          }
          if (!native_printer_.Begin(Utf16FromUtf8(name), use_document_page_size,
                                     options)) {
            result->Error("print_failed", native_printer_.error());
            return;
          }
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
          const bool printed = native_printer_.End(owner);
          if (!printed && !native_printer_.error().empty()) {
            result->Error("print_failed", native_printer_.error());
          } else {
            result->Success(flutter::EncodableValue(printed));
          }
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

  // Revealing a saved document in File Explorer. url_launcher can only ask the
  // shell to "open" the containing folder, which Explorer is free to serve
  // from a window it already has - so a document saved to a new folder could
  // surface the one the user was looking at before. Naming the item leaves
  // nothing to guess, and selects the file the way Finder does on macOS (the
  // Dart side shares that channel's `revealFile`; see lib/file_io.dart).
  file_access_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kFileAccessChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  file_access_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "revealFile") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        const std::wstring path = OptionalString(args, "path");
        if (path.empty()) {
          result->Error("bad_args", "revealFile expects a path");
          return;
        }
        result->Success(
            flutter::EncodableValue(dart_pdf::RevealFileInExplorer(path)));
      });
}

void DartPdfPlatformChannels::DeliverFileToFlutter(
    const std::wstring& path) {
  if (!incoming_channel_ || path.empty()) return;
  incoming_channel_->InvokeMethod(
      "openFile", std::make_unique<flutter::EncodableValue>(FilePayload(path)));
}
