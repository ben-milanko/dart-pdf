#!/usr/bin/env python3
"""Check ML Kit's reflection entry points in an actual release APK.

Flutter/widget tests and debug APKs cannot catch R8 removing a constructor.
Run after `flutter build apk --release` (also run by release-app.yml):
  python3 tool/check_android_scanner.py app/build/app/outputs/flutter-apk/app-release.apk

Requires apkanalyzer from the Android SDK command-line tools, found on PATH or
under ANDROID_HOME/ANDROID_SDK_ROOT, or supplied with --apkanalyzer.
"""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


ANDROID = "{http://schemas.android.com/apk/res/android}"
DISCOVERY_SERVICE = "com.google.mlkit.common.internal.MlKitComponentDiscoveryService"
COMMON_REGISTRAR = "com.google.mlkit.common.internal.CommonComponentRegistrar"
REGISTRAR_PREFIX = "com.google.firebase.components:"
REGISTRAR_TYPE = "com.google.firebase.components.ComponentRegistrar"


def find_apkanalyzer():
    executable = shutil.which("apkanalyzer")
    if executable:
        return executable
    for variable in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        sdk = os.environ.get(variable)
        if sdk:
            executable = Path(sdk) / "cmdline-tools/latest/bin/apkanalyzer"
            if executable.is_file():
                return str(executable)
    raise RuntimeError("Set ANDROID_HOME or pass --apkanalyzer with its SDK path")


def check_apk(apk, apkanalyzer):
    def analyze(*args):
        return subprocess.run(
            [apkanalyzer, *args, str(apk)], check=True, capture_output=True, text=True
        ).stdout

    manifest = ET.fromstring(analyze("manifest", "print"))
    registrars = set()
    for service in manifest.iter("service"):
        if service.get(ANDROID + "name") != DISCOVERY_SERVICE:
            continue
        for metadata in service.findall("meta-data"):
            name = metadata.get(ANDROID + "name", "")
            if (metadata.get(ANDROID + "value") == REGISTRAR_TYPE
                    and name.startswith(REGISTRAR_PREFIX)):
                registrars.add(name[len(REGISTRAR_PREFIX):])
    if COMMON_REGISTRAR not in registrars:
        raise RuntimeError("ML Kit's common registrar is missing from the APK manifest")

    for registrar in sorted(registrars):
        # Read the un-mapped DEX, not the pre-shrink class files or R8 seeds.
        # Looking up the manifest's name also catches accidental obfuscation.
        code = analyze("dex", "code", "--class", registrar)
        if not re.search(r"^\.method public constructor <init>\(\)V\s*$", code, re.M):
            raise RuntimeError(
                f"{registrar} has no public no-argument constructor in {apk}; "
                "release document scanning will fail during ML Kit initialization"
            )
        print(f"OK: {registrar} has its reflectively invoked constructor")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--apkanalyzer")
    args = parser.parse_args()
    try:
        check_apk(args.apk, args.apkanalyzer or find_apkanalyzer())
    except (OSError, RuntimeError, ET.ParseError, subprocess.CalledProcessError) as error:
        print(f"Android scanner check failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
