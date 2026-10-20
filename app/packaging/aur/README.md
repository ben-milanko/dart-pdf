# Arch Linux package candidate for DartPDF

`dartpdf-bin` repackages the official prebuilt DartPDF 8.0.0 Linux release.
It is not yet published to AUR. Do not advertise `yay -S dartpdf-bin` or
`paru -S dartpdf-bin` until a live listing is verified.

This directory is the source of truth for the recipe. The
[validation repository](https://github.com/ben-milanko/dartpdf-aur) prepares
the eventual publication mirror; it is not an AUR listing.

## Package contents

The recipe keeps the GUI, CLI, native plugins, data and desktop integration.
It installs the runtime bundle under `/usr/lib/dartpdf`, with launchers at
`/usr/bin/dartpdf` and `/usr/bin/dartpdf-cli`. The 8.0.0 archive includes the
CLI, so a missing sidecar fails packaging rather than silently omitting it.

Source checksums pin the archive and Apache-2.0 license to `app-v8.0.0`.
The recipe repairs six Flutter plugins' upstream build-directory RUNPATH to
`$ORIGIN`, resolving the bundled engine beside each plugin. It does not remove
plugins or bypass source integrity checks.

## Validation and limits

[Native Arch validation](https://github.com/ben-milanko/dartpdf-aur/actions/runs/37884461790)
passed on 9 October 2026 at candidate commit
`3151fd4c0d2fcae06bb6e972ca337ffae1c4adda`. Its PKGBUILD and .SRCINFO match
the recipe here. The disposable Arch container verified source hashes,
generated metadata, makepkg output, explicit direct ELF dependencies,
installed file integrity, desktop entry, CLI inspection, a mapped GUI window
and package removal.

Namcap reports no errors, but warnings remain: some upstream binaries lack
FULL RELRO or are unstripped, some linked libraries are unused, and the
bundled JNI helper cannot resolve `libjvm.so` without a JVM. Java is an
optional dependency. The app window and CLI ran without it; the JNI feature
and every editing workflow were not tested. The CLI reports its separate
protocol version 0.1.0, not the GUI release version.

These are AI-assisted packaging and smoke checks, not an AUR acceptance
decision, a complete application regression test or evidence of new users.

## Update and publication

For each new release, verify the official artifact, refresh source checksums,
audit native dependency providers, regenerate `.SRCINFO` with
`makepkg --printsrcinfo`, then build, lint, test-install, inspect the CLI,
launch the GUI and remove the disposable test package. Do not omit lint
warnings from review or count test installs as acquisitions.

Before first publication, check the official and AUR catalogs for existing
packages, review the current
[AUR submission guidelines](https://wiki.archlinux.org/title/AUR_submission_guidelines)
and [Arch package guidelines](https://wiki.archlinux.org/title/Arch_package_guidelines),
and use the owner's AUR account and approved SSH access. Credential changes
and account terms require the owner's handoff. Adopt this update upstream
before publishing the mirror.

After an actual AUR submission, verify the native listing and install path
before announcing availability. Until then, users can download the existing
[official Linux release](https://github.com/ben-milanko/dart-pdf/releases/tag/app-v8.0.0).
