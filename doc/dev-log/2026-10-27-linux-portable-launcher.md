# Portable Linux launcher registration

Issue #1169 reports terminal-only launch on Ubuntu, without an installation format or app version. Flatpak, Snap and AUR already export desktop integration. Portable bundles carry metadata but do not register it in the desktop session. Copying the tarball desktop file alone also leaves Exec/TryExec pointing at a missing dartpdf wrapper. PR #1059 fixed the AppDir layout and metadata discovery, not host registration.

The opt-in Python helper registers the existing portable executable and a copied icon under the user data directory. AppRun exposes --install-desktop and --uninstall-desktop, retaining the outer APPIMAGE path instead of a temporary mount. Ordinary launch stays unchanged. A separate portable desktop ID avoids overriding package installations. Moving the application requires registering it again; no default PDF association is changed.

The 38 host-portable Linux tests pass, including real GLib DesktopAppInfo visibility and argument forwarding through paths with spaces, quotes, dollar signs, backticks, backslashes and Unicode. GLib checks executable existence before expanding percent escapes, so paths containing percent signs are rejected before registration. Tests use temporary homes and synthetic shell executables. Desktop validation passes with the pre-existing multiple-main-category hint.

Ubuntu shell search and icon presentation still need confirmation in a logged-in desktop session. The reporter installation format remains unknown. No release or package-manager installation was changed.
