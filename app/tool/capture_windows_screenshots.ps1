# Capture real Windows app windows for Microsoft Store. Run after:
# flutter build windows --release -t tool/screenshots_main.dart
# Captures the running Windows app's Flutter surface on headless CI runners.
# No synthesized window frames, platform overrides, or marketing overlays.
[CmdletBinding()]
param(
  [string]$SourceRoot = '.',
  [string]$OutputDirectory = 'doc/screenshots/app/windows'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Native Windows captures require Windows.' }
$source = (Resolve-Path $SourceRoot).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
$executable = Join-Path $source 'app/build/windows/x64/runner/Release/dartpdf.exe'
if (-not (Test-Path $executable)) { throw "Build the capture app first: $executable" }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$signals = Join-Path ([IO.Path]::GetTempPath()) "dartpdf-shots-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $signals | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DartPdfCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct Rect { public int Left, Top, Right, Bottom; }
  public delegate bool EnumWindow(IntPtr window, IntPtr data);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindow callback, IntPtr data);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect rect);
  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  public static IntPtr FindWindow(uint processId) {
    IntPtr found = IntPtr.Zero;
    int largest = 0;
    EnumWindows((window, data) => {
      uint owner;
      GetWindowThreadProcessId(window, out owner);
      Rect rect;
      if (owner == processId && IsWindowVisible(window) && GetWindowRect(window, out rect)) {
        int area = (rect.Right - rect.Left) * (rect.Bottom - rect.Top);
        if (area > largest) { largest = area; found = window; }
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
'@

[DartPdfCapture]::SetProcessDPIAware() | Out-Null
$appProcess = $null
$priorSignalDirectory = $env:DARTPDF_SHOT_SIGNAL_DIR
$priorOutputDirectory = $env:DARTPDF_SHOT_OUTPUT_DIR
try {
  $env:DARTPDF_SHOT_SIGNAL_DIR = $signals
  $env:DARTPDF_SHOT_OUTPUT_DIR = $output
  $appProcess = Start-Process -FilePath $executable -PassThru `
    -WorkingDirectory (Split-Path $executable) `
    -RedirectStandardOutput (Join-Path $output 'app-stdout.log') `
    -RedirectStandardError (Join-Path $output 'app-stderr.log')
  $captures = @()
  foreach ($scene in @('01-welcome', '02-editor', '03-dark')) {
    $deadline = (Get-Date).AddSeconds(90)
    while (-not (Test-Path (Join-Path $signals "$scene.ready"))) {
      if ($appProcess.HasExited) { throw "App exited before $scene (exit $($appProcess.ExitCode))." }
      if ((Get-Date) -gt $deadline) { throw "Timed out waiting for scene $scene." }
      Start-Sleep -Milliseconds 200
    }
    $window = [DartPdfCapture]::FindWindow($appProcess.Id)
    if ($window -eq [IntPtr]::Zero) { throw 'No visible window belongs to the capture process.' }
    [DartPdfCapture]::ShowWindow($window, 9) | Out-Null # SW_RESTORE
    if (-not [DartPdfCapture]::SetWindowPos($window, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0040)) {
      throw 'Could not size the app window.'
    }
    [DartPdfCapture]::SetForegroundWindow($window) | Out-Null
    # The app waits for this request, settles after resize, then captures its
    # own real Windows render surface. This also works without a desktop monitor.
    Set-Content (Join-Path $signals "$scene.capture") 'capture'
    $deadline = (Get-Date).AddSeconds(90)
    while (-not (Test-Path (Join-Path $signals "$scene.captured"))) {
      if ($appProcess.HasExited) { throw "App exited while capturing $scene." }
      if ((Get-Date) -gt $deadline) { throw "Timed out capturing scene $scene." }
      Start-Sleep -Milliseconds 200
    }
    $path = Join-Path $output "$scene.png"
    $bitmap = [System.Drawing.Bitmap]::new($path)
    try {
      $width = $bitmap.Width
      $height = $bitmap.Height
      if ($width -lt 1366 -or $height -lt 768) { throw "Image too small for Store: ${width}x${height}." }
      $colors = [Collections.Generic.HashSet[int]]::new()
      for ($y = 40; $y -lt $height; $y += 20) {
        for ($x = 20; $x -lt $width; $x += 20) {
          [void]$colors.Add($bitmap.GetPixel($x, $y).ToArgb())
        }
      }
      if ($colors.Count -lt 20) { throw "Scene $scene appears blank ($($colors.Count) sampled colors)." }
    } finally {
      $bitmap.Dispose()
    }
    $captures += @{
      file = "$scene.png"; width = $width; height = $height
      sha256 = (Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    Write-Host "Captured $scene at ${width}x${height}: $path"
  }
  if (@($captures.sha256 | Select-Object -Unique).Count -ne 3) {
    throw 'Expected three different scenes, but some captures are identical.'
  }
  @{
    platform = 'windows'; capture = 'running Windows app render surface via RenderRepaintBoundary.toImage at 2x'
    source_sha = (git -C $source rev-parse HEAD)
    harness_sha = (git -C $PSScriptRoot rev-parse HEAD)
    app_version = (Select-String -Path "$source/app/pubspec.yaml" -Pattern '^version:').Line
    workflow_run = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
    captured_at = (Get-Date).ToUniversalTime().ToString('o')
    screenshots = $captures
  } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $output 'provenance.json')
} finally {
  if ($appProcess -and -not $appProcess.HasExited) { Stop-Process -Id $appProcess.Id -Force }
  $env:DARTPDF_SHOT_SIGNAL_DIR = $priorSignalDirectory
  $env:DARTPDF_SHOT_OUTPUT_DIR = $priorOutputDirectory
  Remove-Item $signals -Recurse -Force
}
