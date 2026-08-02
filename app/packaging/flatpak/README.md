# DartPDF Flatpak packaging

Flatpak is the preferred Linux installation for DartPDF. The official signed
repository is hosted at <https://dartpdf-flatpak.web.app>; it is independent of
Flathub and therefore remains under the project's release policy and control.

Install the current stable release:

```sh
flatpak install --from \
  https://dartpdf-flatpak.web.app/dartpdf.flatpakref
```

The one-click reference adds the `dartpdf` remote, imports the embedded public
key, installs the Freedesktop runtime from Flathub, and installs
`dev.milanko.dartpdf`. Subsequent releases arrive through normal Flatpak
updates.

## Files

- `dev.milanko.dartpdf.yml` — binary Flatpak manifest.
- `desktop-assets/` — reviewable copies of the `.desktop`, AppStream metadata,
  and hicolor icons installed by the manifest.
- `sync-desktop-assets.sh` — refreshes those copies from authoritative files
  under `app/linux/`.
- `build-self-hosted-repo.sh` — builds and signs the hosted OSTree repository.
- `dartpdf-flatpak-public-key.gpg` / `.asc` — public repository signing key.
- `dartpdf-flatpak-key.fingerprint` — immutable fingerprint checked by CI.

The manifest unpacks the portable Linux tarball produced by the app release
workflow instead of rebuilding Flutter inside the Flatpak sandbox. Its checked-
in source URL pins the current stable release for local builds. Repository CI
temporarily replaces that source with the digest-verified release asset it has
downloaded, so publishing never depends on a draft or not-yet-uploaded URL.
The GNOME runtime supplies the GTK desktop stack and `libsecret` used by
`flutter_secure_storage`; dependencies outside that runtime stay bundled with
the release archive.

## Sandbox permissions

| Permission | Reason |
|---|---|
| `--socket=wayland` + `--socket=fallback-x11` | Native Wayland rendering with X11 fallback. |
| `--share=ipc` | Shared-memory surfaces used by GTK/X11. |
| `--device=dri` | GPU-accelerated rendering. |
| `--talk-name=org.freedesktop.secrets` | Store digital-signing identities through Secret Service/libsecret. |
| `--share=network` | Optional keyless signing, timestamps, certificate revocation checks, OCR model downloads, and update transport. Documents remain local. |

There is deliberately no broad filesystem permission. `GtkFileChooserNative`
and the `%U` desktop-file argument use XDG document/file-chooser portals, so the
app receives only files the user selected.

## Local manifest test

On Linux:

```sh
sudo apt install flatpak flatpak-builder
flatpak remote-add --if-not-exists --user flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub \
  org.gnome.Platform//50 org.gnome.Sdk//50

cd app/packaging/flatpak
flatpak-builder --user --install --force-clean \
  build-dir dev.milanko.dartpdf.yml
flatpak run dev.milanko.dartpdf
```

After changing desktop metadata or icons, run:

```sh
app/packaging/flatpak/sync-desktop-assets.sh
```

## Publishing

`.github/workflows/publish-flatpak.yml` runs when an `app-v*` GitHub Release is
published. It verifies the release asset's GitHub SHA-256 digest, imports the
dedicated signing key, builds and signs the app commit and repository summary,
installs the package from the signed local remote, smoke-tests it, and deploys
the repository to its dedicated Firebase Hosting site.

The private key is the Actions secret `FLATPAK_GPG_PRIVATE_KEY`. Its public
fingerprint is:

```text
32E5 3D63 14CF 1F14 4846 2E23 19EF DD96 AD44 514D
```

The signing key must remain stable. Replacing it would require users to remove
and re-add the remote. Backup locations and manual-dispatch instructions are in
[`flatpak-hosting/README.md`](../../../flatpak-hosting/README.md).
