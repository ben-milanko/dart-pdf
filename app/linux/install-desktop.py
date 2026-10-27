#!/usr/bin/env python3
"""Register this portable DartPDF bundle for the current user's desktop.

Run from an extracted tar bundle, or via AppImage --install-desktop.
The application stays where it is; rerun after moving it. No sudo required.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

APP_ID = "dev.milanko.dartpdf"
# A separate ID avoids shadowing a package-manager installation.
DESKTOP_ID = APP_ID + ".portable"


def desktop_string(value):
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")


def exec_argument(value):
    # Exec has two escaping layers: desktop string decoding, then argv parsing.
    value = value.replace("%", "%%")
    for char in ('\\', '"', '$', chr(96)):
        value = value.replace(char, '\\' + char)
    return desktop_string('"' + value + '"')


def data_home():
    value = os.environ.get("XDG_DATA_HOME", "")
    return Path(value) if Path(value).is_absolute() else Path.home() / ".local/share"


def install(bundle, appimage=None):
    bundle = bundle.resolve()
    executable = Path(appimage).absolute() if appimage else bundle / "dart_pdf_editor_app"
    share = bundle.parent / "share" if appimage else bundle / "share"
    template = share / "applications" / (APP_ID + ".desktop")
    icon = share / "icons/hicolor/512x512/apps" / (APP_ID + ".png")
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError("The application must exist and be executable before registration")
    if not template.is_file() or not icon.is_file():
        raise ValueError("Missing desktop metadata or icon; use a complete DartPDF bundle")
    # Reject control characters in executable paths: these cannot be represented
    # portably across desktop launchers. Spaces and shell metacharacters are safe.
    if any(ord(c) < 32 for c in str(executable)) or "%" in str(executable):
        # GLib checks the executable before expanding %% in the command.
        raise ValueError("Move the application to a path without percent signs or control characters")
    home = data_home()
    applications = home / "applications"
    icons = home / "icons/hicolor/512x512/apps"
    applications.mkdir(parents=True, exist_ok=True)
    icons.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(icon, icons / (DESKTOP_ID + ".png"))
    lines = []
    for line in template.read_text(encoding="utf-8").splitlines():
        if line.startswith("Exec="):
            line = "Exec=" + exec_argument(str(executable)) + " %U"
        elif line.startswith("TryExec="):
            continue  # No PATH dependency; Exec is an absolute path.
        elif line.startswith("Icon="):
            line = "Icon=" + DESKTOP_ID
        lines.append(line)
    target = applications / (DESKTOP_ID + ".desktop")
    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    target.chmod(0o644)
    refresh(applications, home / "icons/hicolor")
    return target


def refresh(applications, icons):
    for command, args in [("update-desktop-database", [str(applications)]),
                          ("gtk-update-icon-cache", ["-f", "-t", str(icons)])]:
        if shutil.which(command):
            subprocess.run([command, *args], check=False, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uninstall", action="store_true",
                        help="remove only this user's portable launcher and icon")
    args = parser.parse_args()
    try:
        if args.uninstall:
            home = data_home()
            (home / "applications" / (DESKTOP_ID + ".desktop")).unlink(missing_ok=True)
            (home / "icons/hicolor/512x512/apps" / (DESKTOP_ID + ".png")).unlink(missing_ok=True)
            refresh(home / "applications", home / "icons/hicolor")
            print("Removed the portable DartPDF launcher; application files are unchanged.")
        else:
            target = install(Path(__file__).resolve().parent, os.environ.get("APPIMAGE"))
            print(f"Registered DartPDF: {target}")
            print("Search for DartPDF in Applications. Rerun registration if you move the app.")
    except (OSError, ValueError) as error:
        print(f"Cannot register DartPDF: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
