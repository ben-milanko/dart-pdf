#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string.h>

#include <string>
#include <memory>
#include <vector>

#include "flutter_window.h"
#include "flutter/generated_plugin_registrant.h"
#include "platform_channels.h"
#include "utils.h"
#include "../../native/windowing_bootstrap.h"

namespace {

// Process-wide single-instance guard. A second launch hands its file to the
// already-running instance instead of opening a second window.
constexpr const wchar_t kSingleInstanceMutexName[] =
    L"dev.milanko.dartpdf.SingleInstance";

// Window class of the main window (see runner/win32_window.cpp); a second
// instance locates the running window by this class.
constexpr const wchar_t kMainWindowClassName[] = L"DARTPDF_WIN32_WINDOW";
constexpr const wchar_t kWindowingMessageClassName[] =
    L"DARTPDF_WINDOWING_MESSAGE_HOST";
constexpr UINT kSurfaceWindowingApp = WM_APP + 0x445;

bool ExperimentalWindowingEnabled() {
  return dart_pdf::FlutterWindowingEnabled();
}

// Returns the first `.pdf` path on the command line, or an empty string. This
// is how Windows delivers a file association / "open with" - the path is the
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

BOOL CALLBACK FindProcessWindow(HWND hwnd, LPARAM result) {
  DWORD process_id = 0;
  ::GetWindowThreadProcessId(hwnd, &process_id);
  if (process_id != ::GetCurrentProcessId() || !::IsWindowVisible(hwnd)) {
    return TRUE;
  }
  *reinterpret_cast<HWND*>(result) = hwnd;
  return FALSE;
}

HWND ActiveProcessWindow() {
  HWND active = ::GetActiveWindow();
  if (active != nullptr) return active;
  HWND result = nullptr;
  ::EnumWindows(FindProcessWindow, reinterpret_cast<LPARAM>(&result));
  return result;
}

void SurfaceWindowingApp() {
  if (HWND window = ActiveProcessWindow()) SurfaceWindow(window);
}

// Locates the main window of an already-running instance, retrying briefly to
// cover the race where the first instance owns the mutex but hasn't created
// its window yet.
HWND FindRunningInstanceWindow(bool experimental_windowing) {
  for (int attempt = 0; attempt < 50; attempt++) {
    HWND hwnd = experimental_windowing
                    ? ::FindWindowExW(HWND_MESSAGE, nullptr,
                                      kWindowingMessageClassName, nullptr)
                    : ::FindWindowW(kMainWindowClassName, nullptr);
    if (hwnd != nullptr) {
      return hwnd;
    }
    ::Sleep(100);
  }
  return nullptr;
}

class WindowingMessageHost {
 public:
  explicit WindowingMessageHost(DartPdfPlatformChannels* channels)
      : channels_(channels) {}

  bool Create(HINSTANCE instance) {
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = WindowProc;
    window_class.hInstance = instance;
    window_class.lpszClassName = kWindowingMessageClassName;
    if (::RegisterClassW(&window_class) == 0 &&
        ::GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      return false;
    }
    window_ = ::CreateWindowExW(
        0, kWindowingMessageClassName, nullptr, 0, 0, 0, 0, 0, HWND_MESSAGE,
        nullptr, instance, this);
    return window_ != nullptr;
  }

  ~WindowingMessageHost() {
    if (window_ != nullptr) ::DestroyWindow(window_);
  }

 private:
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam) {
    WindowingMessageHost* self = reinterpret_cast<WindowingMessageHost*>(
        ::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
      self = static_cast<WindowingMessageHost*>(create->lpCreateParams);
      ::SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                          reinterpret_cast<LONG_PTR>(self));
    }
    if (self == nullptr) return ::DefWindowProcW(hwnd, message, wparam, lparam);

    if (message == WM_COPYDATA) {
      auto* data = reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if (data != nullptr && data->dwData == kIncomingFileCopyDataMagic &&
          data->lpData != nullptr && data->cbData >= sizeof(wchar_t)) {
        const wchar_t* chars = static_cast<const wchar_t*>(data->lpData);
        const size_t max_chars = data->cbData / sizeof(wchar_t);
        self->channels_->DeliverFileToFlutter(
            std::wstring(chars, ::wcsnlen(chars, max_chars)));
      }
      SurfaceWindowingApp();
      return TRUE;
    }
    if (message == kSurfaceWindowingApp) {
      SurfaceWindowingApp();
      return 0;
    }
    return ::DefWindowProcW(hwnd, message, wparam, lparam);
  }

  DartPdfPlatformChannels* channels_;
  HWND window_ = nullptr;
};

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

  const bool experimental_windowing = ExperimentalWindowingEnabled();
  const std::wstring initial_file = FirstPdfArgument();

  // Single instance: if one is already running, hand it our file (so the
  // document opens in a new tab of the existing window) and exit. If we can't
  // find its window - it may be shutting down - fall through and start fresh.
  HANDLE single_instance =
      ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  const bool already_running =
      single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS;
  if (already_running) {
    HWND running = FindRunningInstanceWindow(experimental_windowing);
    if (running != nullptr) {
      // Let the running instance pull itself to the foreground past Windows'
      // foreground lock (it calls SetForegroundWindow when it handles the
      // forwarded file).
      ::AllowSetForegroundWindow(ASFW_ANY);
      if (!initial_file.empty()) {
        ForwardFileToRunningInstance(running, initial_file);
      }
      if (experimental_windowing) {
        ::SendMessageW(running, kSurfaceWindowingApp, 0, 0);
      } else {
        SurfaceWindow(running);
      }
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

  if (experimental_windowing) {
    auto engine = std::make_shared<flutter::FlutterEngine>(project);
    RegisterPlugins(engine.get());
    DartPdfPlatformChannels platform_channels(
        initial_file, []() { return ActiveProcessWindow(); });
    platform_channels.Register(engine->messenger());
    WindowingMessageHost message_host(&platform_channels);
    if (!message_host.Create(instance) || !engine->Run()) {
      if (single_instance != nullptr) ::CloseHandle(single_instance);
      ::CoUninitialize();
      return EXIT_FAILURE;
    }

    ::MSG msg;
    while (::GetMessage(&msg, nullptr, 0, 0)) {
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }

    if (single_instance != nullptr) ::CloseHandle(single_instance);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

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
