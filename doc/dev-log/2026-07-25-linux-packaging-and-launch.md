# Linux packaging + launch kit (Flathub/AUR, landing page, launch drafts)

Follow-up to the #547 Linux-desktop groundwork. Prepared everything needed to
publish DartPDF on the Linux desktop and run the launch, and fixed a packaging
correctness bug found by inspecting the actual release artifact.

## The bug: no released tarball carries the desktop files

The #547 CMake rules install the `.desktop`/metainfo/icons into the bundle's
`share/` tree so the release tarball is desktop-integration self-contained. But
`app-v3.0.0` was **tagged before #547 merged** (tag commit `fff7272f`, Release
3.0.0, 2026-07-23 09:55 UTC; #547 `36cb1b90` merged 13:04 UTC). Verified against
the published artifact:

```
tar tzf dartpdf-linux-x64.tar.gz  →  ./dart_pdf_editor_app  ./data  ./lib   (no share/)
```

So the original Flatpak manifest (`install ... share/applications/...` from the
tarball) would **fail against every currently-published release**. This is the
kind of thing the headless CI smoke can't catch.

### Fix

Decoupled the desktop files from the tarball so packaging is correct against the
**current** `app-v3.0.0` binary, no new release required:

- **Flatpak** (`app/packaging/flatpak/`): manifest now installs the desktop
  files from `desktop-assets/` (staged next to the manifest — the payload that
  gets committed into the `flathub/flathub` PR), and pins the binary tarball to
  `app-v3.0.0` with its real sha256 (`c626d2cb…447987`). Added `x-checker-data`
  for auto-update PRs. `sync-desktop-assets.sh` regenerates the staged copies
  from the authoritative `app/linux/` (single source of truth preserved).
- **AUR** (`app/packaging/aur/`): `dartpdf-bin` PKGBUILD + `.SRCINFO` fetch the
  binary tarball + the desktop files (pinned to immutable commit
  `01326c2d…`) + LICENSE, install to `/opt/dartpdf` with a `/usr/bin/dartpdf`
  symlink. All eight sha256sums are real/verified.
- Both READMEs document the simplification path: **once a release is cut from
  post-#547 `main`**, its tarball will carry `share/` and the extra desktop
  sources can be dropped. The test matrix has a row to confirm that on the next
  release.

Also added a `3.0.0` `<release>` entry to `app/linux/…metainfo.xml` (was 2.1.0)
so GNOME Software/Discover show current "what's new".

## Other deliverables

- **SEO landing page** `site/pdf-editor-linux.html` (+ sitemap entry): targets
  "PDF editor Linux", matches the site design system, neutral wording (no
  competitor names), SoftwareApplication + FAQ structured data. Install cards:
  AppImage/tarball live now; Flathub/AUR marked "coming soon" with HTML comments
  marking exactly what to flip when they go live.
- **Launch kit** `doc/marketing/linux-launch/`: Show HN, r/linux, and press-pitch
  (Phoronix/OMG!/It's FOSS) drafts, with honesty guardrails and a sequencing
  rule: **do not post until Flathub is live, the landing page is flipped, and
  hardware testing has passed.**
- **Test matrix** `doc/dev-log/2026-07-25-linux-test-matrix.md`: manual pass for
  Wayland/X11, fractional scaling, no-keyring, portal save, single-instance file
  open — each row tied to the specific code path.

## Confirmed (no action needed)

- Marketing screenshots the metainfo references are already on `main`
  (`doc/marketing/app/macos/0{1,2,3}-*.png`), so the raw.githubusercontent URLs
  resolve.
- License is clean FOSS: root + all 8 packages Apache-2.0, nothing copyleft or
  proprietary. `metadata_license=CC0-1.0`, `project_license=Apache-2.0`.

## Still needs the maintainer (accounts/hardware — can't be done from here)

1. **Cut/confirm a release** whose tarball carries `share/` (optional cleanup),
   or proceed with the decoupled manifest against `app-v3.0.0` as-is.
2. **Real-hardware test pass** (the matrix) — Wayland + X11 + fractional +
   no-keyring.
3. **Flathub submission**: fork `flathub/flathub`, copy
   `app/packaging/flatpak/{manifest,desktop-assets}`, PR against `new-pr`, then
   verify the **`milanko.dev`** app-id domain via DNS TXT (keep the app id).
4. **AUR publish**: push `dartpdf-bin` to `ssh://aur@aur.archlinux.org` (needs an
   AUR account + SSH key).
5. **Launch**: flip landing-page cards → Show HN → r/linux → press.
