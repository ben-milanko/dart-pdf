# 2026-10-14 - Windows installer closes and relaunches DartPDF

Running the installer over a live DartPDF (the in-app updater hands the
downloaded installer to the shell while the app is still open) used to fail on
the locked `dart_pdf_editor_app.exe` with NSIS's bare "error opening file for
writing" retry box. The installer now:

- **Offers to close the app.** Leaving the directory page (the first point
  `$INSTDIR` is final, the last before files are copied) counts copies
  running *from `$INSTDIR`* - `dart_pdf_editor_app.exe` and the `dartpdf.exe`
  CLI; a portable copy elsewhere is ignored. If any are, OK/Cancel: OK sends
  WM_CLOSE (`Process.CloseMainWindow`, after `AppActivate` so the window comes
  forward), which goes through `didRequestAppExit`, so unsaved changes still
  get their prompt. One WM_CLOSE per window handle - a repeat would stack
  prompts - and waits 30 s. Still running: Yes ends it (`Stop-Process`), No
  stays on the page. Cancel/No never touches the app.
- **Offers to relaunch.** The finish page has a checked "Launch DartPDF" box
  (`MUI_FINISHPAGE_RUN`), relabelled "Relaunch ..." when Setup closed the app.
- **Silent (`/S`)** skips the pages, so the section itself closes the app
  (prompts default to end-it) and relaunches it at the end if it was running.

The process work is `app/packaging/windows/app-processes.ps1`
(count/close/kill), embedded into `$PLUGINSDIR` in `.onInit` and run hidden
via `nsExec` with the in-box Windows PowerShell. If it can't run, the count
reads 0 and the file copy's own retry prompt is the fallback.

The stable release workflow had its own stale inline copy of the NSIS script
(no Combine verb, no `MultiSelectModel`); release-app.yml now calls
`build-installer.ps1` like the nightly, so there is one installer script.

Verified the rendered script compiles with makensis 3.09 (only the
pre-existing missing-LegalCopyright warning); not run on Windows here.
