"""Reject a Linux bundle whose ELF requirements exceed the supported libc.

Run on Linux with GNU readelf (binutils). Only version *needs* count: a library
can define newer symbols without requiring them from the host. Check every ELF,
not just the launcher; Flutter plugins and prebuilt libraries share this floor.
This is an ABI gate, not a substitute for a native GUI smoke test.
"""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


class GlibcError(ValueError):
    """An invalid bundle, unreadable ELF, or unsupported libc requirement."""


def version_number(value):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)+", value):
        raise GlibcError(f"Not a numeric libc version: {value}")
    return tuple(int(part) for part in value.split("."))


def required_versions(output):
    versions = set()
    in_needs = False
    need_names = 0
    saw_section = False
    for line in output.splitlines():
        if re.match(r"^Version (needs|definition|symbols) section ", line):
            if in_needs and not need_names:
                raise GlibcError("Version needs section has no parseable names")
            saw_section = True
            in_needs = line.startswith("Version needs section ")
            need_names = 0
        if in_needs:
            name = re.search(r"\bName:\s+(\S+)", line)
            if name:
                need_names += 1
                if name[1].startswith("GLIBC_"):
                    # Unknown ABI tags (including GLIBC_PRIVATE) must not pass
                    # by being silently omitted from a numeric maximum.
                    version_number(name[1][len("GLIBC_"):])
                    versions.add(name[1])
    if in_needs and not need_names:
        raise GlibcError("Version needs section has no parseable names")
    if not saw_section and "No version information found in this file." not in output:
        raise GlibcError("Unrecognised readelf version-info output")
    return versions


def inspect_elf(path):
    result = subprocess.run(
        ["readelf", "--wide", "--version-info", str(path)],
        check=False, capture_output=True, text=True,
        env={**os.environ, "LC_ALL": "C"},
    )
    if result.returncode or result.stderr.strip():
        raise GlibcError(f"readelf failed for {path}: {result.stderr.strip()}")
    return required_versions(result.stdout)


def check_bundle(root, maximum):
    limit = version_number(maximum)
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise GlibcError(f"Bundle is not a directory: {root}")
    results = []
    for path in sorted(root.rglob("*")):
        # Do not accidentally inspect a host library via a bundle symlink.
        if path.is_symlink() and (not path.exists() or
                                  not path.resolve().is_relative_to(root)):
            raise GlibcError(f"Broken or external bundle symlink: {path}")
        if not path.is_file():
            continue
        with path.open("rb") as source:
            if source.read(4) != b"\x7fELF":
                continue
        try:
            versions = inspect_elf(path)
        except GlibcError as error:
            raise GlibcError(f"{path.relative_to(root)}: {error}") from error
        newest = max(versions, key=lambda v: version_number(v[6:]), default=None)
        if newest and version_number(newest[6:]) > limit:
            raise GlibcError(f"{path.relative_to(root)} requires {newest}; "
                             f"supported maximum is GLIBC_{maximum}")
        results.append((path.relative_to(root), newest))
    if not results:
        raise GlibcError("Bundle contains no ELF files")
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--max-version", default="2.35")
    args = parser.parse_args(argv)
    try:
        results = check_bundle(args.bundle, args.max_version)
    except (GlibcError, OSError) as error:
        print(f"Linux libc check failed: {error}", file=sys.stderr)
        return 1
    for path, version in results:
        print(f"OK {path}: {version or 'no GLIBC requirement'}")
    print(f"Checked {len(results)} ELF files against GLIBC_{args.max_version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
