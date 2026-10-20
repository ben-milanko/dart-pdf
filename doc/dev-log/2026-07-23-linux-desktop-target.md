# Linux desktop target: CI, file-open, desktop integration, packaging

Made the Linux desktop build a first-class, CI-verified target with proper
desktop integration and Flathub-ready packaging scaffolding. Touches `app/`
and the two workflows only — no `packages/` changes were needed (the build
compiled clean as-is).

## What landed

### 1. Linux CI job (`.github/workflows/ci.yml`)

New `linux` job on `ubuntu-latest`:

- Installs the desktop build deps (`ninja-build`, `libgtk-3-dev`,
  `libsecret-1-dev` for flutter_secure_storage, `libjsoncpp-dev`) plus the
  validators (`desktop-file-utils`, `appstream`) and `xvfb`. Mirrors the deps
  the `release-app.yml` `linux` job already used.
- `flutter build linux --release` (in `app/`).
- `desktop-file-validate` on the `.desktop` and `appstreamcli validate
  --no-net` on the metainfo — both must pass.
- Asserts the desktop/metainfo/icon files actually landed in the built bundle.
- A headless smoke launch under `xvfb-run` (8s survive-or-fail), marked
  `continue-on-error: true` — a GUI under Xvfb can be flaky in CI, so a launch
  failure warns rather than fails the job. Locally it survived cleanly (only
  benign `libEGL`/`Atk`/`GSettings` warnings under Xvfb).

The build was already green in `release-app.yml`'s `linux` job, so this is
about keeping it green per-PR, not fixing compile errors — there were none.

### 2. File-open in the runner (`app/linux/runner/my_application.cc`)

The stock scaffold dropped command-line file args. Changes:

- Flags `G_APPLICATION_NON_UNIQUE` → **`G_APPLICATION_HANDLES_OPEN`**, and the
  custom `local_command_line` override was replaced by an `open` vfunc.
  Removing that override lets GApplication do the standard single-instance
  routing: a second `dartpdf file.pdf` while running is delivered into the
  already-running primary instance instead of spawning a new process.
- `activate` gained a re-entry guard (`self->window != nullptr` → just
  `gtk_window_present`), so re-activation reuses the one window.
- `open`:
  - **Cold start:** sets the file as the Dart entrypoint argument, then
    activates. This is deliberate — the Dart side already reads Linux/Windows
    cold-start opens from `launchArgs` (`editor_screen.dart` `_openLaunchArgs`,
    and `_hasExplicitLaunchTarget` uses `launchArgs` to let the explicit file
    win over session restore). Keeping cold start on `launchArgs` preserves
    that tested behavior; only warm opens use the channel.
  - **Warm start:** invokes `openFile` on the shared
    `dev.milanko.dartpdf/incoming` channel (the same one macOS/Windows use)
    with a `{name, path}` payload, then presents the window.
- Registered the `dev.milanko.dartpdf/incoming` channel alongside the existing
  `native_print` channel. `getInitialFile` returns null on Linux (cold start
  is handled via `launchArgs`, so returning the file here too would
  double-open).

Verified under Xvfb: `dartpdf <corpus.pdf>` starts and opens the file without
crashing.

### 3. Desktop integration (`app/linux/`)

- `dev.milanko.dartpdf.desktop`: `Exec=dartpdf %U`, `MimeType=application/pdf;`,
  `Categories=Office;Viewer;Graphics;`, `StartupWMClass=dev.milanko.dartpdf`
  (GTK sets the app-id as the WM class for a `GtkApplication`, and it matches
  the `.desktop` basename so GNOME/Wayland associate the window+icon). Localized
  `Comment[..]` lines for all 20 shipped locales, sourced from
  `app/fastlane/metadata/android/*/short_description.txt` (fastlane locale
  codes mapped to POSIX: `de-DE`→`de`, `pt-BR`→`pt_BR`, `zh-CN`→`zh_CN`, …).
  `desktop-file-validate` passes (one non-fatal hint: two main categories).
- `dev.milanko.dartpdf.metainfo.xml`: `desktop-application`, launchable →
  the `.desktop`, OARS content rating, `project_license=Apache-2.0` (matches
  `LICENSE`), developer, URLs (homepage `https://dart-pdf.com`, bugtracker →
  the GitHub repo). Description from `store-listing.md`, neutralized per the
  project rule (no competitor names → "proprietary incumbent's cloud"). One
  `<release>` (2.1.0) generated from `app/release-notes/2.1.0-stores.txt`.
  Screenshots reference the English marketing PNGs under
  `doc/marketing/app/macos/` via `raw.githubusercontent.com/.../main/...`
  URLs — those files are already on `main`, so they're https-reachable.
  `appstreamcli validate --no-net` passes.
- Icons: hicolor PNGs at 64/128/256/512 generated from the 1024px source
  (`app/macos/.../app_icon_1024.png`), installed to
  `share/icons/hicolor/<size>/apps/dev.milanko.dartpdf.png`.
- `app/linux/CMakeLists.txt` install rules put all of the above under the
  bundle's `share/` tree, so the release tarball carries them and packaging
  can relocate them.

### 4. Release artifact (`.github/workflows/release-app.yml`)

The `linux` job's existing tarball step (`tar -C build/linux/x64/release/bundle
.`) now automatically includes the `share/` desktop files — verified by
listing the produced `dartpdf-linux-x64.tar.gz`. Only a clarifying comment was
added; no build change needed. (The AppImage step was left as-is; it builds its
own minimal desktop entry and is out of scope.)

### 5. Flathub scaffolding (`app/packaging/flatpak/`)

- `dev.milanko.dartpdf.yml`: binary manifest, `org.freedesktop.Platform`
  24.08, sourced from the release tarball. Finish-args: `wayland` +
  `fallback-x11`, `ipc`, `dri`, `--talk-name=org.freedesktop.secrets`,
  `--share=network` — **no blanket `--filesystem`**. Files come through the
  portals (Exec `%U` file-forwarding for opens; `file_selector_linux` uses
  `GtkFileChooserNative` → FileChooser portal for dialogs). Exposes the runner
  as `dartpdf` via a `/app/bin` symlink so the `.desktop` `Exec=dartpdf`
  resolves.
- `README.md`: local `flatpak-builder` test steps, how to bump the pinned
  tarball URL+sha per release, and the `flathub/flathub` submission flow
  (fork → `dev.milanko.dartpdf` branch → PR against `new-pr` → domain
  verification). The actual submission is intentionally left to the maintainer
  (separate repo + account).

## Plugin audit (Linux)

All plugins the app depends on have Linux implementations, so nothing had to be
dropped or stubbed:

- `file_selector_linux`, `url_launcher_linux`, `desktop_drop`,
  `flutter_secure_storage_linux`, `share_plus`, `path_provider_linux`,
  `shared_preferences_linux`, `package_info_plus`, and the FFI plugins `jni` +
  `onnxruntime` (OCR) all compiled and linked in the release build.
- **libsecret with no keyring:** `SecureIdentityStore` (flutter_secure_storage)
  needs the Secret Service on D-Bus. If it's absent, the signing dialog's
  `identityStore.ids()`/`load()` calls are wrapped in `try`/`catch`
  (`app/lib/digital_signature.dart`), so it shows an empty identity list and
  surfaces an error when creating/persisting one — no crash.
- **File dialogs are portal-backed** under Flatpak with no code change (see
  above), which is why the manifest needs no filesystem grant.

## Remaining / follow-ups

- **Flathub submission itself** (needs the separate repo + the maintainer's
  account + app-id domain verification via `dart-pdf.com`/`milanko.dev` DNS).
- **Version reconciliation:** `pubspec` is at `3.0.0+20` (unreleased) but the
  newest release notes are `2.1.0`; the metainfo `<release>` and the flatpak
  tarball URL/sha are pinned to `2.1.0`. When 3.0.0 ships, add its `<release>`
  entry and re-pin the tarball.
- **AUR** packaging (not attempted).
- The Xvfb smoke launch is non-blocking; if it proves reliable on CI it could
  be tightened to a hard gate later.
- In-place save of a portal/forwarded file: works in the common case; if a
  case surfaces where the document portal refuses the write, consider a narrow
  `--filesystem=xdg-*` grant (never `host`) — noted in the flatpak README.
