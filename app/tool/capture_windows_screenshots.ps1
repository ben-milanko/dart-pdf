# Capture real Windows app windows for Microsoft Store. Run after:
# flutter build windows --release -t tool/screenshots_main.dart
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
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DartPdfCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct Rect { public int Left, Top, Right, Bottom; }
  // DEVMODEW: retain the current mode's other fields when resizing the CI display.
  [StructLayout(LayoutKind.Explicit, Size = 220)]
  public struct DisplayMode {
    [FieldOffset(68)] public ushort Size;
    [FieldOffset(72)] public uint Fields;
    [FieldOffset(172)] public uint Width;
    [FieldOffset(176)] public uint Height;
  }
  public delegate bool EnumWindow(IntPtr window, IntPtr data);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern bool EnumDisplaySettings(string name, int mode, ref DisplayMode settings);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int ChangeDisplaySettings(ref DisplayMode settings, uint flags);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindow callback, IntPtr data);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect rect);
  [DllImport("dwmapi.dll")]
  public static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out Rect rect, int size);
  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
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
$originalMode = New-Object DartPdfCapture+DisplayMode
$originalMode.Size = 220
if (-not [DartPdfCapture]::EnumDisplaySettings($null, -1, [ref]$originalMode)) {
  throw 'Cannot read the Windows desktop display mode.'
}
$captureMode = $originalMode
$captureMode.Fields = 0x180000 # DM_PELSWIDTH | DM_PELSHEIGHT
$captureMode.Width = 1920
$captureMode.Height = 1080
$displayChanged = $false
$appProcess = $null
$priorSignalDirectory = $env:DARTPDF_SHOT_SIGNAL_DIR
try {
  if ($originalMode.Width -lt 1600 -or $originalMode.Height -lt 1000) {
    $result = [DartPdfCapture]::ChangeDisplaySettings([ref]$captureMode, 0)
    if ($result -ne 0) { throw "Cannot provision a 1920x1080 desktop (Windows result $result)." }
    $displayChanged = $true
    Start-Sleep -Seconds 2
  }
  $env:DARTPDF_SHOT_SIGNAL_DIR = $signals
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
    # The handshake holds the scene while Flutter lays out at the capture size.
    Start-Sleep -Seconds 3
    if ([DartPdfCapture]::GetForegroundWindow() -ne $window) {
      throw 'The capture window is obscured; refusing to capture another application.'
    }
    $rect = New-Object DartPdfCapture+Rect
    if ([DartPdfCapture]::DwmGetWindowAttribute($window, 9, [ref]$rect, 16) -ne 0) {
      if (-not [DartPdfCapture]::GetWindowRect($window, [ref]$rect)) { throw 'Cannot read window bounds.' }
    }
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -lt 1366 -or $height -lt 768) { throw "Window too small for Store: ${width}x${height}." }
    $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
    if ($rect.Left -lt $screen.Left -or $rect.Top -lt $screen.Top -or
        $rect.Right -gt $screen.Right -or $rect.Bottom -gt $screen.Bottom) {
      throw 'Window extends beyond the desktop; refusing a clipped capture.'
    }
    $path = Join-Path $output "$scene.png"
    $bitmap = [System.Drawing.Bitmap]::new($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, [System.Drawing.Size]::new($width, $height))
      # A failed compositor/desktop session can return a solid black frame.
      $colors = [Collections.Generic.HashSet[int]]::new()
      for ($y = 40; $y -lt $height; $y += 20) {
        for ($x = 20; $x -lt $width; $x += 20) {
          [void]$colors.Add($bitmap.GetPixel($x, $y).ToArgb())
        }
      }
      if ($colors.Count -lt 20) { throw "Scene $scene appears blank ($($colors.Count) sampled colors)." }
      $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
      $graphics.Dispose()
      $bitmap.Dispose()
    }
    $captures += @{
      file = "$scene.png"; width = $width; height = $height
      sha256 = (Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    Write-Host "Captured $scene at ${width}x${height}: $path"
    Set-Content (Join-Path $signals "$scene.captured") 'captured'
  }
  if (@($captures.sha256 | Select-Object -Unique).Count -ne 3) {
    throw 'Expected three different scenes, but some captures are identical.'
  }
  @{
    platform = 'windows'; capture = 'native window pixels via CopyFromScreen'
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
  if ($displayChanged) { [DartPdfCapture]::ChangeDisplaySettings([ref]$originalMode, 0) | Out-Null }
  Remove-Item $signals -Recurse -Force
}
