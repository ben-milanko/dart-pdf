#ifndef RUNNER_WINDOWS_DROP_H_
#define RUNNER_WINDOWS_DROP_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <map>
#include <memory>

class DartPdfWindowsDropTarget;

// Per-HWND OLE file-drop registration for Flutter's engine-owned regular
// windows. The desktop_drop plugin can only discover an implicit registrar
// view, which does not exist in DartPDF's multi-window bootstrap.
class DartPdfWindowsDropService {
 public:
  explicit DartPdfWindowsDropService(flutter::BinaryMessenger* messenger);
  ~DartPdfWindowsDropService();

  DartPdfWindowsDropService(const DartPdfWindowsDropService&) = delete;
  DartPdfWindowsDropService& operator=(const DartPdfWindowsDropService&) =
      delete;

 private:
  bool Register(HWND window);
  void Unregister(HWND window);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::map<HWND, DartPdfWindowsDropTarget*> targets_;
  bool ole_initialized_ = false;
};

#endif  // RUNNER_WINDOWS_DROP_H_
