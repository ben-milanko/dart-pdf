// Explorer "Combine with DartPDF" for the Microsoft Store (MSIX) build.
//
// Packaged apps can't add classic registry verbs, so the Store package
// registers this IExplorerCommand handler instead (msix_config: context_menu in
// app/pubspec.yaml; the package hosts it in a COM surrogate). That also puts
// the entry in Windows 11's top-level context menu, and Explorer hands it the
// whole selection at once. It launches dart_pdf_editor_app.exe --combine with
// every selected file; the runner treats that like the NSIS verb's per-file
// `--combine` launches (see runner/main.cpp).

#include <windows.h>
#include <shlwapi.h>
#include <shobjidl_core.h>
#include <wrl/client.h>
#include <wrl/implements.h>
#include <wrl/module.h>

#include <string>
#include <vector>

using Microsoft::WRL::ClassicCom;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::InProc;
using Microsoft::WRL::Module;
using Microsoft::WRL::RuntimeClass;
using Microsoft::WRL::RuntimeClassFlags;

namespace {

HMODULE g_module = nullptr;

constexpr wchar_t kTitle[] = L"Combine with DartPDF";
constexpr wchar_t kExecutable[] = L"dart_pdf_editor_app.exe";
// IDI_APP_ICON in runner/resource.h.
constexpr wchar_t kIconResource[] = L",-101";
// CreateProcess caps a command line at 32,767 characters.
constexpr size_t kMaxCommandLine = 32000;

// The package folder: this DLL sits beside the app's executable.
std::wstring ModuleDirectory() {
  std::wstring path(MAX_PATH, L'\0');
  for (;;) {
    const DWORD length = ::GetModuleFileNameW(
        g_module, path.data(), static_cast<DWORD>(path.size()));
    if (length == 0) return std::wstring();
    if (length < path.size()) {
      path.resize(length);
      break;
    }
    path.resize(path.size() * 2);
  }
  const size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring() : path.substr(0, slash);
}

// Appends |arg| as one CommandLineToArgvW argument.
void AppendQuoted(std::wstring& command_line, const std::wstring& arg) {
  command_line += L" \"";
  size_t backslashes = 0;
  for (const wchar_t c : arg) {
    if (c == L'\\') {
      backslashes++;
      continue;
    }
    command_line.append(c == L'"' ? backslashes * 2 + 1 : backslashes, L'\\');
    backslashes = 0;
    command_line += c;
  }
  command_line.append(backslashes * 2, L'\\');
  command_line += L'"';
}

// File-system paths of the selection; items without one (inside a zip, on a
// phone) are skipped.
std::vector<std::wstring> SelectedPaths(IShellItemArray* items) {
  std::vector<std::wstring> paths;
  DWORD count = 0;
  if (items == nullptr || FAILED(items->GetCount(&count))) return paths;
  for (DWORD i = 0; i < count; i++) {
    ComPtr<IShellItem> item;
    if (FAILED(items->GetItemAt(i, &item))) continue;
    PWSTR path = nullptr;
    if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) &&
        path != nullptr) {
      paths.emplace_back(path);
    }
    ::CoTaskMemFree(path);
  }
  return paths;
}

HRESULT Launch(const std::wstring& executable, const std::wstring& directory,
               std::wstring command_line) {
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!::CreateProcessW(executable.c_str(), command_line.data(), nullptr,
                        nullptr, FALSE, 0, nullptr, directory.c_str(),
                        &startup, &process)) {
    return HRESULT_FROM_WIN32(::GetLastError());
  }
  ::CloseHandle(process.hThread);
  ::CloseHandle(process.hProcess);
  return S_OK;
}

}  // namespace

// The clsid is msix_config: context_menu's command clsid in app/pubspec.yaml.
class __declspec(uuid("f515c804-0900-4602-8912-22643870a1a1")) CombineCommand
    final : public RuntimeClass<RuntimeClassFlags<ClassicCom>,
                                IExplorerCommand, IObjectWithSite> {
 public:
  IFACEMETHODIMP GetTitle(IShellItemArray*, PWSTR* name) {
    return ::SHStrDupW(kTitle, name);
  }

  IFACEMETHODIMP GetIcon(IShellItemArray*, PWSTR* icon) {
    const std::wstring resource =
        ModuleDirectory() + L"\\" + kExecutable + kIconResource;
    return ::SHStrDupW(resource.c_str(), icon);
  }

  IFACEMETHODIMP GetToolTip(IShellItemArray*, PWSTR* tip) {
    *tip = nullptr;
    return E_NOTIMPL;
  }

  IFACEMETHODIMP GetCanonicalName(GUID* name) {
    *name = __uuidof(CombineCommand);
    return S_OK;
  }

  // Combining takes two or more files; a single PDF doesn't get the entry.
  IFACEMETHODIMP GetState(IShellItemArray* items, BOOL, EXPCMDSTATE* state) {
    DWORD count = 0;
    *state = items != nullptr && SUCCEEDED(items->GetCount(&count)) &&
                     count >= 2
                 ? ECS_ENABLED
                 : ECS_HIDDEN;
    return S_OK;
  }

  IFACEMETHODIMP Invoke(IShellItemArray* items, IBindCtx*) {
    const std::vector<std::wstring> paths = SelectedPaths(items);
    if (paths.empty()) return S_OK;
    const std::wstring directory = ModuleDirectory();
    const std::wstring executable = directory + L"\\" + kExecutable;
    const std::wstring prefix = L"\"" + executable + L"\" --combine";
    // Let the app (or the running instance it forwards to) take the
    // foreground from Explorer.
    ::AllowSetForegroundWindow(ASFW_ANY);

    // One launch normally carries the whole selection. One too long for a
    // single command line goes out in several launches, which the running app
    // joins back into one batch (runner/platform_channels.cpp).
    std::wstring command_line = prefix;
    bool has_files = false;
    for (const std::wstring& path : paths) {
      std::wstring argument;
      AppendQuoted(argument, path);
      if (has_files &&
          command_line.size() + argument.size() > kMaxCommandLine) {
        const HRESULT result = Launch(executable, directory, command_line);
        if (FAILED(result)) return result;
        command_line = prefix;
      }
      command_line += argument;
      has_files = true;
    }
    return Launch(executable, directory, command_line);
  }

  IFACEMETHODIMP GetFlags(EXPCMDFLAGS* flags) {
    *flags = ECF_DEFAULT;
    return S_OK;
  }

  IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand** commands) {
    *commands = nullptr;
    return E_NOTIMPL;
  }

  IFACEMETHODIMP SetSite(IUnknown* site) {
    site_ = site;
    return S_OK;
  }

  IFACEMETHODIMP GetSite(REFIID riid, void** site) {
    return site_.CopyTo(riid, site);
  }

 private:
  ComPtr<IUnknown> site_;
};

CoCreatableClass(CombineCommand)
// Keeps the linker from dropping the class's factory entry.
CoCreatableClassWrlCreatorMapInclude(CombineCommand)

STDAPI DllGetClassObject(REFCLSID clsid, REFIID riid, LPVOID* object) {
  return Module<InProc>::GetModule().GetClassObject(clsid, riid, object);
}

STDAPI DllCanUnloadNow() {
  return Module<InProc>::GetModule().GetObjectCount() == 0 ? S_OK : S_FALSE;
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    g_module = module;
    ::DisableThreadLibraryCalls(module);
  }
  return TRUE;
}
