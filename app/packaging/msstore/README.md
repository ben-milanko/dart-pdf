# Microsoft Store packaging for DartPDF

Builds the Store MSIX and pushes it into a Partner Center submission. Both
halves are plain CLI, so the per-release path is fully headless after the first
submission has a package registered in Partner Center:

| Step | Tool | Script |
|---|---|---|
| Build the MSIX | [`msix`](https://pub.dev/packages/msix) pub package (`dart run msix:create --store`) | [`build-msix.ps1`](build-msix.ps1) |
| Upload the submission | [Microsoft Store Developer CLI](https://learn.microsoft.com/windows/apps/publish/msstore-dev-cli/overview) (`msstore publish`) | [`publish-msix.ps1`](publish-msix.ps1) |

CI wiring is [`.github/workflows/release-windows-store.yml`](../../../.github/workflows/release-windows-store.yml).
`.github/workflows/ci.yml`'s `windows-store-scripts` job parse-checks the
PowerShell and the `msix_config` block on every PR, so neither can rot without a
Windows runner.

Both scripts are **Windows-only** at run time: `msix` shells out to the
`makeappx.exe`/`makepri.exe` it bundles (no Windows SDK needed), and `msstore` is
a Windows binary here. Everything else about the scripts is portable.

## What is *not* scriptable

Creating the app is a one-time manual job. **You cannot reserve an app name or
create the app through the API** — Microsoft's own docs say you must create it in
Partner Center first, after which the API can manage its submissions. Same shape
as the Play/App Store boundary in [`app/RELEASING.md`](../../RELEASING.md).

## One-time setup checklist

Do this once, in order — steps 4-5 need the values that 2-3 mint, and step 7
needs a package already uploaded by step 6. Partner Center is at
<https://partner.microsoft.com/dashboard>.

- [ ] **1. Register a developer account.** Free as of 2026 for both individual and
      company accounts (the old $19/$99 fees were dropped). An *organization*
      account shows the org as the seller name, the same trade-off RES already
      carries on Apple/Play.
- [ ] **2. Reserve the app name `DartPDF`.** This is the step the API cannot do,
      and it mints the identity values the MSIX must carry.
- [ ] **3. Register an Azure AD application, associate it with the Partner Center
      account** (*Account settings → User management → Azure AD applications*),
      and register a certificate credential on it. The **association** is the
      part that is easy to miss: without it the credentials authenticate fine
      but see no products, which reads like a permissions bug.
- [ ] **4. Set the 4 repository variables** (*Settings → Secrets and variables →
      Actions → Variables*). Values and dashboard paths: table below.
- [ ] **5. Set the 5 repository secrets** (same page, *Secrets* tab).
- [ ] **6. Dry-run the pipeline.** Actions → *Release Windows Store* → Run
      workflow, **`commit` unchecked**. This builds the MSIX and uploads it as a
      draft — the first end-to-end proof, since `makeappx`/`makepri` and Store
      authentication cannot be tested off Windows. Check the
      `windows-store-msix` artifact exists and the run didn't skip (a skip means
      a value from 4-5 is missing; the log's `::notice::` names which). On a
      brand-new product, Microsoft Store Developer CLI v0.3.9 can report a
      successful `--noCommit` upload without attaching that first package in
      the Partner Center UI. If *Packages* is still incomplete, download the
      artifact and upload the MSIX there once. After that bootstrap, the CLI
      updates the registered submission on later releases.
- [ ] **7. Complete the first submission in the UI.** Listing description,
      screenshots, category, privacy policy URL (host `app/PRIVACY.md`, as Play
      does) and the age-rating questionnaire. Screenshots and age rating are not
      CLI-drivable, so the *first* release is manual — every one after is not.
- [ ] **8. Submit for certification** and confirm it passes.
- [ ] **9. Confirm the automated path** on the next release: push an `app-v*` tag,
      check a draft submission appears, then run the workflow with `commit`
      checked to send it.

After that, `release-windows-store.yml` handles each release.

## Configuration: 4 variables + 5 secrets

All nine are set in *Settings → Secrets and variables → Actions*, but on
**different tabs**. The workflow **skips (does not fail)** while any is missing,
so an unconfigured account cannot turn an `app-v*` tag red; its `::notice::` says
which are missing and which tab each belongs on.

**Repository *variables*** — public by construction, so masking them would only
make the logs harder to read. The first three are embedded in the shipped MSIX
manifest (unzip any Store package and you can read them); the Store ID is in the
app's public Store URL.

| Variable | Where to find it |
|---|---|
| `MSSTORE_IDENTITY_NAME` | Product → Product identity → `Package/Identity/Name` |
| `MSSTORE_PUBLISHER` | Product → Product identity → `Package/Properties/Publisher` (a `CN=…` string) |
| `MSSTORE_PUBLISHER_DISPLAY_NAME` | Product → Product identity → `Package/Properties/PublisherDisplayName` |
| `MSSTORE_PRODUCT_ID` | Product → Product identity → **Store ID** |

**Repository *secrets*** — the base64 PFX and its password are credentials. The
three IDs are identifiers, kept masked as defence in depth so leaked certificate
material isn't accompanied by everything needed to use it.

| Secret | Where to find it |
|---|---|
| `MSSTORE_CERTIFICATE_BASE64` | Base64 of a password-protected PFX whose public certificate is registered on the associated Azure AD app |
| `MSSTORE_CERTIFICATE_PASSWORD` | The PFX password |
| `MSSTORE_TENANT_ID` | Account settings → User management → Azure AD applications |
| `MSSTORE_CLIENT_ID` | The associated Azure AD app registration |
| `MSSTORE_SELLER_ID` | Account settings → Account details → **Seller ID** |

**This repo is public, so Actions logs are world-readable.** GitHub masks
registered secret values, but the scripts don't rely on that: they never echo a
credential. `build-msix.ps1` does print the four public identifiers, which is the
whole reason they are variables rather than secrets. Keep that split if you add
logging. The workflow's artifact upload is a narrow `*.msix` glob, so the
credential file `msstore reconfigure` writes cannot be picked up.

The identity values are deliberately **not** in `app/pubspec.yaml`: a checked-in
placeholder identity builds a package the Store silently refuses, so
`build-msix.ps1` requires them from the environment and names the exact dashboard
path in its error.

## Per-release flow

Pushing an `app-v*` tag builds the MSIX and uploads it as a **draft** submission
— nothing reaches the public Store until you review it, mirroring the *draft*
GitHub Release that `release-app.yml` creates.

To send it to certification, run the workflow manually
(Actions → Release Windows Store → Run workflow) with **commit** checked, and
optionally a rollout percentage. Or locally, from `app/packaging/msstore`:

```powershell
$env:MSSTORE_IDENTITY_NAME = '…'; $env:MSSTORE_PUBLISHER = 'CN=…'
$env:MSSTORE_PUBLISHER_DISPLAY_NAME = '…'
./build-msix.ps1 -Version 3.0.0

$env:MSSTORE_TENANT_ID = '…'; $env:MSSTORE_SELLER_ID = '…'
$env:MSSTORE_CLIENT_ID = '…'
$env:MSSTORE_CERTIFICATE_BASE64 = '…'
$env:MSSTORE_CERTIFICATE_PASSWORD = '…'
$env:MSSTORE_PRODUCT_ID = '…'
./publish-msix.ps1 -MsixPath ../../build/windows/msstore/dartpdf-windows-store.msix -Commit
```

## Gotchas

- **Submissions must be unsigned.** The Store re-signs with the publisher's
  certificate, so a package we signed is rejected. `store: true` in `msix_config`
  makes `msix` skip signing; `build-msix.ps1` asserts the output is unsigned
  rather than trusting that.
- **The version's revision field must be `0`** and the whole version must be
  *higher than the last published one*. `build-msix.ps1` takes `X.Y.Z` and
  appends `.0`; the pubspec build number goes to Flutter as `--build-number`, not
  into the MSIX version. Bumping only the build number therefore produces a
  version the Store rejects as a duplicate — bump `X.Y.Z`.
- **The MSIX carries no MSVC runtime.** Unlike the NSIS/zip artifacts in
  `release-app.yml`, which copy `msvcp140.dll` & friends to run on clean PCs, an
  MSIX gets its runtime from the OS via the framework dependency.
- **`.pdf` association** is declared by `msix_config`'s `file_extension`, which
  is what registers DartPDF as a PDF handler at install time. The NSIS installer
  does the same thing through the registry. Neither can make DartPDF the
  *default* handler — see RELEASING.md's "File associations".
- **The msstore CLI is framework-dependent** (`net9.0`), so a .NET 9 runtime must
  be present; the workflow installs it with `actions/setup-dotnet`. The CLI
  archive is pinned by version *and* SHA-256 in `publish-msix.ps1`, the way
  `release-app.yml` pins `appimagetool`.
- **Telemetry** is turned off (`msstore settings --enableTelemetry false`) before
  any authenticated call.

## Store MSIX vs. the existing Windows artifacts

`release-app.yml`'s `windows` job keeps producing the unsigned portable zip, the
self-extracting exe, and the NSIS installer — those feed the in-app update
checker (`app/lib/update_installer.dart`), which reads GitHub Releases and knows
those exact file names. The Store MSIX is an additional distribution channel and
deliberately lands in a separate workflow so a Partner Center outage or a
credential problem cannot fail the artifact build a release depends on.

Store-installed builds update through the Store, so the in-app updater is
redundant there; it is harmless because it only offers a download.
