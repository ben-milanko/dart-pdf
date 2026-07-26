# Linux desktop test matrix (pre-launch)

The Linux target is CI-verified for **build + headless smoke** only
(`.github/workflows/ci.yml` `linux` job: `flutter build linux --release`,
`desktop-file-validate`, `appstreamcli validate`, an 8s `xvfb-run` launch marked
`continue-on-error`). That does **not** exercise a real compositor, scaling, a
keyring, or the portal file paths. This checklist is the manual pass to run on
real hardware/VMs before submitting to Flathub and before the launch posts.

Run each row on **both a Wayland session and an X11 session**. Two boxes cover
most of the field: a **GNOME** machine (Wayland default, Mutter fractional
scaling) and a **KDE Plasma** machine (Wayland + easy X11 toggle). A minimal
`weston` or a no-keyring VM covers the edge rows.

Legend: ☐ todo · ✅ pass · ⚠️ pass-with-note · ❌ fail (file an issue, link here).

## A. Windowing & display

| # | Check | Steps | Expected | Code ref |
|---|---|---|---|---|
| A1 | Wayland launch | Start on a Wayland session | Window opens, no `libEGL`/GL crash, GPU path (`--device=dri`) works | `app/linux/runner/` |
| A2 | X11 fallback | Start on an X11 session (or `GDK_BACKEND=x11`) | Renders identically | manifest `--socket=fallback-x11` |
| A3 | App icon + window class | Check the taskbar/overview | Correct DartPDF icon; window groups under the app | `.desktop` `StartupWMClass=dev.milanko.dartpdf` |
| A4 | 100% scale | Default | Crisp text, correct hit-testing | — |
| A5 | Fractional scaling 125/150/175% | Set per-display scale, relaunch | UI + PDF page scale correctly; annotation/selection hit-testing lands where expected; no blurry raster | renderer DPR path |
| A6 | Runtime scale change | Change scale while running | Reflows without corruption (or documents "restart to apply") | — |
| A7 | Multi-monitor mixed DPI | Move window between a HiDPI and a 1x display | Re-rasterizes sharp on each | image cache / DPR |

## B. File open paths (the runner rewrite in #547)

| # | Check | Steps | Expected | Code ref |
|---|---|---|---|---|
| B1 | Cold start with a file | `dartpdf some.pdf` (nothing running) | Opens that file, wins over session restore | `my_application.cc` `open` cold path → `launchArgs`; `editor_screen.dart` `_openLaunchArgs`, `_hasExplicitLaunchTarget` |
| B2 | Warm open (second invocation) | With app running, `dartpdf other.pdf` | **Same** window opens the file (single instance), no 2nd process | `G_APPLICATION_HANDLES_OPEN`; `dev.milanko.dartpdf/incoming` `openFile` |
| B3 | "Open With" from file manager | Right-click a PDF → Open With → DartPDF | Opens it | `.desktop` `MimeType=application/pdf`, `Exec=dartpdf %U` |
| B4 | Set as default handler | `xdg-mime default dev.milanko.dartpdf.desktop application/pdf`, double-click a PDF | Opens in DartPDF | xdg-mime association |
| B5 | Drag & drop | Drag a PDF onto the window | Opens/imports | `desktop_drop` plugin |
| B6 | activate re-entry | Launch with no file while running | Existing window is presented, not duplicated | `my_application.cc` activate guard (`window != nullptr` → `gtk_window_present`) |

## C. Save & portals (Flatpak-specific, run the Flatpak build)

| # | Check | Steps | Expected | Code ref |
|---|---|---|---|---|
| C1 | Save in place (portal doc) | Open via Open With, edit, Save | Writes back to the original file | FileChooser/document portal |
| C2 | Save As | File → Save As, pick a new path | Writes new file through the portal | `file_selector_linux` → GtkFileChooserNative |
| C3 | Open dialog | In-app Open | Portal file picker, selected file loads | same |
| C4 | In-place save refused? | If C1 ever fails under the sandbox | Note it here; consider a narrow `--filesystem=xdg-*` (never `host`) — see `app/packaging/flatpak/README.md` | — |

## D. Keyring / signing (the graceful-degradation claim)

| # | Check | Steps | Expected | Code ref |
|---|---|---|---|---|
| D1 | With keyring | Normal GNOME/KDE session, create a signing identity | Identity is stored and reloads | `SecureIdentityStore` (flutter_secure_storage_linux → libsecret) |
| D2 | **No keyring** | VM with no Secret Service (mask `gnome-keyring-daemon` / minimal WM), open the signing dialog | Empty identity list, **no crash**; creating one surfaces an error, not a segfault | `app/lib/digital_signature.dart` try/catch around `identityStore.ids()`/`load()` |
| D3 | Keyless sign (network) | Sign with the keyless flow | Fetches Fulcio cert + TSA timestamp over the network; produces a B-T signature | `app/lib/keyless_signing.dart`, `fulcioHttpTransport` |
| D4 | Sign then validate | Sign, reopen, check signature panel | Reports the signature and its level | `PdfSignature.validate()` |

## E. Content features (spot-check on real docs)

| # | Check | Expected |
|---|---|---|
| E1 | Edit on-page text | Word replaced, following text holds position |
| E2 | Fill an AcroForm + save | Values persist on reopen |
| E3 | Redaction | Covered text gone from the file (verify with a byte search on the saved file) |
| E4 | OCR a scan | Model downloads once, text becomes selectable — on device (check no doc upload in the network log) |
| E5 | Export/reorder pages | New file correct |
| E6 | Open a password-protected PDF | Prompts and opens |

## F. Packaging smoke

| # | Check | Steps | Expected |
|---|---|---|---|
| F1 | Flatpak builds | `flatpak-builder --user --install --force-clean build-dir dev.milanko.dartpdf.yml` | Builds from the pinned tarball + staged assets |
| F2 | Flatpak lint | `flatpak-builder-lint manifest dev.milanko.dartpdf.yml` and `... repo build-dir` | No errors (warnings triaged) |
| F3 | Flatpak run | `flatpak run dev.milanko.dartpdf`, and with a file arg | Launches; file opens |
| F4 | AppImage | Download release AppImage, `chmod +x`, run on GNOME **and** a non-GNOME distro | Launches on both |
| F5 | AUR (once published) | `makepkg -si` from `app/packaging/aur/` on Arch | Installs to `/opt/dartpdf`, `dartpdf` on PATH, icon/desktop present |

## Known gaps this pass must confirm or refute

- **The release tarball has no `share/` tree** for `app-v3.0.0` (built before
  #547). Packaging works around it by installing desktop files from staged/repo
  copies. **Confirm the *next* release built from post-#547 `main` puts
  `share/applications`, `share/metainfo`, `share/icons` in the tarball**
  (`tar tzf dartpdf-linux-x64.tar.gz | grep share/`). If it does, the Flatpak
  and AUR desktop-asset sources can be simplified.
- Mobile pan/zoom bug is unrelated (touch), but watch A5/A6 for any analogous
  gesture/scale interaction on touchscreen laptops.

## Result log

Record one line per environment: `<distro> <de> <wayland|x11> <scale> — <passes/fails>`.
File failures as GitHub issues and link them in the relevant row.

### 2026-07-25 — whistler (Ubuntu 24.04.4, x86_64, glibc 2.39), headless over SSH

Ran the headless-capable rows against the **real `app-v3.0.0` release artifacts**
(tarball + AppImage downloaded on the box). This machine has no active graphical
session, so the GUI rows (A/B3–B6/C/D GUI/E) were **not** covered here — they
still need a box with a live Wayland/X11 desktop.

- ✅ **appstreamcli validate** (edited metainfo incl. the new 3.0.0 `<release>`):
  "Validation was successful."
- ✅ **desktop-file-validate**: pass (only the known two-main-categories hint).
- ✅ **Tarball blocker reconfirmed**: `app-v3.0.0` tarball has `dart_pdf_editor_app`,
  `data/`, `lib/` and **0 `share/` entries**. Packaging correctly installs the
  desktop files itself.
- ✅ **Dependency audit (ldd, binary + all bundled .so)**: 0 unresolved with the
  bundled `lib/` on the path. Only unbundled runtime deps are the gtk3 stack +
  libsecret. **`jsoncpp` is NOT a runtime dep** (build-time only) → removed from
  the AUR `depends`. `lib/libdartjni.so` links `libjvm.so` (the `jni` plugin);
  the app runs fine without a JRE — **open item: confirm on-device OCR works
  without Java on Linux** (if not, OCR needs `java-runtime`, and the
  `org.freedesktop.Platform` Flatpak runtime has no JRE → OCR-under-Flatpak
  would need addressing).
- ✅ **Xvfb smoke launch** of the released binary: alive after 8s.
- ✅ **Install-layout launch**: extracted to an `/opt`-style prefix and launched
  through an absolute `/usr/bin`-style **symlink** — the binary resolves `data/`
  via its real (readlink) path. This is the core assumption of both the AUR and
  Flatpak layouts; **confirmed working.**
- ✅ **AppImage** (`--appimage-extract-and-run`): launches.
- ⚠️ **Live view could not be produced on this box.** X11-forwarding to XQuartz
  on the Mac fails (`glx: failed to create drisw screen`, `DRI3 error` — XQuartz
  offers no compatible GLX fbConfig/DRI3, so Flutter gets no GL surface). Under
  local Xvfb + llvmpipe the process runs and the window **maps**, but bare Xvfb
  has no WM so the window stays 10×10 and the frame grab is black; no WM /
  xdotool / Xlib available without `sudo`. Neither is a bug for a normal local
  Linux X11/Wayland desktop (real GPU + DRI3) — it's specific to this headless
  SSH setup. A real visual needs a machine with a live desktop session (e.g.
  alta/hakuba/laax when online) or a local run of the AppImage.
