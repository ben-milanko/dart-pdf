# Flathub packaging for DartPDF

This directory holds the Flatpak manifest used to publish DartPDF on
[Flathub](https://flathub.org). It is a **binary manifest**: instead of
compiling Flutter inside the Flatpak sandbox, it unpacks the release tarball
built by CI (`.github/workflows/release-app.yml`, the `linux` job →
`dartpdf-linux-x64.tar.gz`). That tarball already carries the `.desktop`,
AppStream `metainfo`, and hicolor icons that `app/linux/CMakeLists.txt`
installs into the bundle, so the manifest only has to relocate them into
`/app`.

The app id, `.desktop`, `metainfo`, and icons are all named
`dev.milanko.dartpdf`, matching the GTK `application-id` in
`app/linux/CMakeLists.txt`.

## Files

- `dev.milanko.dartpdf.yml` — the Flatpak manifest.

The `.desktop`, `metainfo`, and icon sources live in `app/linux/` (one copy,
shared by the raw bundle, the tarball, and this manifest).

## Sandbox permissions (why each `finish-arg`)

| Permission | Why |
|---|---|
| `--socket=wayland` + `--socket=fallback-x11` | Rendering/windowing (Wayland first, X11 fallback). |
| `--share=ipc` | Shared-memory path GTK/X11 use for surfaces. |
| `--device=dri` | GPU-accelerated rendering. |
| `--talk-name=org.freedesktop.secrets` | `flutter_secure_storage` stores signing-identity private keys via libsecret, which talks to the Secret Service over D-Bus. |
| `--share=network` | Keyless signing (Sigstore/Fulcio), RFC 3161 timestamps, OCSP/CRL revocation checks, and the in-app update check. No document content is uploaded. |

There is deliberately **no `--filesystem` grant**. Files reach the sandbox
through the XDG portals:

- **"Open With" / launch arguments.** The `.desktop` `Exec` carries `%U`, so
  Flatpak exports it with file-forwarding and hands the opened file into the
  sandbox without a host-filesystem hole.
- **In-app open/save dialogs.** `file_selector_linux` uses
  `GtkFileChooserNative`, which GTK automatically routes through the
  **FileChooser portal** when running under Flatpak. So the file picker is
  portal-backed with no extra work.

  **Known limitation:** a file opened this way is granted access through the
  document portal for that document. Opening a PDF from a file manager and
  saving in place works; if a save-in-place is ever refused by the portal,
  "Save As" through the picker always works. If you find an in-place-save case
  that the portal blocks, revisit whether a narrower `--filesystem=xdg-*`
  grant is warranted — but do not add a blanket `--filesystem=host`.

If the Secret Service is unavailable (no keyring running), identity storage
degrades gracefully: the signing dialog shows an empty identity list and
surfaces an error when you try to create/persist one, rather than crashing
(the store calls are wrapped in `try`/`catch` in
`app/lib/digital_signature.dart`).

## Test locally with flatpak-builder

```sh
# One-time: tooling + runtime/SDK.
sudo apt install flatpak flatpak-builder   # or your distro's equivalent
flatpak remote-add --if-not-exists --user flathub \
  https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.freedesktop.Platform//24.08 org.freedesktop.Sdk//24.08

# Fill in a real tarball URL + sha256 first (see below), then build & install.
cd app/packaging/flatpak
flatpak-builder --user --install --force-clean build-dir dev.milanko.dartpdf.yml

# Run it, or open a file with it.
flatpak run dev.milanko.dartpdf
flatpak run dev.milanko.dartpdf /path/to/file.pdf
```

To build against a locally-built tarball instead of a published release,
point the manifest's `source` at a `type: file`/`path:` (or a `file://` URL)
of a `dartpdf-linux-x64.tar.gz` you produced with
`flutter build linux --release && tar czf dartpdf-linux-x64.tar.gz -C build/linux/x64/release/bundle .`.

## Update the pinned tarball for a release

The manifest pins one release tarball by URL + sha256. For each new
`app-v<version>` release:

1. Set `sources[0].url` to
   `https://github.com/ben-milanko/dart-pdf/releases/download/app-v<version>/dartpdf-linux-x64.tar.gz`.
2. Set `sources[0].sha256` to the tarball's digest:
   `sha256sum dartpdf-linux-x64.tar.gz`.
3. Bump the `<release>` entry in `app/linux/dev.milanko.dartpdf.metainfo.xml`
   to match (Flathub requires a current `<releases>` entry).

Optionally add an external-data checker so Flathub proposes updates
automatically. For GitHub releases:

```yaml
        x-checker-data:
          type: json
          url: https://api.github.com/repos/ben-milanko/dart-pdf/releases/latest
          version-query: .tag_name | sub("^app-v"; "")
          url-query: >-
            .assets[] | select(.name == "dartpdf-linux-x64.tar.gz")
            | .browser_download_url
```

## Submit to Flathub

Flathub submissions live in a **separate repo** (`flathub/flathub`), not this
one — that is why this directory only scaffolds the manifest.

1. **Verify the app id domain.** Flathub requires that you control the domain
   in the app id (`dev.milanko` → `milanko.dev`) *or* use the code-hosting id
   form. Verification is done in the Flathub web UI, typically by adding a DNS
   `TXT` record (or a well-known file) for the domain — the homepage is
   `https://dart-pdf.com`, so coordinate the app-id domain and the
   verification method accordingly.
2. Fork `https://github.com/flathub/flathub`.
3. Create a branch named after the app id: `new-pr` is the base; push a branch
   `dev.milanko.dartpdf`.
4. Add `dev.milanko.dartpdf.yml` (this manifest, with a real URL + sha256) at
   the repo root.
5. Open a PR against the `new-pr` branch of `flathub/flathub`. The Flathub bot
   builds it and a reviewer checks the manifest.
6. Once merged, Flathub creates the per-app repo and the build goes live.

See the Flathub docs: <https://docs.flathub.org/docs/for-app-authors/submission>.
