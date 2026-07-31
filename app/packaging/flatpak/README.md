# Flathub packaging for DartPDF

This directory is the **payload for the `flathub/flathub` submission**: the
Flatpak manifest plus the desktop-integration files it installs. Copy the whole
directory's tracked contents into the Flathub PR (see "Submit to Flathub").

It is a **binary manifest**: instead of compiling Flutter inside the Flatpak
sandbox, it unpacks the release tarball built by CI
(`.github/workflows/release-app.yml`, the `linux` job → `dartpdf-linux-x64.tar.gz`)
and installs the `.desktop`, AppStream `metainfo`, and hicolor icons from the
copies staged in [`desktop-assets/`](desktop-assets/).

The app id, `.desktop`, `metainfo`, and icons are all named
`dev.milanko.dartpdf`, matching the GTK `application-id` in
`app/linux/CMakeLists.txt`.

## Files

- `dev.milanko.dartpdf.yml` — the Flatpak manifest.
- `desktop-assets/` — staged copies of the `.desktop`, `metainfo.xml`, and the
  four hicolor icons, installed by the manifest.
- `sync-desktop-assets.sh` — regenerates `desktop-assets/` from `app/linux/`.

### Desktop assets: one source of truth

`app/linux/` is authoritative for the `.desktop` entry, the metainfo, and the
icons (one copy, shared by the raw bundle and the release tarball). The copies
in `desktop-assets/` exist only because they must be committed into the
*separate* `flathub/flathub` repo next to the manifest. **After any change under
`app/linux/`, run `./sync-desktop-assets.sh`** so the staged copies do not drift
(CI could assert this later).

### Self-contained release payload

The `app-v3.2.0` tarball carries `share/applications`, `share/metainfo`, and
`share/icons` alongside the runner, `data/`, and `lib/`. The manifest keeps its
staged desktop assets because they remain easy for Flathub reviewers to inspect
and make the submission independent of archive layout changes.

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
  **FileChooser portal** when running under Flatpak.

  **Known limitation:** a file opened this way is granted access through the
  document portal for that document. Opening a PDF from a file manager and
  saving in place works; if a save-in-place is ever refused by the portal,
  "Save As" through the picker always works. If you find an in-place-save case
  the portal blocks, revisit whether a narrower `--filesystem=xdg-*` grant is
  warranted — but do not add a blanket `--filesystem=host`.

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

# Build & install from this directory (the pinned tarball is fetched over HTTP).
cd app/packaging/flatpak
flatpak-builder --user --install --force-clean build-dir dev.milanko.dartpdf.yml

# Run it, or open a file with it.
flatpak run dev.milanko.dartpdf
flatpak run dev.milanko.dartpdf /path/to/file.pdf

# Lint the manifest and the built repo the way Flathub CI does.
pip install --user flatpak-builder-lint    # or: flatpak run org.flatpak.Builder ...
flatpak-builder-lint manifest dev.milanko.dartpdf.yml
flatpak-builder-lint repo build-dir      # after a --repo build
```

To build against a locally-built tarball instead of a published release, point
the manifest's archive `source` at a `type: file`/`path:` (or `file://` URL) of
a `dartpdf-linux-x64.tar.gz` you produced with
`flutter build linux --release && tar czf dartpdf-linux-x64.tar.gz -C build/linux/x64/release/bundle .`.

## Update for a new release

For each new `app-v<version>` release:

1. Set the archive `sources[0].url` to
   `https://github.com/ben-milanko/dart-pdf/releases/download/app-v<version>/dartpdf-linux-x64.tar.gz`.
2. Set `sources[0].sha256` to `sha256sum dartpdf-linux-x64.tar.gz`.
3. Add a matching `<release>` entry at the top of
   `app/linux/dev.milanko.dartpdf.metainfo.xml`, then run
   `./sync-desktop-assets.sh`. (Flathub wants a current `<releases>` entry.)

The `x-checker-data` block on the archive source lets Flathub's external-data
checker open the update PR for step 1–2 automatically once a new `app-v*`
release ships; you still do step 3.

## Submit to Flathub

Flathub submissions live in a **separate repo** (`flathub/flathub`), not this
one — that is why this directory only stages the payload.

### 1. Decide + verify the app-id domain

The app id is `dev.milanko.dartpdf`, so the id domain is **`milanko.dev`**
(reverse-DNS), *not* the homepage `dart-pdf.com`. Flathub verification (in the
Flathub web UI, after the app is accepted) can be done by:

- a DNS `TXT` record on **`milanko.dev`**, or
- a `.well-known` file served from `https://milanko.dev`, or
- linking the GitHub account that owns `github.com/ben-milanko`.

You control `milanko.dev`, so the DNS-TXT route on `milanko.dev` is the path of
least resistance and keeps the existing app id (which is already baked into the
`.desktop`, metainfo, icons, GTK application-id, and the platform channel names
in `app/linux/runner/`). **Do not** rename the app id to a `dart-pdf.com` form —
that would touch every one of those and re-key the installed app.

### 2. Open the PR

1. Fork `https://github.com/flathub/flathub`.
2. Create a branch named after the app id: base is `new-pr`; push a branch
   `dev.milanko.dartpdf`.
3. At the repo root add the manifest **and** the `desktop-assets/` directory
   (the manifest's `type: file` sources are relative to it). The simplest way:
   `cp -r app/packaging/flatpak/{dev.milanko.dartpdf.yml,desktop-assets} <flathub-clone>/`.
4. Open a PR against the `new-pr` branch of `flathub/flathub`. The Flathub bot
   builds it and a reviewer checks the manifest.
5. Once merged, Flathub creates the per-app repo, the build goes live, and you
   verify the `milanko.dev` domain in the Flathub web UI to get the blue
   verified badge.

See the Flathub docs: <https://docs.flathub.org/docs/for-app-authors/submission>.
