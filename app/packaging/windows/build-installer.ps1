[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BundlePath,

  [Parameter(Mandatory = $true)]
  [string]$Version,

  [string]$OutputPath = 'dartpdf-windows-installer.exe'
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

$nsi = @"
Unicode true
!include "MUI2.nsh"
!define MUI_ABORTWARNING

Name "DartPDF"
OutFile "$output"
InstallDir "`$LOCALAPPDATA\Programs\DartPDF"
InstallDirRegKey HKCU "Software\DartPDF" "InstallDir"
RequestExecutionLevel user

VIProductVersion "$fileVersion"
VIAddVersionKey "ProductName" "DartPDF"
VIAddVersionKey "CompanyName" "DartPDF"
VIAddVersionKey "FileDescription" "DartPDF installer"
VIAddVersionKey "ProductVersion" "$Version"
VIAddVersionKey "FileVersion" "$Version"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "DartPDF" SecInstall
  SetShellVarContext current
  SetOutPath "`$INSTDIR"
  File /r "$bundle\*.*"

  CreateDirectory "`$SMPROGRAMS\DartPDF"
  CreateShortcut "`$SMPROGRAMS\DartPDF\DartPDF.lnk" "`$INSTDIR\dart_pdf_editor_app.exe"
  CreateShortcut "`$SMPROGRAMS\DartPDF\Uninstall DartPDF.lnk" "`$INSTDIR\Uninstall.exe"

  WriteUninstaller "`$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "Software\DartPDF" "InstallDir" "`$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DartPDF" "DisplayName" "DartPDF"
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
  WriteRegStr HKCU "Software\Classes\DartPDF.pdf\shell\open\command" "" '"`$INSTDIR\dart_pdf_editor_app.exe" "%1"'
  WriteRegStr HKCU "Software\Classes\.pdf\OpenWithProgids" "DartPDF.pdf" ""
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  Delete "`$SMPROGRAMS\DartPDF\DartPDF.lnk"
  Delete "`$SMPROGRAMS\DartPDF\Uninstall DartPDF.lnk"
  RMDir "`$SMPROGRAMS\DartPDF"

  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DartPDF"
  DeleteRegKey HKCU "Software\DartPDF"
  DeleteRegKey HKCU "Software\Classes\DartPDF.pdf"
  DeleteRegValue HKCU "Software\Classes\.pdf\OpenWithProgids" "DartPDF.pdf"

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
