#include "include/dart_pdf_printing/dart_pdf_printing_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "dart_pdf_printing_plugin.h"

void DartPdfPrintingPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  dart_pdf_printing::DartPdfPrintingPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
