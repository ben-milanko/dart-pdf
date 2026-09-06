#include "file_dialogs.h"

#include <shobjidl.h>
#include <windows.h>

#include <utility>

namespace dart_pdf {

namespace {

// Minimal scoped COM pointer. The runner deliberately avoids pulling in ATL or
// WRL for six call sites; this covers exactly the shape used below.
template <typename T>
class ComPtr {
 public:
  ComPtr() = default;
  ~ComPtr() { Reset(); }

  ComPtr(const ComPtr&) = delete;
  ComPtr& operator=(const ComPtr&) = delete;

  // Address of the (released) slot, for IID_PPV_ARGS.
  T** Put() {
    Reset();
    return &ptr_;
  }

  T* Get() const { return ptr_; }
  T* operator->() const { return ptr_; }
  explicit operator bool() const { return ptr_ != nullptr; }

  void Reset() {
    if (ptr_ != nullptr) {
      ptr_->Release();
      ptr_ = nullptr;
    }
  }

 private:
  T* ptr_ = nullptr;
};

// "*.png;*.jpg" for a filter's extensions, or "*.*" when it names none.
std::wstring FilterSpec(const FileTypeFilter& filter) {
  if (filter.extensions.empty()) return L"*.*";
  std::wstring spec;
  for (const std::wstring& extension : filter.extensions) {
    if (!spec.empty()) spec += L";";
    spec += L"*." + extension;
  }
  return spec;
}

// The filesystem path behind |item|, or an empty string when it has none
// (a shell item that is not a file, or a failed query).
std::wstring PathForShellItem(IShellItem* item) {
  if (item == nullptr) return std::wstring();
  wchar_t* wide_path = nullptr;
  if (FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &wide_path))) {
    return std::wstring();
  }
  std::wstring path(wide_path);
  ::CoTaskMemFree(wide_path);
  return path;
}

void CollectOpenResults(IFileDialog* dialog, FileDialogResult* out) {
  ComPtr<IFileOpenDialog> open_dialog;
  if (FAILED(dialog->QueryInterface(IID_PPV_ARGS(open_dialog.Put())))) return;
  ComPtr<IShellItemArray> items;
  if (FAILED(open_dialog->GetResults(items.Put())) || !items) return;
  DWORD count = 0;
  if (FAILED(items->GetCount(&count))) return;
  for (DWORD index = 0; index < count; index++) {
    ComPtr<IShellItem> item;
    if (FAILED(items->GetItemAt(index, item.Put()))) continue;
    std::wstring path = PathForShellItem(item.Get());
    if (!path.empty()) out->paths.push_back(std::move(path));
  }
}

void CollectSaveResult(IFileDialog* dialog, FileDialogResult* out) {
  ComPtr<IShellItem> item;
  if (FAILED(dialog->GetResult(item.Put()))) return;
  std::wstring path = PathForShellItem(item.Get());
  if (!path.empty()) out->paths.push_back(std::move(path));
}

FileDialogResult ShowDialog(HWND owner, const FileDialogRequest& request,
                            bool save) {
  FileDialogResult result;
  ComPtr<IFileDialog> dialog;
  HRESULT hr = ::CoCreateInstance(
      save ? CLSID_FileSaveDialog : CLSID_FileOpenDialog, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(dialog.Put()));
  if (FAILED(hr) || !dialog) {
    result.error = FAILED(hr) ? hr : E_FAIL;
    return result;
  }

  FILEOPENDIALOGOPTIONS options = 0;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    // FORCEFILESYSTEM keeps every result addressable as a real path, which is
    // the only kind this app can read or write.
    options |= FOS_FORCEFILESYSTEM;
    if (!save && request.allow_multiple) options |= FOS_ALLOWMULTISELECT;
    if (!save && request.select_folders) options |= FOS_PICKFOLDERS;
    dialog->SetOptions(options);
  }

  // The COMDLG_FILTERSPEC entries borrow these strings, so both vectors have
  // to outlive the SetFileTypes call - and `specs` must never reallocate.
  std::vector<std::wstring> spec_strings;
  std::vector<COMDLG_FILTERSPEC> specs;
  spec_strings.reserve(request.filters.size());
  specs.reserve(request.filters.size());
  for (const FileTypeFilter& filter : request.filters) {
    spec_strings.push_back(FilterSpec(filter));
    specs.push_back({filter.label.c_str(), spec_strings.back().c_str()});
  }
  if (!specs.empty()) {
    dialog->SetFileTypes(static_cast<UINT>(specs.size()), specs.data());
  }

  if (!request.initial_directory.empty()) {
    ComPtr<IShellItem> folder;
    if (SUCCEEDED(::SHCreateItemFromParsingName(
            request.initial_directory.c_str(), nullptr,
            IID_PPV_ARGS(folder.Put())))) {
      dialog->SetFolder(folder.Get());
    }
  }
  if (!request.suggested_name.empty()) {
    dialog->SetFileName(request.suggested_name.c_str());
  }
  if (!request.confirm_button_text.empty()) {
    dialog->SetOkButtonLabel(request.confirm_button_text.c_str());
  }

  hr = dialog->Show(owner);
  if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    // Dismissed. An empty selection is the answer, not an error.
    result.shown = true;
    return result;
  }
  if (FAILED(hr)) {
    result.error = hr;
    return result;
  }

  if (save) {
    CollectSaveResult(dialog.Get(), &result);
  } else {
    CollectOpenResults(dialog.Get(), &result);
  }
  UINT filter_index = 0;
  if (SUCCEEDED(dialog->GetFileTypeIndex(&filter_index))) {
    result.filter_index = filter_index;
  }
  result.shown = true;
  return result;
}

}  // namespace

FileDialogResult ShowOpenFileDialog(HWND owner,
                                    const FileDialogRequest& request) {
  return ShowDialog(owner, request, /*save=*/false);
}

FileDialogResult ShowSaveFileDialog(HWND owner,
                                    const FileDialogRequest& request) {
  return ShowDialog(owner, request, /*save=*/true);
}

}  // namespace dart_pdf
