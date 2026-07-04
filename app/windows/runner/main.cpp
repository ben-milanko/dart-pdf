#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Process-wide single-instance guard. A second launch hands its file to the
// already-running instance instead of opening a second window.
constexpr const wchar_t kSingleInstanceMutexName[] =
    L"dev.milanko.dartpdf.SingleInstance";

// Window class of the main window (see runner/win32_window.cpp); a second
// instance locates the running window by this class.
constexpr const wchar_t kMainWindowClassName[] = L"DARTPDF_WIN32_WINDOW";

// Returns the first `.pdf` path on the command line, or an empty string. This
// is how Windows delivers a file association / "open with" — the path is the
// first argument after the executable.
std::wstring FirstPdfArgument() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::wstring();
  }
  std::wstring result;
  for (int i = 1; i < argc; i++) {
    std::wstring arg = argv[i];
    if (arg.size() >= 4 &&
        _wcsicmp(arg.c_str() + (arg.size() - 4), L".pdf") == 0) {
      result = arg;
      break;
    }
  }
  ::LocalFree(argv);
  return result;
}

// Brings an existing window to the foreground, restoring it if minimized.
void SurfaceWindow(HWND hwnd) {
  if (::IsIconic(hwnd)) {
    ::ShowWindow(hwnd, SW_RESTORE);
  }
  ::SetForegroundWindow(hwnd);
}

// Locates the main window of an already-running instance, retrying briefly to
// cover the race where the first instance owns the mutex but hasn't created
// its window yet.
HWND FindRunningInstanceWindow() {
  for (int attempt = 0; attempt < 50; attempt++) {
    HWND hwnd = ::FindWindowW(kMainWindowClassName, nullptr);
    if (hwnd != nullptr) {
      return hwnd;
    }
    ::Sleep(100);
  }
  return nullptr;
}

// Hands |path| to the running instance via WM_COPYDATA so it opens in a new tab.
void ForwardFileToRunningInstance(HWND target, const std::wstring& path) {
  COPYDATASTRUCT cds{};
  cds.dwData = kIncomingFileCopyDataMagic;
  cds.cbData = static_cast<DWORD>((path.size() + 1) * sizeof(wchar_t));
  cds.lpData = const_cast<wchar_t*>(path.c_str());
  ::SendMessageW(target, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&cds));
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  const std::wstring initial_file = FirstPdfArgument();

  // Single instance: if one is already running, hand it our file (so the
  // document opens in a new tab of the existing window) and exit. If we can't
  // find its window — it may be shutting down — fall through and start fresh.
  HANDLE single_instance =
      ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  const bool already_running =
      single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS;
  if (already_running) {
    HWND running = FindRunningInstanceWindow();
    if (running != nullptr) {
      // Let the running instance pull itself to the foreground past Windows'
      // foreground lock (it calls SetForegroundWindow when it handles the
      // forwarded file).
      ::AllowSetForegroundWindow(ASFW_ANY);
      if (!initial_file.empty()) {
        ForwardFileToRunningInstance(running, initial_file);
      }
      SurfaceWindow(running);
      if (single_instance != nullptr) {
        ::CloseHandle(single_instance);
      }
      ::CoUninitialize();
      return EXIT_SUCCESS;
    }
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, initial_file);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"DartPDF", origin, size)) {
    if (single_instance != nullptr) {
      ::CloseHandle(single_instance);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance != nullptr) {
    ::CloseHandle(single_instance);
  }
  return EXIT_SUCCESS;
}
