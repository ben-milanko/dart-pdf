# AUR packaging for DartPDF (`dartpdf-bin`)

`dartpdf-bin` repackages the official prebuilt Linux release for Arch Linux and
derivatives, so users can `paru -S dartpdf-bin` / `yay -S dartpdf-bin`.

- **Package:** binary (`-bin`) — installs the release bundle under
  `/opt/dartpdf` and symlinks `/usr/bin/dartpdf`.
- **Source of truth for the `PKGBUILD`:** this directory. The AUR git repo is a
  publish target; keep this copy authoritative and push from here.

## Why extra sources beyond the tarball

The `app-v3.0.0` release tarball carries only the binary + `data/` + `lib/` — it
predates the CMake rules (#547) that add the `.desktop`/metainfo/icons to the
bundle's `share/` tree. So the `PKGBUILD` fetches those six files from the
source repo, pinned to an immutable commit (`_assets_commit`), and installs them
itself. When a release built from a tree that includes #547 ships, the tarball
will carry `share/` and you can drop the `*_assets` sources and install straight
from the unpacked bundle instead.

## Per-release update

1. Bump `pkgver` to the new `app-v<version>` (and reset `pkgrel=1`).
2. Refresh checksums:
   ```sh
   cd app/packaging/aur
   updpkgsums                       # rewrites sha256sums[] from the sources
   ```
   If you also moved `_assets_commit` (e.g. to pick up a new metainfo
   `<release>` entry), do that first, then `updpkgsums`.
3. Regenerate the metadata and sanity-build:
   ```sh
   makepkg --printsrcinfo > .SRCINFO
   makepkg -f                       # builds the package locally
   namcap PKGBUILD *.pkg.tar.zst    # lint (optional but recommended)
   ```
4. Test-install: `sudo pacman -U dartpdf-bin-*.pkg.tar.zst`, then `dartpdf`.

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
