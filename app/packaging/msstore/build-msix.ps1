<#
.SYNOPSIS
  Builds the Microsoft Store MSIX for DartPDF.

.DESCRIPTION
  Runs `flutter build windows --release` and then `dart run msix:create --store`
  over its output. Most settings come from `msix_config` in app/pubspec.yaml;
  the three Partner Center identity values are supplied here from the
  environment so no placeholder identity is checked in.

  `--store` makes msix skip signing: the Store re-signs every submission with
  the publisher's certificate, and a package we signed ourselves is rejected.

  Windows-only - msix shells out to the makeappx.exe/makepri.exe it bundles.

.PARAMETER Version
  Marketing version, e.g. 3.0.0. The MSIX version becomes <Version>.0 because
  the Store requires the revision field to be 0. Defaults to the `version:` in
  app/pubspec.yaml.

.PARAMETER BuildNumber
  Passed to Flutter as --build-number. Defaults to the pubspec build number.

.PARAMETER OutputDir
  Where the .msix is written. Defaults to app/build/windows/msstore.

.EXAMPLE
  $env:MSSTORE_IDENTITY_NAME       = '12345ABCDE.DartPDF'
  $env:MSSTORE_PUBLISHER           = 'CN=ABCD1234-...'
  $env:MSSTORE_PUBLISHER_DISPLAY_NAME = 'Ben Milanko'
  ./build-msix.ps1 -Version 3.0.0
#>
[CmdletBinding()]
param(
  [string]$Version,
  [string]$BuildNumber,
  [string]$OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# app/ - the directory holding the pubspec msix reads.
$appDir = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

function Get-RequiredEnv {
  param([string]$Name, [string]$PartnerCenterPath)
  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw @"
$Name is not set.

Find it in Partner Center:
  $PartnerCenterPath

See app/packaging/msstore/README.md for the full one-time setup.
"@
  }
  return $value
}

# These identify the Store listing, so a wrong or missing value produces a
# package the Store silently refuses rather than a build error. Demand them up
# front, with the exact dashboard path to each.
$identityName = Get-RequiredEnv 'MSSTORE_IDENTITY_NAME' `
  'Product > Product identity > Package/Identity/Name'
$publisher = Get-RequiredEnv 'MSSTORE_PUBLISHER' `
  'Product > Product identity > Package/Properties/Publisher'
$publisherDisplayName = Get-RequiredEnv 'MSSTORE_PUBLISHER_DISPLAY_NAME' `
  'Product > Product identity > Package/Properties/PublisherDisplayName'

# Fall back to the pubspec version, which is the single source of truth for
# every other platform build (see app/RELEASING.md).
$pubspecVersion = (Select-String -Path (Join-Path $appDir 'pubspec.yaml') `
    -Pattern '^version:\s*(\S+)' | Select-Object -First 1
).Matches[0].Groups[1].Value
if (-not $pubspecVersion) { throw "Could not read version: from app/pubspec.yaml" }

if (-not $Version)     { $Version     = ($pubspecVersion -split '\+')[0] }
if (-not $BuildNumber) { $BuildNumber = ($pubspecVersion -split '\+')[1] }
if (-not $BuildNumber) { $BuildNumber = '1' }
if (-not $OutputDir)   { $OutputDir   = Join-Path $appDir 'build/windows/msstore' }

# The Store wants exactly four parts with a 0 revision; it rejects anything
# else and refuses a version <= the last published one.
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
  throw "Version must be X.Y.Z (got '$Version'); the Store revision field is forced to 0."
}
$msixVersion = "$Version.0"

Write-Host "Building DartPDF $Version (build $BuildNumber) as MSIX $msixVersion"
# Safe to print: all three are embedded in the shipped MSIX manifest, so they
# are public by construction (anyone can unzip a Store package and read them).
# That is why they are repository *variables* rather than secrets - see
# packaging/msstore/README.md. The credentials in publish-msix.ps1 are never
# printed. This repo is public, so Actions logs are world-readable - keep it
# that way.
Write-Host "  identity_name          : $identityName"
Write-Host "  publisher              : $publisher"
Write-Host "  publisher_display_name : $publisherDisplayName"

Push-Location $appDir
try {
  & flutter build windows --release `
    --build-name=$Version --build-number=$BuildNumber
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed ($LASTEXITCODE)" }

  # The Release folder is what the portable zip ships; the MSIX runtime is
  # supplied by the OS, so no msvcp140/vcruntime140 copy is needed here (unlike
  # the NSIS/zip artifacts in release-app.yml).
  New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

  & dart run msix:create `
    --store `
    --version $msixVersion `
    --identity-name $identityName `
    --publisher $publisher `
    --publisher-display-name $publisherDisplayName `
    --output-path $OutputDir
  if ($LASTEXITCODE -ne 0) { throw "msix:create failed ($LASTEXITCODE)" }
} finally {
  Pop-Location
}

$msix = Get-ChildItem -Path $OutputDir -Filter '*.msix' | Select-Object -First 1
if (-not $msix) { throw "No .msix produced in $OutputDir" }

# An unsigned package is the expected shape for a Store submission. Catch the
# opposite mistake - a signed one, which the Store rejects - before upload.
$signature = Get-AuthenticodeSignature $msix.FullName
if ($signature.Status -eq 'Valid') {
  throw "$($msix.Name) is signed; Store submissions must be unsigned (expected --store to skip signing)."
}

Write-Host "MSIX ready: $($msix.FullName) ($([math]::Round($msix.Length / 1MB, 1)) MB)"
Write-Output $msix.FullName
