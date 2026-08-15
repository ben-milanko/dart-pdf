param([string]$DartDefines = "")

foreach ($encoded in $DartDefines.Split(',')) {
  try {
    $define = [Text.Encoding]::UTF8.GetString(
      [Convert]::FromBase64String($encoded))
  } catch {
    continue
  }
  $prefix = 'FLUTTER_ENABLED_FEATURE_FLAGS='
  if (-not $define.StartsWith($prefix)) {
    continue
  }
  if ($define.Substring($prefix.Length).Split(',') -contains 'windowing') {
    Write-Output 1
    exit 0
  }
}

Write-Output 0
