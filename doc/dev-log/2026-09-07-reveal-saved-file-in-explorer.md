# "Open in File Explorer" could show the document's old folder (Windows)

Reported: after a Save As to a different folder, the tab context menu's
**Open in File Explorer** opened the location the document had been opened
*from*, not the one it had just been saved to.

## What was ruled out first

The app-side half is sound, and now has a test that says so
(`app/test/tabs_menu_test.dart`, "reveal follows a Save As to a new folder").
`EditorScreen._save` adopts the destination on a successful Save As -
`tab.originPath`/`originBookmark`/title all move to the new file, `cachePath`
is dropped - and `_showTabMenu` reads `tab.originPath` when the action runs,
not when the menu is built. Driving that end to end (open a file-backed tab,
Save As, right-click, Open in File Explorer) reveals the new path on macOS and
Windows alike.

## The actual mechanism

`openContainingFolder` asked `url_launcher` to open a `file:` URL for the
*containing folder*. On Windows that lands in
`ShellExecuteW(nullptr, L"open", L"file:///C:/...")`, which is a request to
open a folder, not to show a particular file. Explorer is free to answer it
from a window it already has - with the shell's default "open each folder in
the same window", the user gets whatever that window was showing. Right after
opening a PDF from `Documents` and saving it to `Desktop`, the window Explorer
reaches for is the one still parked on `Documents`: the document's old
location.

macOS never had this: its reveal goes through the runner and calls
`NSWorkspace.activateFileViewerSelecting`, which names the file.

## Fix

Windows now reveals through the runner too, the same way:

- `windows/runner/file_dialogs.cpp` gains `RevealFileInExplorer`, which turns
  the path into a PIDL (`ILCreateFromPathW`) and calls
  `SHOpenFolderAndSelectItems`. The item is named, so there is nothing for the
  shell to resolve from an existing window, and the saved file comes up
  selected - the same affordance Finder gives.
- `windows/runner/platform_channels.cpp` registers
  `dev.milanko.dartpdf/file_access` (the channel macOS already uses for
  bookmarks and its own `revealFile`) with the one `revealFile` method.
- `lib/file_io.dart`'s `openContainingFolder` calls it on Windows and **falls
  back** to the old folder launch when the runner has no such method (a Dart
  build running against an older runner) or when the shell refuses the item
  (a file deleted between the save and the click).

`shell32`/`ole32` were already linked for the common-item dialogs, and COM is
already initialised STA on the platform thread by `main.cpp`, so the reveal
needed no build changes.

## Also fixed here

`Uri.file(folder)` takes its separator rules from the **host** process, not
from `defaultTargetPlatform`. That is the same thing in production, but it
means a Windows path formatted on any other host silently becomes a relative,
percent-encoded URI (`C%3A%5CUsers%5C...`) - which is what a
`TargetPlatformVariant` test sees. The call now passes `windows:` explicitly,
so the folder fallback is honest under test and pinned by
`app/test/file_io_folder_test.dart`.
