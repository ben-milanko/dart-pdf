# "Combine with DartPDF" in the OS right-click menu

Follow-up to 2026-10-07-combine-files-from-os.md. That change made a
multi-file "Open with DartPDF" ask open-or-combine. This one puts
**Combine with DartPDF** in the file manager's own menu, so the choice is made
there and the app only asks for the order (`showIncomingFilesDialog(...,
combineOnly: true)`: "Combine N PDFs", no "Open in new tabs" button).

## The mark

An incoming file payload may carry `combine: true`
(`IncomingFile.combine`); a batch with any marked file is a combine request.
A batch of one still just opens. Every runner sets it the same way:

- **Linux** - `dartpdf --combine %U`, from two entries installed by
  `linux/CMakeLists.txt`: `share/applications/dev.milanko.dartpdf.combine.desktop`
  (`NoDisplay`, `MimeType=application/pdf` - shows in GNOME Files/Nemo/Caja
  "Open With") and a KDE Dolphin service menu
  (`share/kio/servicemenus/`, installed executable because KF6 refuses
  others). GApplication's parser rejects unknown flags and cannot forward
  one, so `my_application_local_command_line` handles a command line that
  contains `--combine` itself (register, then `g_application_open` with hint
  `combine`, which GLib carries to an already-running primary) and chains up
  for everything else. `my_application_open` turns the hint into the payload
  mark (warm) or a leading `--combine` entrypoint argument (cold; read by
  `_openLaunchArgs`).
- **Windows, NSIS installer** - the installer registers
  `HKCU\Software\Classes\SystemFileAssociations\.pdf\shell\DartPDF.Combine`
  (`MultiSelectModel=Player`, `--combine "%1"`), so it shows for PDFs whatever
  the default app is. Explorer still starts one process per file; each passes
  `--combine` on (`PdfArguments`) and forwards with the
  `kIncomingCombineCopyDataMagic` WM_COPYDATA tag, and the existing settle
  window joins them into one batch. On Windows 11 classic verbs sit under
  "Show more options".
- **macOS** - an `NSServices` entry in Info.plist (Finder right-click > Quick
  Actions / Services) calls `AppDelegate.combinePDFs(_:userData:error:)`
  (`NSApp.servicesProvider = self`), which reads the file URLs off the
  pasteboard and delivers them like an open, marked.
- **Windows, Store MSIX** - a packaged app can't write registry verbs, so
  the package registers a shell extension instead: `windows/combine_menu`, an
  `IExplorerCommand` (plain WRL, no WIL/ATL) wired up by `msix_config`'s
  `context_menu` (`desktop4:FileExplorerContextMenus` + a `com:SurrogateServer`).
  It is the better entry: Windows 11's top-level menu, hidden for a single
  file, and Explorer hands it the whole selection, so it launches
  `dart_pdf_editor_app.exe --combine a.pdf b.pdf ...` once (several launches
  only if the paths overflow one command line; the runner's settle window
  joins them). The DLL is built at a fixed path beside the bundle
  (`build/windows/x64/combine_menu/`, `$<0:>` keeps the config folder out)
  and **not** installed into it: `msix:create` copies it into the package and
  then deletes it from the Release folder, which would also eat an installed
  copy. The clsid in `pubspec.yaml` must match `combine_menu.cpp`. The PR
  preview workflow checks the DLL is built; nothing here has loaded it in
  Explorer yet.

## Not covered

- **NSIS keeps the classic verb on purpose.** Registering the DLL from the
  installer (a CLSID plus `ExplorerCommandHandler` on the verb) would *not*
  reach Windows 11's top-level menu: that menu takes only apps with package
  identity, so an unpackaged install needs a signed sparse package, and the
  Windows release builds are unsigned. It would also load the DLL into
  `explorer.exe`, where it stays locked while the in-app updater reruns the
  installer over the install folder.
- **Snap** only exports desktop files for declared apps, and **Flatpak** can't
  export KDE service menus; the Flatpak does install the Open With entry.

## Also fixed

A Linux cold start with several launch files never showed the dialog: launch
files are handled from `initState`, and the dialog ran before a frame existed.
`_openIncomingBatch` now waits for `endOfFrame` before asking.
