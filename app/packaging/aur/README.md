# AUR packaging for DartPDF (`dartpdf-bin`)

`dartpdf-bin` repackages the official prebuilt Linux release for Arch Linux and
derivatives, so users can `paru -S dartpdf-bin` / `yay -S dartpdf-bin`.

- **Package:** binary (`-bin`) — installs the release bundle under
  `/opt/dartpdf`, preserves the GUI launcher at `/usr/bin/dartpdf`, and exposes
  the bundled CLI/MCP sidecar as `/usr/bin/dartpdf-cli`.
- **Source of truth for the `PKGBUILD`:** this directory. The AUR git repo is a
  publish target; keep this copy authoritative and push from here.

## Release payload

As of `app-v3.4.0`, the official release tarball carries the runner, `data/`,
`lib/`, and the complete desktop-integration `share/` tree. The `PKGBUILD`
installs that immutable payload directly and fetches only the Apache license
from the matching release tag.

## Per-release update

1. Bump `pkgver` to the new `app-v<version>` (and reset `pkgrel=1`).
2. Refresh checksums:
   ```sh
   cd app/packaging/aur
   updpkgsums                       # rewrites sha256sums[] from the sources
   ```
3. Regenerate the metadata and sanity-build:
   ```sh
   makepkg --printsrcinfo > .SRCINFO
   makepkg -f                       # builds the package locally
   namcap PKGBUILD *.pkg.tar.zst    # lint (optional but recommended)
   ```
4. Test-install: `sudo pacman -U dartpdf-bin-*.pkg.tar.zst`, then launch
   `dartpdf` and check the bundled CLI with `dartpdf-cli --version`.

> **Note:** `.SRCINFO` in this repo is hand-maintained to mirror the `PKGBUILD`.
> Always regenerate it with `makepkg --printsrcinfo > .SRCINFO` before pushing —
> the AUR reads package metadata from it.

## First-time publish to the AUR

You need an [AUR account](https://aur.archlinux.org) with an SSH key registered
(Account → "SSH Public Key").

```sh
# Clone the (empty) AUR repo for the package name.
git clone ssh://aur@aur.archlinux.org/dartpdf-bin.git aur-dartpdf-bin
cd aur-dartpdf-bin

# Copy the packaging files in (only PKGBUILD + .SRCINFO belong in the AUR repo).
cp /path/to/dart-pdf/app/packaging/aur/{PKGBUILD,.SRCINFO} .

git add PKGBUILD .SRCINFO
git commit -m "Initial import: dartpdf-bin 3.0.0"
git push
```

The package appears at `https://aur.archlinux.org/packages/dartpdf-bin`. For
subsequent releases, repeat the update steps above and `git push` the new
`PKGBUILD` + `.SRCINFO`.

## Relationship to a future source package

`dartpdf-bin` is the fast path. A from-source `dartpdf` package would have to
vendor the pinned Flutter SDK and build the engine, which is heavy and brittle
on a rolling distro; the binary package is the recommended route (and matches
how the Flatpak is built). Revisit a source package only if there's demand.
