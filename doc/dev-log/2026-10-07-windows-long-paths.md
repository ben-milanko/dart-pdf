# Windows: opening PDFs past MAX_PATH

Audit of every way a path reaches the app on Windows, checking each for the
260-character MAX_PATH limit:

- **Reading/writing (dart:io).** No limit. The Dart VM's `file_win.cc` sends
  every path through `ToWinAPIPath` (`PathAllocCanonicalize` +
  `PATHCCH_ENSURE_IS_EXTENDED_LENGTH_PATH`), so `File(path).open()` in
  `pdf_file_source_io.dart`, save and `XFile` all handle long paths whatever
  the system policy is.
- **Native hand-offs.** No limit. `windows_drop.cpp` (`DragQueryFileW` sized by
  a first call), `file_dialogs.cpp` (`SIGDN_FILESYSPATH`, CoTaskMem string),
  `CommandLineToArgvW` and the WM_COPYDATA forward to the running instance all
  use dynamic buffers. The one fixed `TCHAR[MAX_PATH]` is in `desktop_drop`'s
  own Windows plugin. The app only falls back to that plugin before its window
  handle is known (`_buildFileDropTarget`), so we don't patch it.
- **Explorer launches.** The gap. Explorer can hand a file past MAX_PATH to an
  app as its 8.3 short alias. That alias opens fine, but the tab title,
  recents and in-place save then all carry `REPORT~1.PDF`, and on volumes with
  8.3 names disabled there's no alias to hand over at all.

Changes:

- `runner.exe.manifest` declares `longPathAware`, which lifts the limit for
  every Win32 call in the process once the user's `LongPathsEnabled` policy is
  on (it does nothing without that policy).
- `main.cpp` `PdfArguments` runs each path through `ExpandLongPath`
  (`GetLongPathNameW` in the `\\?\` form, so the expansion itself can exceed
  MAX_PATH). Because both the cold-start batch and the paths forwarded to an
  already-running instance come from this function, a combine gets real paths.
- The string halves (`ExtendedLengthPath` / `StripExtendedLengthPrefix`) live
  in `runner/long_paths.h`, free of `<windows.h>`. They're unit-tested on the
  host by CI's linux job (`app/windows/test/long_paths_test.cc`), the same way
  as `dib_pixels.h`.

Not verified on a real Windows machine from this session (Linux container):
the C++ in `main.cpp` compiles only in the Windows CI/release builds.

## Follow-up: Explorer's 15-file Open limit

Explorer hides a legacy command-line verb once more than 15 files are selected
(the default `Document` multi-select model). The NSIS installer now sets
`MultiSelectModel=Player` on `DartPDF.pdf\shell\open`, which raises that to 100
(Microsoft's "verb selection model" table: legacy verbs are 15 under Document
and 100 under Player; only COM verbs have no limit). Explorer still runs the
`"%1"` command once per file. Every extra process forwards its path over
WM_COPYDATA, and `kIncomingSettleMs` (500 ms of quiet) batches them into one
`openFiles` call, so the combine offer still sees the whole selection.

The MSIX is unchanged: for a packaged app Windows uses Player for 15 or fewer
files and Document (one launch per file) beyond that, so the verb never
disappears. The `msix` tool can't express `MultiSelectModel` anyway. Past 100
files would need a COM `DropTarget`/`ExecuteCommand` handler. See RELEASING.md
"File associations".
