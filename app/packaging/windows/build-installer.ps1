[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BundlePath,

  [Parameter(Mandatory = $true)]
  [string]$Version,

  [string]$OutputPath = 'dartpdf-windows-installer.exe',

  # What Windows calls the install: the installer title, Start menu entry and
  # Installed apps row. The nightly passes 'DartPDF Nightly' so it can be told
  # apart from a stable install. Both channels share one install directory,
  # uninstall key and ProgID, so either replaces the other in place.
  [string]$ProductName = 'DartPDF'
)

$ErrorActionPreference = 'Stop'

$bundle = (Resolve-Path $BundlePath).Path
$output = [System.IO.Path]::GetFullPath(
  (Join-Path (Get-Location) $OutputPath)
)
$outputDirectory = Split-Path -Parent $output
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$versionDigits = $Version -replace '[^0-9.].*$', ''
$versionParts = @(
  $versionDigits.Split('.') | Where-Object { $_ -match '^\d+$' }
)
while ($versionParts.Count -lt 4) { $versionParts += '0' }
$fileVersion = ($versionParts[0..3] -join '.')

# Start menu entries every channel has ever created, so switching channels
# (or uninstalling) never leaves the other channel's shortcut behind.
$shortcutNames = @('DartPDF', 'DartPDF Nightly')
# Single-quoted fragments: NSIS's own $SMPROGRAMS must reach the script as-is.
function Get-ShortcutDeletes([string[]]$names) {
  ($names | ForEach-Object {
    '  Delete "$SMPROGRAMS\DartPDF\' + $_ + '.lnk"'
    '  Delete "$SMPROGRAMS\DartPDF\Uninstall ' + $_ + '.lnk"'
  }) -join "`r`n"
}
$staleShortcuts = Get-ShortcutDeletes @(
  $shortcutNames | Where-Object { $_ -ne $ProductName }
)
$allShortcuts = Get-ShortcutDeletes $shortcutNames

# Run by the installer (hidden) to find and close a running DartPDF before
# the files are replaced; see the script's header.
$appProcesses = Join-Path $PSScriptRoot 'app-processes.ps1'

$nsi = @"
Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!define MUI_ABORTWARNING

Name "$ProductName"
OutFile "$output"
InstallDir "`$LOCALAPPDATA\Programs\DartPDF"
InstallDirRegKey HKCU "Software\DartPDF" "InstallDir"
RequestExecutionLevel user

VIProductVersion "$fileVersion"
VIAddVersionKey "ProductName" "$ProductName"
VIAddVersionKey "CompanyName" "DartPDF"
VIAddVersionKey "FileDescription" "$ProductName installer"
VIAddVersionKey "ProductVersion" "$Version"
VIAddVersionKey "FileVersion" "$Version"

!define APP_EXE "`$INSTDIR\dart_pdf_editor_app.exe"
!define APP_PROCESSES '"`$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "`$PLUGINSDIR\app-processes.ps1" -InstallDir "`$INSTDIR"'

; 1 once Setup has closed a running DartPDF, so the finish page offers to
; relaunch it (and a silent install relaunches it by itself).
Var AppWasRunning

!insertmacro MUI_PAGE_WELCOME
; Leaving the directory page is the last stop before files are copied, and
; the first point `$INSTDIR is final: close a running copy there.
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE CloseRunningApp
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "`${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch $ProductName"
!define MUI_PAGE_CUSTOMFUNCTION_SHOW FinishPageShow
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function .onInit
  InitPluginsDir
  File "/oname=`$PLUGINSDIR\app-processes.ps1" "$appProcesses"
FunctionEnd

; `$0 = how many copies are running from `$INSTDIR (0 if the check can't run;
; the file copy's own retry prompt then still catches a locked file).
Function CountRunningApp
  nsExec::ExecToStack '`${APP_PROCESSES} -Action count'
  Pop `$1
  Pop `$0
  `${If} `$1 != 0
    StrCpy `$0 0
  `${EndIf}
  IntOp `$0 `$0 + 0
FunctionEnd

; Abort keeps the user on the directory page (or fails a silent install).
Function CloseRunningApp
  Call CountRunningApp
  `${If} `$0 == 0
    Return
  `${EndIf}
  `${IfNot} `${Silent}
    MessageBox MB_OKCANCEL|MB_ICONINFORMATION "$ProductName is running and needs to close before Setup can continue.`$\r`$\n`$\r`$\nSelect OK to close it now. If you have unsaved changes, $ProductName asks what to do with them first." IDOK close_app
    Abort
  `${EndIf}
close_app:
  StrCpy `$AppWasRunning 1
  nsExec::Exec '`${APP_PROCESSES} -Action close'
  Pop `$1
  `${If} `$1 == 0
    Return
  `${EndIf}
  MessageBox MB_YESNO|MB_ICONEXCLAMATION "$ProductName is still running. It may be waiting for you to save or discard changes.`$\r`$\n`$\r`$\nSelect Yes to end it now (unsaved changes may be lost), or No to go back." /SD IDYES IDYES kill_app
  Abort
kill_app:
  nsExec::Exec '`${APP_PROCESSES} -Action kill'
  Pop `$1
  `${If} `$1 != 0
    MessageBox MB_OK|MB_ICONSTOP "Setup could not close $ProductName. Close it, then try again." /SD IDOK
    Abort
  `${EndIf}
FunctionEnd

Function FinishPageShow
  `${If} `$AppWasRunning == 1
    SendMessage `$mui.FinishPage.Run `${WM_SETTEXT} 0 "STR:Relaunch $ProductName"
  `${EndIf}
FunctionEnd

Section "DartPDF" SecInstall
  SetShellVarContext current
  ; No pages run in a silent install (an update), so close a running copy here.
  `${If} `${Silent}
    Call CloseRunningApp
  `${EndIf}
  SetOutPath "`$INSTDIR"
  File /r "$bundle\*.*"

$staleShortcuts
  CreateDirectory "`$SMPROGRAMS\DartPDF"
  CreateShortcut "`$SMPROGRAMS\DartPDF\$ProductName.lnk" "`${APP_EXE}"
  CreateShortcut "`$SMPROGRAMS\DartPDF\Uninstall $ProductName.lnk" "`$INSTDIR\Uninstall.exe"

  WriteUninstaller "`$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "Software\DartPDF" "InstallDir" "`$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DartPDF" "DisplayName" "$ProductName"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DartPDF" "DisplayVersion" "$Version"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DartPDF" "Publisher" "DartPDF"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DartPDF" "InstallLocation" "`$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DartPDF" "DisplayIcon" "`$INSTDIR\dart_pdf_editor_app.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DartPDF" "UninstallString" '"`$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DartPDF" "QuietUninstallString" '"`$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DartPDF" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DartPDF" "NoRepair" 1

  WriteRegStr HKCU "Software\Classes\DartPDF.pdf" "" "PDF document"
  WriteRegStr HKCU "Software\Classes\DartPDF.pdf\DefaultIcon" "" "`$INSTDIR\dart_pdf_editor_app.exe,-102"
  ; Player lifts Explorer's 15-item cap on a selection's Open (the default
  ; Document model hides the verb past 15) to 100. Explorer still runs the
  ; "%1" command once per file; the single-instance runner forwards each to
  ; the first window, which offers to combine the batch.
  WriteRegStr HKCU "Software\Classes\DartPDF.pdf\shell\open" "MultiSelectModel" "Player"
  WriteRegStr HKCU "Software\Classes\DartPDF.pdf\shell\open\command" "" '"`$INSTDIR\dart_pdf_editor_app.exe" "%1"'
  WriteRegStr HKCU "Software\Classes\.pdf\OpenWithProgids" "DartPDF.pdf" ""
  ; Explorer right-click > "Combine with DartPDF" on any PDF selection, whatever
  ; the default PDF app is. Explorer starts one process per selected file; the
  ; runner coalesces their forwards into one batch (see windows/runner).
  ; Player lifts the 15-file cap of the default multi-select model.
  WriteRegStr HKCU "Software\Classes\SystemFileAssociations\.pdf\shell\DartPDF.Combine" "MUIVerb" "Combine with DartPDF"
  WriteRegStr HKCU "Software\Classes\SystemFileAssociations\.pdf\shell\DartPDF.Combine" "Icon" "`$INSTDIR\dart_pdf_editor_app.exe,-102"
  WriteRegStr HKCU "Software\Classes\SystemFileAssociations\.pdf\shell\DartPDF.Combine" "MultiSelectModel" "Player"
  WriteRegStr HKCU "Software\Classes\SystemFileAssociations\.pdf\shell\DartPDF.Combine\command" "" '"`$INSTDIR\dart_pdf_editor_app.exe" --combine "%1"'
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'

  `${If} `${Silent}
  `${AndIf} `$AppWasRunning == 1
    Exec '"`${APP_EXE}"'
  `${EndIf}
SectionEnd

Section "Uninstall"
  SetShellVarContext current
$allShortcuts
  RMDir "`$SMPROGRAMS\DartPDF"

  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DartPDF"
  DeleteRegKey HKCU "Software\DartPDF"
  DeleteRegKey HKCU "Software\Classes\DartPDF.pdf"
  DeleteRegValue HKCU "Software\Classes\.pdf\OpenWithProgids" "DartPDF.pdf"
  DeleteRegKey HKCU "Software\Classes\SystemFileAssociations\.pdf\shell\DartPDF.Combine"

  RMDir /r "`$INSTDIR"
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'
SectionEnd
"@

$makensis = "${env:ProgramFiles(x86)}\NSIS\makensis.exe"
if (-not (Test-Path $makensis)) {
  throw 'NSIS is not installed (makensis.exe was not found)'
}

$nsiPath = Join-Path ([System.IO.Path]::GetTempPath()) (
  "dartpdf-installer-$([guid]::NewGuid().ToString('N')).nsi"
)
try {
  Set-Content -Path $nsiPath -Value $nsi -Encoding utf8
  & $makensis $nsiPath
  if ($LASTEXITCODE -ne 0) {
    throw "makensis failed ($LASTEXITCODE)"
  }
  if (-not (Test-Path $output)) {
    throw "Installer was not produced at $output"
  }
} finally {
  Remove-Item $nsiPath -Force -ErrorAction SilentlyContinue
}
