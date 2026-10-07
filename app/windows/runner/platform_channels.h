#ifndef RUNNER_PLATFORM_CHANNELS_H_
#define RUNNER_PLATFORM_CHANNELS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "file_dialogs.h"
#include "trackpad_signature.h"

class DartPdfWindowsDropService;

// A file the OS handed DartPDF, and whether it came from Explorer's "Combine
// with DartPDF" verb (`--combine`), which marks it to combine with the rest
// of its batch.
struct DartPdfIncomingFile {
  std::wstring path;
  bool combine = false;
};

// Engine-scoped DartPDF services shared by the normal single-view runner and
// Flutter's experimental engine-owned multi-window bootstrap.
class DartPdfPlatformChannels {
 public:
  using OwnerWindow = std::function<HWND()>;

  DartPdfPlatformChannels(std::vector<DartPdfIncomingFile> initial_files,
                          OwnerWindow owner_window);
  ~DartPdfPlatformChannels();

  DartPdfPlatformChannels(const DartPdfPlatformChannels&) = delete;
  DartPdfPlatformChannels& operator=(const DartPdfPlatformChannels&) = delete;

  void Register(flutter::BinaryMessenger* messenger);
  // Queues a file forwarded by a second instance for Dart. Files that arrive
  // close together go to Dart as one `openFiles` batch (see
  // ArmIncomingFlush).
  void DeliverFileToFlutter(const std::wstring& path, bool combine = false);

 private:
  // Explorer starts one process per selected file for a multi-file "Open",
  // and each forwards its file here as it comes up. Waiting until none has
  // arrived for this long lets them reach Dart as one batch, which offers to
  // combine them.
  static constexpr UINT kIncomingSettleMs = 500;

  void ArmIncomingFlush();
  void FlushIncomingFiles();
  static void CALLBACK OnIncomingFlushTimer(HWND, UINT, UINT_PTR, DWORD);
  // The instance the thread timer above reports to (one per process).
  static DartPdfPlatformChannels* incoming_owner_;

  OwnerWindow owner_window_;

  // Launch files, then forwarded ones, not yet handed to Dart.
  std::vector<DartPdfIncomingFile> pending_files_;
  // True once Dart's `getInitialFiles` has been answered; until then nothing
  // can be pushed (Dart's handler may not exist yet).
  bool dart_incoming_ready_ = false;
  // The held `getInitialFiles` call, answered when the batch settles so files
  // forwarded during a cold multi-file launch join the launch file.
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
      initial_files_result_;
  UINT_PTR incoming_flush_timer_ = 0;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      incoming_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      memory_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_geometry_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      image_clipboard_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      file_dialog_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      file_access_channel_;
  std::unique_ptr<DartPdfWindowsDropService> windows_drop_service_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      trackpad_support_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      trackpad_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> trackpad_sink_;
  dart_pdf::TrackpadSignatureCapture trackpad_capture_;
};

#endif  // RUNNER_PLATFORM_CHANNELS_H_
