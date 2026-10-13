#!/usr/bin/env python3
"""Stage a Flutter Linux bundle as an AppDir without changing its binaries.

Flutter resources stay beside the runner in usr/bin. Desktop integration belongs
in usr/share, where AppImage tools and catalog workers can find it. The AppImage
copy omits the existing Mac marketing screenshots: catalog-generated
native Linux captures are preferable until genuine Linux assets are available.
The source metainfo and portable tar bundle are not edited.
"""

import argparse
from pathlib import Path
import shutil
import sys
import xml.etree.ElementTree as ET


APP_ID = "dev.milanko.dartpdf"
BINARY = "dart_pdf_editor_app"
APPIMAGE_METAINFO = f"{APP_ID}.appdata.xml"


def stage_appdir(bundle: Path, appdir: Path) -> None:
    bundle = bundle.resolve()
    appdir = appdir.resolve()
    if not bundle.is_dir():
        raise ValueError(f"Missing bundle directory: {bundle}")
    if appdir == bundle or bundle in appdir.parents:
        raise ValueError("AppDir must be outside the source bundle")
    if appdir.exists():
        raise ValueError("AppDir already exists; refusing to overwrite it")

    desktop = bundle / "share/applications" / f"{APP_ID}.desktop"
    metainfo = bundle / "share/metainfo" / f"{APP_ID}.metainfo.xml"
    icon = bundle / "share/icons/hicolor/512x512/apps" / f"{APP_ID}.png"
    for required in [bundle / BINARY, desktop, metainfo, icon]:
        if not required.is_file():
            raise ValueError(f"Missing required bundle file: {required}")
    for directory in [bundle / "data", bundle / "lib"]:
        if not directory.is_dir():
            raise ValueError(f"Missing Flutter resource directory: {directory}")

    # Validate before creating the output. Do not invent an identity or launch
    # target if the bundle's installed metadata describes something else.
    tree = ET.parse(metainfo)
    component = tree.getroot()
    if component.tag != "component" or component.findtext("id") != APP_ID:
        raise ValueError("Unexpected AppStream component identity")
    launchable = component.find("launchable[@type='desktop-id']")
    if launchable is None or launchable.text != f"{APP_ID}.desktop":
        raise ValueError("AppStream desktop launchable does not match the app")

    desktop_lines = desktop.read_text(encoding="utf-8").splitlines()
    if "[Desktop Entry]" not in desktop_lines:
        raise ValueError("Missing desktop entry group")
    for key in ["Exec", "Icon"]:
        if sum(line.startswith(f"{key}=") for line in desktop_lines) != 1:
            raise ValueError(f"Expected exactly one desktop {key} entry")
    portable_desktop = []
    for line in desktop_lines:
        if line.startswith("Exec="):
            line = f"Exec={BINARY} %F"
        elif line.startswith("Icon="):
            line = f"Icon={APP_ID}"
        elif line.startswith("TryExec="):
            # The installed wrapper named dartpdf is not in this container.
            # AppRun locates the bundled runner; a host PATH check can hide it.
            continue
        portable_desktop.append(line)

    binaries = appdir / "usr/bin"
    binaries.mkdir(parents=True)
    for source in bundle.iterdir():
        if source.name == "share":
            continue
        target = binaries / source.name
        if source.is_symlink():
            target.symlink_to(source.readlink())
        elif source.is_dir():
            shutil.copytree(source, target, symlinks=True)
        else:
            shutil.copy2(source, target)
    shutil.copytree(bundle / "share", appdir / "usr/share", symlinks=True)

    # Only generated AppImage metadata changes. Retain the description, license,
    # URLs, version history, categories and launchable from the installed file.
    for screenshots in component.findall("screenshots"):
        for screenshot in screenshots.findall("screenshot"):
            urls = [element.text or "" for element in screenshot
                    if element.tag in {"image", "video"}]
            if any("/app/macos/" in url or
                   url == "https://dart-pdf.com/assets/promo-app.webm"
                   for url in urls):
                screenshots.remove(screenshot)
        remaining = screenshots.findall("screenshot")
        if not remaining:
            component.remove(screenshots)
        elif not any(item.get("type") == "default" for item in remaining):
            remaining[0].set("type", "default")
    # appimagetool 1.9.1 discovers the desktop-ID .appdata.xml spelling only.
    # Ship one standard component file, not aliases an importer may read twice.
    tree.write(appdir / "usr/share/metainfo" / APPIMAGE_METAINFO,
               encoding="utf-8", xml_declaration=True)
    (appdir / "usr/share/metainfo" / metainfo.name).unlink()

    staged_desktop = appdir / "usr/share/applications" / desktop.name
    staged_desktop.write_text("\n".join(portable_desktop) + "\n", encoding="utf-8")
    (appdir / desktop.name).symlink_to(f"usr/share/applications/{desktop.name}")
    (appdir / f"{APP_ID}.png").symlink_to(
        f"usr/share/icons/hicolor/512x512/apps/{APP_ID}.png")
    (appdir / ".DirIcon").symlink_to(f"{APP_ID}.png")
    apprun = appdir / "AppRun"
    apprun.write_text(
        '#!/bin/bash\n'
        'set -euo pipefail\n'
        'HERE="$(dirname "$(readlink -f "$0")")"\n'
        'export LD_LIBRARY_PATH="$HERE/usr/bin/lib:${LD_LIBRARY_PATH:-}"\n'
        'export XDG_DATA_DIRS="$HERE/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"\n'
        f'exec "$HERE/usr/bin/{BINARY}" "$@"\n', encoding="utf-8")
    apprun.chmod(0o755)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--appdir", required=True, type=Path)
    args = parser.parse_args()
    try:
        stage_appdir(args.bundle, args.appdir)
    except (ValueError, OSError, ET.ParseError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"Staged {APP_ID}: standard desktop metadata; original binaries retained")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
