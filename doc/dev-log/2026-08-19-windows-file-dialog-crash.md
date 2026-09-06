# Windows: open/save dialogs crashed the multi-window runner

"Open PDF in new tab" and "Save as" both took the Windows app down. Same
single cause, and it is a consequence of the engine-owned bootstrap that
desktop multi-windowing needs (#687, doc/dev-log/2026-08-14-flutter-347-multi-window.md).

## Root cause

`file_selector_windows` captures the dialog's owner window at registration
time, straight off the registrar's implicit view:

```cpp
// file_selector_windows/windows/file_selector_plugin.cpp
HWND GetRootWindow(flutter::FlutterView* view) {
  return ::GetAncestor(view->GetNativeWindow(), GA_ROOT);   // view is null
}
...
  [registrar] { return GetRootWindow(registrar->GetView()); }
```

The pinned Flutter 3.47 client wrapper is explicit that this can be null:

```cpp
// plugin_registrar_windows.h
// Returns the implicit view, or nullptr if there is no implicit view.
FlutterView* GetView() { return implicit_view_.get(); }
```

DartPDF's Windows runner deliberately has no implicit view - it runs a bare
`flutter::FlutterEngine` so Dart can create every native window itself. So
`GetView()` is null, the plugin dereferences it, and the process dies at the
first `openFile`/`openFiles`/`getSaveLocation`. Nothing recovers from it:
it's an access violation inside the method-call handler, not a Dart
exception, so no toast and no fallback.

Auditing the rest of the Windows plugin set for the same shape:

| plugin | uses the implicit view | effect here |
| --- | --- | --- |
| `file_selector_windows` | unguarded deref | **crash** (this fix) |
| `desktop_drop` | guarded, bails out | drag-and-drop silently inert |
| `share_plus` | unguarded deref | unreachable - only called on Android/iOS |
| `url_launcher_windows`, `flutter_secure_storage_windows`, `flutter_doc_scanner` | no | fine |

## Fix

The runner already knows its active window without a view - it hands one to
the print dialog and the image clipboard - so DartPDF drives the common-item
dialogs itself.

- `windows/runner/file_dialogs.{h,cpp}`: `IFileOpenDialog`/`IFileSaveDialog`
  behind a small struct API (filters, initial folder, suggested name, OK
  label, multi-select, folder mode). A dismissed dialog is an empty
  selection, not an error; only a dialog that could not run reports its
  HRESULT.
- `windows/runner/platform_channels.cpp`: a `dev.milanko.dartpdf/file_dialogs`
  channel over it, owned by the same `OwnerWindow` provider the print and
  clipboard channels use. Registered by both bootstraps, so the single-view
  runner gets it too.
- `lib/windows_file_dialogs.dart`: `WindowsFileDialogs`, a
  `FileSelectorPlatform` that routes to that channel.
  `installIfNeeded()` swaps it in from `main()` on Windows only, after
  `ensureInitialized()` so it wins over the Dart plugin registrant. Every
  `file_selector` call site is unchanged.

Two things kept deliberately faithful to the plugin it displaces, so the
swap is invisible to callers: a type group that names neither "any" nor any
extension throws the same `ArgumentError` up front, and the save dialog
reports its active filter by the same one-based index.

`getDirectoryPath`/`getDirectoryPaths` route through the channel as well.
The app doesn't call them today, but they were the plugin's other two
crash sites and leaving them out would just bank a future one.

## Verification

- `app/test/windows_file_dialogs_test.dart` (11 tests): argument encoding,
  cancellation, multi-pick, active-filter mapping, out-of-range filter
  index, the `ArgumentError` contract, folder picks, the
  MissingPluginException fallback, and `installIfNeeded` being
  Windows-only and idempotent.
- The native sources were cross-compiled against the pinned SDK's real
  `cpp_client_wrapper` headers (`flutter precache --windows`, then
  `x86_64-w64-mingw32-g++ -std=c++17 -fsyntax-only -Wall -Wextra
  -Wconversion`); all eight runner translation units are clean. `/W4 /WX`
  patterns to keep in mind if this file grows: every narrowing conversion
  is an explicit cast, and the `COMDLG_FILTERSPEC` array borrows strings
  from two vectors that are `reserve`d up front so they never reallocate.
- `flutter test` in `app/`: 463 passing.

## Still open

Drag-and-drop onto a Windows window is inert for the same reason -
`desktop_drop` returns early when the registrar has no view ("no window, no
drop"). Fixing it needs a per-window `IDropTarget` in the runner rather than
a channel, so it is not in this change.
