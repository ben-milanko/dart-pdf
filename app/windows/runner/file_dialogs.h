#ifndef RUNNER_FILE_DIALOGS_H_
#define RUNNER_FILE_DIALOGS_H_

#include <windows.h>

#include <string>
#include <vector>

namespace dart_pdf {

// One entry of the dialog's file-type dropdown. |extensions| carries bare
// extensions ("pdf"), not patterns - the dialog builds "*.pdf" itself.
struct FileTypeFilter {
  std::wstring label;
  std::vector<std::wstring> extensions;
};

// Everything the Dart side can configure on a dialog. Empty strings mean
// "leave the platform default alone".
struct FileDialogRequest {
  std::vector<FileTypeFilter> filters;
  std::wstring initial_directory;
  std::wstring suggested_name;
  std::wstring confirm_button_text;
  bool allow_multiple = false;
  bool select_folders = false;
};

// The outcome of one dialog. |shown| distinguishes a dialog the user
// dismissed (shown, empty paths) from one that could not run at all (not
// shown, |error| carries the HRESULT).
struct FileDialogResult {
  bool shown = false;
  HRESULT error = S_OK;
  std::vector<std::wstring> paths;

  // One-based index of the type filter the user had selected, or 0 when the
  // dialog did not report one.
  unsigned int filter_index = 0;
};

// Shows the common-item open dialog owned by |owner|, blocking until the user
// dismisses it. Picks folders instead of files when |request.select_folders|
// is set, and allows several only when |request.allow_multiple| is.
FileDialogResult ShowOpenFileDialog(HWND owner,
                                    const FileDialogRequest& request);

// Shows the common-item save dialog owned by |owner|, blocking until the user
// dismisses it. The returned path is whatever the user typed - the caller is
// responsible for forcing an extension.
FileDialogResult ShowSaveFileDialog(HWND owner,
                                    const FileDialogRequest& request);

// Opens |path|'s folder in File Explorer with the file itself selected, the
// way Finder's "Reveal in Finder" behaves. Returns false when the path cannot
// be parsed by the shell (it no longer exists, or is not a filesystem path) or
// Explorer refuses the request, which lets the Dart side fall back to plainly
// launching the containing folder.
//
// Shell-executing a `file:` URL for the folder - what url_launcher does - is a
// navigation request Explorer may serve from a window it already has, so it
// could surface a folder the user was looking at earlier instead of this one.
// SHOpenFolderAndSelectItems names the item, so there is nothing to guess.
bool RevealFileInExplorer(const std::wstring& path);

}  // namespace dart_pdf

#endif  // RUNNER_FILE_DIALOGS_H_
