# Bundled into the Windows installer (build-installer.ps1) and run hidden via
# nsExec, so the installer can find and close DartPDF before it replaces the
# files. Only processes started from -InstallDir count: a portable copy or a
# second install elsewhere is left alone.
#
#   count  prints how many are running (exit 0)
#   close  asks each to close - WM_CLOSE, the same as the title-bar X, so the
#          app still offers to save unsaved changes - and waits up to
#          -TimeoutSeconds; exit 0 once all are gone, 1 if any remain
#   kill   ends them outright; exit 0 once all are gone, 1 if any remain
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('count', 'close', 'kill')]
  [string]$Action,

  [Parameter(Mandatory = $true)]
  [string]$InstallDir,

  [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'

try { Add-Type -AssemblyName Microsoft.VisualBasic } catch { }

$prefix = [System.IO.Path]::GetFullPath($InstallDir).TrimEnd('\') + '\'

# Process.Path reads the main module, which fails across bitness (a 32-bit
# PowerShell can't open a 64-bit DartPDF's modules) and reads as empty; CIM's
# ExecutablePath doesn't care, so it backs Path up.
function Get-ImagePath($process) {
  if ($process.Path) { return $process.Path }
  try {
    (Get-CimInstance Win32_Process -Filter "ProcessId = $($process.Id)").ExecutablePath
  } catch { $null }
}

function Get-AppProcesses {
  @(Get-Process -Name 'dart_pdf_editor_app', 'dartpdf' -ErrorAction SilentlyContinue |
    Where-Object {
      $path = Get-ImagePath $_
      $path -and
      $path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
    })
}

function Wait-AppExit([int]$seconds, [switch]$closeWindows) {
  $deadline = (Get-Date).AddSeconds($seconds)
  # A window is asked once: a second WM_CLOSE while the app's "unsaved
  # changes" prompt is up would stack another prompt. Asking again only when
  # the main window changes walks a multi-window session down one at a time.
  $asked = @{}
  while ($true) {
    $running = Get-AppProcesses
    if ($running.Count -eq 0) { return $true }
    if ((Get-Date) -ge $deadline) { return $false }
    if ($closeWindows) {
      foreach ($p in $running) {
        $p.Refresh()
        $handle = $p.MainWindowHandle
        if ($handle -ne [IntPtr]::Zero -and -not $asked.ContainsKey($handle)) {
          $asked[$handle] = $true
          # Bring it forward first so an "unsaved changes" prompt isn't hidden
          # behind the installer (allowed: our parent is the foreground app).
          try { [Microsoft.VisualBasic.Interaction]::AppActivate($p.Id) } catch { }
          [void]$p.CloseMainWindow()
        }
      }
    }
    Start-Sleep -Milliseconds 250
  }
}

switch ($Action) {
  'count' {
    Write-Output (Get-AppProcesses).Count
    exit 0
  }
  'close' {
    if (Wait-AppExit $TimeoutSeconds -closeWindows) { exit 0 }
    exit 1
  }
  'kill' {
    Get-AppProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    if (Wait-AppExit 10) { exit 0 }
    exit 1
  }
}
