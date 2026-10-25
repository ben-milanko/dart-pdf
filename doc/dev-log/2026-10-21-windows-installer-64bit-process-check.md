# 2026-10-21 - Windows installer: find a 64-bit DartPDF from 32-bit Setup

The close-and-relaunch flow from 2026-10-14 never fired: the installer still
hit "Error opening file for writing: ...\dart_pdf_editor_app.exe" with
DartPDF open. Cause: NSIS Setup is a 32-bit process, so `$SYSDIR` resolves to
SysWOW64 and `app-processes.ps1` ran under 32-bit Windows PowerShell. There
`Process.Path` reads `MainModule.FileName`, which throws for a 64-bit process
and surfaces as `$null` - every DartPDF was filtered out, the count read 0,
and Setup went straight to the file copy.

Fixes (either one alone is enough):

- `.onInit` picks `$WINDIR\Sysnative\...\powershell.exe` (the real System32,
  visible only to a 32-bit process on 64-bit Windows), falling back to
  `$SYSDIR` on a 32-bit OS.
- `app-processes.ps1` backs `Process.Path` up with CIM's
  `Win32_Process.ExecutablePath`, which works across bitness.

Rendered script compiles with makensis (only the pre-existing
LegalCopyright warning); not run on Windows here.
