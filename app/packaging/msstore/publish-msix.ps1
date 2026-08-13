<#
.SYNOPSIS
  Uploads a DartPDF MSIX to the Microsoft Store via the Microsoft Store
  Developer CLI.

.DESCRIPTION
  Installs a pinned msstore CLI (checksum-verified), configures it from the
  Partner Center certificate credential in the environment, and pushes the
  package into the app's submission.

  Defaults to leaving the submission as a **draft** (`--noCommit`), matching how
  release-app.yml creates a *draft* GitHub Release: nothing reaches the public
  Store until a human reviews it. Pass -Commit to send it to certification.

.PARAMETER MsixPath
  The .msix to upload - the output of build-msix.ps1.

.PARAMETER Commit
  Commit the submission (sends it to Store certification). Without this the
  submission stays a draft in Partner Center.

.PARAMETER RolloutPercentage
  Package rollout percentage, 0-100. Only meaningful with -Commit.

.PARAMETER CliVersion
  msstore CLI release tag to install. Pinned so a CLI release cannot silently
  change release behaviour.

.EXAMPLE
  $env:MSSTORE_TENANT_ID = '...'; $env:MSSTORE_SELLER_ID = '...'
  $env:MSSTORE_CLIENT_ID = '...'
  $env:MSSTORE_CERTIFICATE_BASE64 = '...'
  $env:MSSTORE_CERTIFICATE_PASSWORD = '...'
  $env:MSSTORE_PRODUCT_ID = '9NABCDEFGHIJ'
  ./publish-msix.ps1 -MsixPath ../../build/windows/msstore/dartpdf-windows-store.msix
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$MsixPath,
  [switch]$Commit,
  [ValidateRange(0, 100)][int]$RolloutPercentage = -1,
  [string]$CliVersion = 'v0.3.9',
  [string]$CliSha256 = 'bf2f9aa47135eb0820c69a3936e2592a3847248fc650a6cda51cf3b5a8c605fb'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $MsixPath)) { throw "MSIX not found: $MsixPath" }
$MsixPath = (Resolve-Path $MsixPath).Path

function Get-RequiredEnv {
  param([string]$Name, [string]$Where)
  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "$Name is not set. $Where`n`nSee app/packaging/msstore/README.md."
  }
  return $value
}

$tenantId     = Get-RequiredEnv 'MSSTORE_TENANT_ID' 'Partner Center > Account settings > User management > Azure AD applications.'
$sellerId     = Get-RequiredEnv 'MSSTORE_SELLER_ID' 'Partner Center > Account settings > Account details > Seller ID.'
$clientId     = Get-RequiredEnv 'MSSTORE_CLIENT_ID' 'The Azure AD app registration associated with the Partner Center account.'
$certificateBase64 = Get-RequiredEnv 'MSSTORE_CERTIFICATE_BASE64' 'A base64-encoded PFX whose public certificate is registered on the Azure AD app.'
$certificatePassword = Get-RequiredEnv 'MSSTORE_CERTIFICATE_PASSWORD' 'The password protecting the PFX certificate.'
$productId    = Get-RequiredEnv 'MSSTORE_PRODUCT_ID' 'Partner Center > Product > Product identity > Store ID.'

# --- Install the CLI ------------------------------------------------------
# Not `winget install`: winget is not reliably usable on hosted runners and
# would float the version. A pinned, checksum-verified release archive matches
# how release-app.yml pins appimagetool.
$cliDir = Join-Path ([System.IO.Path]::GetTempPath()) "msstore-cli-$CliVersion"
$msstore = Join-Path $cliDir 'msstore.exe'

if (-not (Test-Path $msstore)) {
  $zip = Join-Path ([System.IO.Path]::GetTempPath()) "MSStoreCLI-$CliVersion.zip"
  $url = "https://github.com/microsoft/msstore-cli/releases/download/$CliVersion/MSStoreCLI-win-x64.zip"
  Write-Host "Downloading msstore CLI $CliVersion"
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

  $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $CliSha256.ToLowerInvariant()) {
    throw "msstore CLI checksum mismatch`n  expected $CliSha256`n  actual   $actual"
  }

  New-Item -ItemType Directory -Force -Path $cliDir | Out-Null
  Expand-Archive -Path $zip -DestinationPath $cliDir -Force
  if (-not (Test-Path $msstore)) { throw "msstore.exe not found after extracting $zip" }
}

# The archive is framework-dependent (msstore.runtimeconfig.json targets
# net9.0/Microsoft.NETCore.App 9.0.0), so a .NET 9 runtime must already be on
# the machine - the workflow installs it with actions/setup-dotnet.
& $msstore --version | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw "msstore CLI failed to start ($LASTEXITCODE); is the .NET 9 runtime installed?"
}

# --- Configure ------------------------------------------------------------
# Telemetry off before any authenticated call, so a CI run reports nothing.
& $msstore settings --enableTelemetry false | Out-Null

# Decode the PFX only on the ephemeral runner and delete it even when the
# authenticated Store call fails. The public certificate is registered in
# Entra; the private key and password exist only as GitHub encrypted secrets.
$certificatePath = Join-Path ([System.IO.Path]::GetTempPath()) 'dartpdf-msstore-publishing.pfx'
try {
  try {
    [System.IO.File]::WriteAllBytes(
      $certificatePath,
      [Convert]::FromBase64String($certificateBase64)
    )
  } catch {
    throw 'MSSTORE_CERTIFICATE_BASE64 is not valid base64 certificate data.'
  }

  # This repo is public, so Actions logs are world-readable. GitHub masks
  # registered secret values, but don't rely on that - just never echo them.
  Write-Host 'Configuring msstore CLI from the Partner Center certificate credential'
  & $msstore reconfigure `
    --tenantId $tenantId `
    --sellerId $sellerId `
    --clientId $clientId `
    --certificateFilePath $certificatePath `
    --certificatePassword $certificatePassword | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "msstore reconfigure failed ($LASTEXITCODE)" }

  # --- Publish ------------------------------------------------------------
  # --appId is needed because we never ran `msstore init` - the package is built
  # by build-msix.ps1, not by the CLI, so there is no CLI-side project state.
  # v0.3.9 accepts a package directory, not a package-file argument; this
  # directory contains only the single deterministic Store MSIX.
  $inputDirectory = Split-Path -Parent $MsixPath
  $publishArgs = @(
    'publish', '--inputDirectory', $inputDirectory, '--appId', $productId
  )
  if (-not $Commit) {
    Write-Host 'Uploading as a DRAFT submission (pass -Commit to send to certification)'
    $publishArgs += '--noCommit'
  } else {
    Write-Host 'Uploading and COMMITTING the submission - this sends it to Store certification'
    if ($RolloutPercentage -ge 0) {
      $publishArgs += @('--packageRolloutPercentage', "$RolloutPercentage")
    }
  }

  & $msstore @publishArgs
  if ($LASTEXITCODE -ne 0) { throw "msstore publish failed ($LASTEXITCODE)" }

  Write-Host "`nSubmission status:"
  & $msstore submission status $productId

  Write-Host "`nReview the submission at https://partner.microsoft.com/dashboard"
} finally {
  Remove-Item -LiteralPath $certificatePath -Force -ErrorAction SilentlyContinue
}
