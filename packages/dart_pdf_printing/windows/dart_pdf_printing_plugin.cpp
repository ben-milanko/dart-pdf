#include "dart_pdf_printing_plugin.h"

#include <flutter/standard_method_codec.h>

#include <exception>
#include <thread>

namespace dart_pdf_printing {
namespace {
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

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  // First, find the length of the string with a safe upper bound (CWE-126).
  // A UNICODE_STRING contains at most 32767 characters.
  int input_length = static_cast<int>(wcsnlen(utf16_string, 32767));
  // Now use that bounded length to determine the required buffer size.
  // When an explicit length is passed, WideCharToMultiByte does not include
  // the null terminator in its returned size.
  int target_length =
      ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
                            input_length, nullptr, 0, nullptr, nullptr);
  std::string utf8_string;
  if (target_length == 0 ||
      static_cast<size_t>(target_length) > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(static_cast<size_t>(target_length));
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string, input_length,
      utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

std::optional<int64_t> Integer(const flutter::EncodableValue& value) {
  if (const auto* number = std::get_if<int64_t>(&value)) return *number;
  if (const auto* number = std::get_if<int32_t>(&value)) return *number;
  return std::nullopt;
}

std::wstring OptionalString(const flutter::EncodableMap* args,
                            const char* key) {
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
  if (duplex == L"longEdge")
    options.duplex = static_cast<short>(DMDUP_VERTICAL);
  if (duplex == L"shortEdge")
    options.duplex = static_cast<short>(DMDUP_HORIZONTAL);
  if (const auto* value = Lookup(*args, "tray")) {
    const auto tray = Integer(*value);
    if (tray.has_value() && *tray >= 0 && *tray <= 32767) {
      options.tray = static_cast<short>(*tray);
    }
  }
  return options;
}

flutter::EncodableValue PrinterSettingsPayload(
    const NativePrinter::Settings& settings) {
  flutter::EncodableList trays;
  for (const auto& tray : settings.trays) {
    trays.push_back(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("id"), flutter::EncodableValue(tray.id)},
        {flutter::EncodableValue("name"),
         flutter::EncodableValue(Utf8FromUtf16(tray.name.c_str()))},
    }));
  }
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("color"),
       flutter::EncodableValue(settings.color)},
      {flutter::EncodableValue("duplex"),
       flutter::EncodableValue(settings.duplex == DMDUP_VERTICAL ? "longEdge"
                               : settings.duplex == DMDUP_HORIZONTAL
                                   ? "shortEdge"
                                   : "simplex")},
      {flutter::EncodableValue("tray"), flutter::EncodableValue(settings.tray)},
      {flutter::EncodableValue("supportsColor"),
       flutter::EncodableValue(settings.supports_color)},
      {flutter::EncodableValue("supportsDuplex"),
       flutter::EncodableValue(settings.supports_duplex)},
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
  auto reply = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
      std::move(result));
  try {
    std::thread([list_printers, options = std::move(options), reply]() {
      const HRESULT initialized =
          ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
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
            destinations.push_back(
                flutter::EncodableValue(flutter::EncodableMap{
                    {flutter::EncodableValue("name"),
                     flutter::EncodableValue(
                         Utf8FromUtf16(destination.name.c_str()))},
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

}  // namespace

void DartPdfPrintingPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<DartPdfPrintingPlugin>(registrar);
  plugin->channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "dev.milanko.dart_pdf_printing",
          &flutter::StandardMethodCodec::GetInstance());
  plugin->channel_->SetMethodCallHandler(
      [instance = plugin.get()](const auto& call, auto result) {
        instance->HandleMethodCall(call, std::move(result));
      });
  registrar->AddPlugin(std::move(plugin));
}

DartPdfPrintingPlugin::DartPdfPrintingPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}
DartPdfPrintingPlugin::~DartPdfPrintingPlugin() {
  channel_->SetMethodCallHandler(nullptr);
  native_printer_.Cancel();
}

HWND DartPdfPrintingPlugin::OwnerWindow() const {
  // Engine-owned multi-window hosts may have no implicit FlutterView.
  HWND active = ::GetActiveWindow();
  if (active != nullptr) return active;
  auto* view = registrar_->GetView();
  return view == nullptr ? nullptr
                         : ::GetAncestor(view->GetNativeWindow(), GA_ROOT);
}

void DartPdfPrintingPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = call.arguments() == nullptr
                         ? nullptr
                         : std::get_if<flutter::EncodableMap>(call.arguments());
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
    const HWND owner = OwnerWindow();
    NativePrinter::Settings settings;
    if (!native_printer_.PrinterSettings(
            owner, options, call.method_name() == "printerProperties",
            &settings)) {
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
        {flutter::EncodableValue("vector"), flutter::EncodableValue(true)},
    }));
  } else if (call.method_name() == "printPage") {
    const flutter::EncodableValue* image_value =
        args == nullptr ? nullptr : Lookup(*args, "image");
    const auto* image = image_value == nullptr
                            ? nullptr
                            : std::get_if<std::vector<uint8_t>>(image_value);
    if (image == nullptr) {
      result->Error("bad_args", "printPage expects image bytes");
      return;
    }
    result->Success(flutter::EncodableValue(native_printer_.AddPage(*image)));
  } else if (call.method_name() == "printPageVector") {
    const flutter::EncodableValue* page_value =
        args == nullptr ? nullptr : Lookup(*args, "page");
    const auto* page = page_value == nullptr
                           ? nullptr
                           : std::get_if<std::vector<uint8_t>>(page_value);
    if (page == nullptr) {
      result->Error("bad_args", "printPageVector expects a byte stream");
      return;
    }
    result->Success(
        flutter::EncodableValue(native_printer_.AddVectorPage(*page)));
  } else if (call.method_name() == "endJob") {
    const HWND owner = OwnerWindow();
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
}
}  // namespace dart_pdf_printing
