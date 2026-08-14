#ifndef RUNNER_PLATFORM_CHANNELS_H_
#define RUNNER_PLATFORM_CHANNELS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <functional>
#include <memory>
#include <string>

#include "native_print.h"

// Engine-scoped DartPDF services shared by the normal single-view runner and
// Flutter's experimental engine-owned multi-window bootstrap.
class DartPdfPlatformChannels {
 public:
  using OwnerWindow = std::function<HWND()>;

  DartPdfPlatformChannels(std::wstring initial_file, OwnerWindow owner_window);
  ~DartPdfPlatformChannels();

  DartPdfPlatformChannels(const DartPdfPlatformChannels&) = delete;
  DartPdfPlatformChannels& operator=(const DartPdfPlatformChannels&) = delete;

  void Register(flutter::BinaryMessenger* messenger);
  void DeliverFileToFlutter(const std::wstring& path);

 private:
  std::wstring initial_file_;
  OwnerWindow owner_window_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      incoming_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      memory_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      image_clipboard_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      native_print_channel_;
  NativePrinter native_printer_;
};

#endif  // RUNNER_PLATFORM_CHANNELS_H_
