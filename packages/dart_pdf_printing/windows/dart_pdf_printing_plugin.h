#ifndef FLUTTER_PLUGIN_DART_PDF_PRINTING_PLUGIN_H_
#define FLUTTER_PLUGIN_DART_PDF_PRINTING_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

#include "native_print.h"

namespace dart_pdf_printing {

class DartPdfPrintingPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit DartPdfPrintingPlugin(flutter::PluginRegistrarWindows* registrar);

  virtual ~DartPdfPrintingPlugin();

  // Disallow copy and assign.
  DartPdfPrintingPlugin(const DartPdfPrintingPlugin&) = delete;
  DartPdfPrintingPlugin& operator=(const DartPdfPrintingPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  HWND OwnerWindow() const;
  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  NativePrinter native_printer_;
};

}  // namespace dart_pdf_printing

#endif  // FLUTTER_PLUGIN_DART_PDF_PRINTING_PLUGIN_H_
