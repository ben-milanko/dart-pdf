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
- **Windows** - the NSIS installer registers
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

## Not covered

- The Store **MSIX** declares only `file_extension: .pdf` through the `msix`
  package, which has no way to add a static verb; the NSIS install has the
  menu entry, the Store build does not.
- **Snap** only exports desktop files for declared apps, and **Flatpak** can't
  export KDE service menus; the Flatpak does install the Open With entry.

## Also fixed

A Linux cold start with several launch files never showed the dialog: launch
files are handled from `initState`, and the dialog ran before a frame existed.
`_openIncomingBatch` now waits for `endOfFrame` before asking.
