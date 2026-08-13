# DartPDF Snap packaging

Snap Store is a secondary Linux distribution channel for DartPDF. Flatpak
remains the preferred Linux install; the snap gives Ubuntu and other snapd
users native Store discovery and package-managed updates.

Install the stable release:

```sh
sudo snap install dartpdf
```

The strictly-confined package uses the `home` interface for user-selected PDFs,
the GNOME extension for the Flutter/GTK desktop runtime, and narrowly scoped
interfaces for networking, printing, removable media, and the desktop password
manager. `removable-media` and `password-manager-service` do not
auto-connect by default; users can connect them when those features are needed:

```sh
sudo snap connect dartpdf:removable-media
sudo snap connect dartpdf:password-manager-service
```

## Local build

On Ubuntu 24.04 or newer:

```sh
sudo snap install snapcraft --classic
app/packaging/snap/build-release-snap.sh \
  --archive /path/to/dartpdf-linux-x64.tar.gz \
  --version 3.5.0 \
  --output /tmp/dartpdf-snap
sudo snap install --dangerous /tmp/dartpdf-snap/dartpdf_*.snap
snap run dartpdf
```

The checked-in recipe pins the current stable GitHub release and SHA-256 for
reproducible local builds. CI replaces that URL with the already-downloaded,
digest-verified release archive.

## Publishing

`.github/workflows/publish-snap.yml` builds, lints, installs, and launches the
snap whenever an `app-v*` GitHub Release is published. With the repository
secret `SNAPCRAFT_STORE_CREDENTIALS` configured, it uploads the package to the
Snap Store stable channel, then performs a clean Store install and launch test.

The credential should be scoped to the `dartpdf` snap, the stable channel, and
the `package_push,package_release,package_update` ACLs. Export and rotate it as
documented in `app/RELEASING.md`.
