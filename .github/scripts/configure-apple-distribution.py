#!/usr/bin/env python3
"""Select the installed App Store profile without changing app sources."""

import base64
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile


def configure_macos_export(uuid, team, bundle):
    options = Path(os.environ["RUNNER_TEMP"]) / "dartpdf-macos-export.plist"
    options.write_bytes(
        plistlib.dumps(
            {
                "method": "app-store-connect",
                "destination": "export",
                "teamID": team,
                "signingStyle": "manual",
                "signingCertificate": "Apple Distribution",
                "installerSigningCertificate": "3rd Party Mac Developer Installer",
                "provisioningProfiles": {bundle: uuid},
                "uploadSymbols": True,
            }
        )
    )
    options.chmod(0o600)

    source = Path(os.environ.get("STOREFLIGHT_CONFIG", "storeflight.yaml")).resolve()
    original = source.read_text()
    anchor = "build:\n  provider: flutter\n  options:\n    macos:\n"
    if original.count(anchor) != 1 or "export_options_plist:" in original:
        raise ValueError("Unexpected Storeflight macOS export configuration")
    updated = original.replace(
        anchor,
        anchor + f"      export_options_plist: {json.dumps(str(options))}\n",
        1,
    )
    # Keep relative paths and every release policy unchanged. The supported
    # export-options setting is the only change in this runner-local copy.
    descriptor, name = tempfile.mkstemp(
        prefix=".storeflight-macos-ci-", suffix=".yaml", dir=source.parent
    )
    with os.fdopen(descriptor, "w") as output:
        output.write(updated)
    with open(os.environ["GITHUB_ENV"], "a") as output:
        output.write(f"STOREFLIGHT_CONFIG={name}\n")


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
    if platform == "macos":
        configure_macos_export(uuid, team, bundle)
    print(f"Configured {platform} App Store distribution signing for {bundle}")


if __name__ == "__main__":
    configure(sys.argv[1])
