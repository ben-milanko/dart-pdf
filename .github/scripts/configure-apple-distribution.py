#!/usr/bin/env python3
"""Select the installed App Store profile without changing app sources."""

import base64
import datetime
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def configure(platform):
    if platform not in ("ios", "macos"):
        raise ValueError("Expected ios or macos")
    variable = (
        "APPLE_PROVISIONING_PROFILE_BASE64"
        if platform == "ios"
        else "APPLE_PROVISIONING_PROFILE_MAC_BASE64"
    )
    raw = base64.b64decode(os.environ[variable], validate=True)
    result = subprocess.run(
        ["security", "cms", "-D"], input=raw, capture_output=True, check=True
    )
    profile = plistlib.loads(result.stdout)
    team = "N5K9GK8B27"
    bundle = "dev.milanko.dartpdf"
    entitlements = profile["Entitlements"]
    app_id = entitlements.get("application-identifier") or entitlements.get(
        "com.apple.application-identifier"
    )
    if profile["TeamIdentifier"] != [team] or app_id != f"{team}.{bundle}":
        raise ValueError("Profile does not match dartPDF's team and bundle")
    if (
        profile.get("ProvisionedDevices")
        or profile.get("ProvisionsAllDevices")
        or entitlements.get("get-task-allow")
        or entitlements.get("com.apple.security.get-task-allow")
    ):
        raise ValueError("Expected an App Store distribution profile")
    if profile["ExpirationDate"] <= datetime.datetime.now(datetime.timezone.utc).replace(
        tzinfo=None
    ):
        raise ValueError("Provisioning profile has expired")
    uuid = profile["UUID"]
    if not re.fullmatch(r"[0-9A-Fa-f-]{36}", uuid):
        raise ValueError("Invalid provisioning profile UUID")
    extension = "mobileprovision" if platform == "ios" else "provisionprofile"
    for directory in (
        Path.home() / "Library/MobileDevice/Provisioning Profiles",
        Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
    ):
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / f"{uuid}.{extension}"
        target.write_bytes(raw)
        target.chmod(0o600)

    config = Path(os.environ["RUNNER_TEMP"]) / f"dartpdf-{platform}-distribution.xcconfig"
    # Leave profile selection empty for plugin/framework targets. A global
    # profile name makes Xcode try to provision those targets as applications.
    config.write_text(
        f"STOREFLIGHT_PROFILE_dev_milanko_dartpdf = {uuid}\n"
        "PROVISIONING_PROFILE_SPECIFIER = $(STOREFLIGHT_PROFILE_$(PRODUCT_BUNDLE_IDENTIFIER:identifier))\n"
        "CODE_SIGN_STYLE = Manual\n"
        "CODE_SIGN_IDENTITY = Apple Distribution\n"
        f"DEVELOPMENT_TEAM = {team}\n"
    )
    config.chmod(0o600)
    with open(os.environ["GITHUB_ENV"], "a") as output:
        output.write(f"XCODE_XCCONFIG_FILE={config}\n")
    print(f"Configured {platform} App Store distribution signing for {bundle}")


if __name__ == "__main__":
    configure(sys.argv[1])
