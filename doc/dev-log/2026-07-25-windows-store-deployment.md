# 2026-07-25 - Microsoft Store deployment (pure CLI)

Added a headless Microsoft Store release path for the app. Constraint set by
the request: **only if it can be pure CLI/script** - no GUI-driven release step.
It can, for the per-release path; the account/app creation genuinely cannot, and
that boundary is documented rather than papered over.

## Shape

Two halves, both plain CLI:

- **Build** - the [`msix`](https://pub.dev/packages/msix) pub package as a
  dev-dependency of `app`, driven by `dart run msix:create --store`.
  Configuration lives in `msix_config` in `app/pubspec.yaml`.
- **Upload** - Microsoft's [msstore CLI](https://github.com/microsoft/msstore-cli),
  `msstore reconfigure` + `msstore publish --inputFile … --appId …`.

Scripts in `app/packaging/msstore/` (`build-msix.ps1`, `publish-msix.ps1`),
wired by `.github/workflows/release-windows-store.yml`. Docs:
`app/packaging/msstore/README.md`.

## Why a separate workflow, not a job in release-app.yml

`release-app.yml` produces the artifacts the in-app update checker depends on
(`app/lib/update_installer.dart` reads GitHub Releases and matches exact file
names). A Partner Center outage or a credential problem must not fail that
build. The Store MSIX is an additional channel, so it gets its own workflow with
its own `workflow_dispatch` inputs (version / commit / rollout percentage) and
can be re-run without rebuilding every platform.

## Decisions worth remembering

**The three Partner Center identity values are deliberately NOT in pubspec.yaml.**
`identity_name`, `publisher`, `publisher_display_name` are account-specific, and
a checked-in placeholder builds a package the Store *silently refuses* rather
than failing the build. `build-msix.ps1` requires them from the environment and
its error names the exact dashboard path for each. A `ci.yml` guard fails if
anyone later pins them in the pubspec.

**Store submissions must be unsigned.** Microsoft re-signs with the publisher's
certificate, so a package we signed is rejected. `store: true` makes `msix` skip
signing (`if (_config.signMsix && !_config.store)` in msix.dart). `build-msix.ps1`
*asserts* the output is unsigned via `Get-AuthenticodeSignature` rather than
trusting the flag - this is the failure mode that would otherwise only surface
as a rejected submission days later. This is also why the Store channel needs no
Authenticode cert while the NSIS installer still does.

**Version revision must be 0**, and the whole version must exceed the last
published one. `msix` derives `major.minor.patch.0` from the pubspec version;
the build number goes to Flutter as `--build-number` and never into the MSIX
version. So bumping only the build number yields a duplicate the Store rejects -
bump `X.Y.Z`.

**The workflow skips, not fails, when configuration is absent.** An unset secret
must not turn every `app-v*` tag red - that trap already bit the web-worker PRs
with `WORKER_REGEN_TOKEN`. A gate step checks all eight values and emits a
`::notice::` naming which are missing and which tab each belongs on.

**Four repository variables, four secrets** - not eight secrets. `identity_name`,
`publisher`, `publisher_display_name` and the Store ID are public *by
construction*: the first three are embedded in the shipped MSIX manifest (unzip
any Store package to read them) and the Store ID is in the app's public Store
URL. Registering them as secrets would mask them to `***` in the logs, costing
debuggability for zero security gain. Only `MSSTORE_CLIENT_SECRET` is a real
credential; the tenant/client/seller IDs stay secrets as defence in depth, so a
leaked client secret isn't accompanied by everything needed to use it. This split
is why `build-msix.ps1` may print its three identity values while
`publish-msix.ps1` prints none of its inputs.

**Tag push = draft submission.** Committing to certification is an explicit
manual run, mirroring how `release-app.yml` creates a *draft* GitHub Release.

**msstore CLI is framework-dependent** (`msstore.runtimeconfig.json` targets
`net9.0`/`Microsoft.NETCore.App 9.0.0`), so the workflow installs .NET 9 with
`actions/setup-dotnet`. Not `winget install` for the CLI itself - that floats the
version; the release zip is pinned by tag *and* SHA-256
(`bf2f9aa4…605fb` for v0.3.9), the way `release-app.yml` pins `appimagetool`.
Note `msix` needs no Windows SDK - it bundles its own makeappx/makepri.

**`file_extension: .pdf`** closes a long-standing TODO in `RELEASING.md`: the
MSIX manifest is how Windows learns the association at install time, the
equivalent of the NSIS installer's ProgID registry writes.

## What is not scriptable (and why the docs say so)

Microsoft's docs are explicit that the submission API cannot create an app - the
name must be reserved in Partner Center by hand. Also manual, one-time: the
Azure AD app registration and its *association* with the Partner Center account
(without the association the credentials authenticate but see no products), and
the first submission's listing/screenshots/age-rating. Registration itself is now
free for both individual and company accounts (the old $19/$99 fees were dropped
in 2026). Same boundary as Play and the App Store in `RELEASING.md`.

## Verification

No Windows machine here, so everything short of the two Windows binaries was
exercised locally with a self-contained PowerShell 7.6.4:

- Both scripts parse-checked with `Parser::ParseFile`; guard clauses tested
  (missing credentials, bad version format, missing MSIX, rollout out of range),
  and version derivation confirmed to yield `3.0.0` / build `20` → MSIX `3.0.0.0`.
- The workflow's gate step tested for all-unset / all-set / one-missing.
- `msix:create` run against a faked `Release/` folder: it validated the whole
  config, resolved `logo_path: ../doc/icon-1024.png`, generated all **82** scaled
  tile/logo PNGs, and emitted an `AppxManifest.xml` with the right `<Identity>`
  (`Version="3.0.0.0"`, `ProcessorArchitecture="x64"`), `internetClient` +
  `runFullTrust` capabilities, and the `.pdf` `FileTypeAssociation`. It stopped
  exactly at `makepri.exe` - the Windows-only boundary.
- A `ci.yml` job (`windows-store-scripts`, ubuntu + preinstalled `pwsh`) keeps
  the PowerShell and `msix_config` from rotting without paying for a Windows
  runner. Its config guard was mutation-tested: flipping `store` to false,
  deleting it, changing `file_extension`, and deleting `architecture` are all
  caught.

One bug found by that mutation testing and fixed: the guard originally
substring-matched `'store: true'`, which passed even with the key flipped to
`false` because the explanatory comment in `pubspec.yaml` contains that same
literal text. The checks are now anchored regexes against the real YAML keys.

**Still unverified:** `makepri.exe`/`makeappx.exe` packaging, and the upload
itself - both need Windows, and the upload needs a Partner Center account that
does not exist yet. The first real run should be a `workflow_dispatch` without
`commit`, so it lands as a draft.
