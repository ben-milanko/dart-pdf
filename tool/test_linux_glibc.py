"""Host-portable regression tests for the Linux bundle ABI gate."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import check_linux_glibc as gate


def needs(*versions):
    names = "\n".join(f"  0x0010: Name: {v}  Flags: none  Version: 2" for v in versions)
    return ("Version needs section '.gnu.version_r' contains 1 entry:\n"
            "  000000: Version: 1 File: libc.so.6 Cnt: 1\n" + names + "\n")


class VersionTest(unittest.TestCase):
    def test_only_requirements_count_not_defined_or_symbol_table_versions(self):
        output = ("Version symbols section '.gnu.version' contains 2 entries:\n"
                  "  000: 0 (*local*) 2 (GLIBC_2.99)\n"
                  "Version definition section '.gnu.version_d' contains 1 entry:\n"
                  "  0x0010: Name: GLIBC_2.99\n" + needs("GLIBC_2.17", "GLIBC_2.35"))
        self.assertEqual(gate.required_versions(output), {"GLIBC_2.17", "GLIBC_2.35"})

    def test_no_glibc_requirement_is_legitimate(self):
        self.assertEqual(gate.required_versions(needs("GCC_3.0", "GLIBCXX_3.4.30")), set())
        self.assertEqual(gate.required_versions("No version information found in this file."), set())

    def test_unknown_or_private_glibc_requirement_fails_closed(self):
        for value in ("GLIBC_ABI_DT_RELR", "GLIBC_PRIVATE", "GLIBC_2.invalid"):
            with self.subTest(value=value), self.assertRaises(gate.GlibcError):
                gate.required_versions(needs(value))

    def test_empty_or_malformed_output_cannot_pass(self):
        for value in ("", "unexpected", needs(), needs() +
                      "Version definition section '.gnu.version_d' contains 1 entry:\n"):
            with self.subTest(value=value), self.assertRaises(gate.GlibcError):
                gate.required_versions(value)

    def test_numeric_order_not_lexical_order(self):
        self.assertLess(gate.version_number("2.9"), gate.version_number("2.35"))
        self.assertGreater(gate.version_number("2.38"), gate.version_number("2.35"))
        self.assertLess(gate.version_number("2.2.5"), gate.version_number("2.35"))

    def test_invalid_baseline_rejected(self):
        for value in ("", "2", "2.x", "-2.35", "2.35.0x"):
            with self.subTest(value=value), self.assertRaises(gate.GlibcError):
                gate.version_number(value)

    def test_readelf_failure_or_warning_is_not_success(self):
        for code, err in ((1, "invalid ELF"), (0, "readelf: Warning: truncated")):
            with self.subTest(code=code), patch.object(gate.subprocess, "run", return_value=
                    subprocess.CompletedProcess([], code, needs("GLIBC_2.17"), err)):
                with self.assertRaises(gate.GlibcError):
                    gate.inspect_elf(Path("a.so"))

    def test_readelf_uses_stable_locale_and_wide_output(self):
        with patch.object(gate.subprocess, "run", return_value=
                subprocess.CompletedProcess([], 0, needs("GLIBC_2.35"), "")) as run:
            self.assertEqual(gate.inspect_elf(Path("a.so")), {"GLIBC_2.35"})
            self.assertEqual(run.call_args.args[0], ["readelf", "--wide", "--version-info", "a.so"])
            self.assertEqual(run.call_args.kwargs["env"]["LC_ALL"], "C")


class BundleTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def elf(self, name):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"\x7fELF fixture")
        return path

    def test_all_bundled_plugins_checked_not_just_executable(self):
        self.elf("app")
        self.elf("lib/plugin.so")
        with patch.object(gate, "inspect_elf", side_effect=[{"GLIBC_2.17"}, {"GLIBC_2.38"}]):
            with self.assertRaisesRegex(gate.GlibcError, "lib/plugin.so requires GLIBC_2.38"):
                gate.check_bundle(self.root, "2.35")

    def test_old_versions_and_exact_baseline_pass_non_elf_skipped(self):
        self.elf("app")
        self.elf("lib/plugin.so")
        (self.root / "asset").write_bytes(b"not ELF")
        with patch.object(gate, "inspect_elf", side_effect=[{"GLIBC_2.9"}, {"GLIBC_2.35"}]) as inspect:
            results = gate.check_bundle(self.root, "2.35")
        self.assertEqual(len(results), 2)
        self.assertEqual(inspect.call_count, 2)

    def test_empty_bundle_or_invalid_path_fails(self):
        with self.assertRaisesRegex(gate.GlibcError, "no ELF"):
            gate.check_bundle(self.root, "2.35")
        with self.assertRaises(OSError):
            gate.check_bundle(self.root / "missing", "2.35")
        path = self.elf("file")
        with self.assertRaisesRegex(gate.GlibcError, "not a directory"):
            gate.check_bundle(path, "2.35")

    def test_broken_and_external_symlinks_fail(self):
        self.elf("app")
        link = self.root / "lib.so"
        for target in (self.root / "missing", Path("/usr/bin/env")):
            with self.subTest(target=target), patch.object(gate, "inspect_elf", return_value=set()):
                link.symlink_to(target)
                with self.assertRaisesRegex(gate.GlibcError, "symlink"):
                    gate.check_bundle(self.root, "2.35")
                link.unlink()

    def test_in_bundle_library_symlink_is_supported(self):
        path = self.elf("lib.so.1")
        (self.root / "lib.so").symlink_to(path.name)
        with patch.object(gate, "inspect_elf", return_value={"GLIBC_2.35"}):
            self.assertEqual(len(gate.check_bundle(self.root, "2.35")), 2)

    def test_error_reports_exact_file_and_cli_fails(self):
        self.elf("lib/bad.so")
        with patch.object(gate, "inspect_elf", side_effect=gate.GlibcError("malformed")):
            with self.assertRaisesRegex(gate.GlibcError, "lib/bad.so: malformed"):
                gate.check_bundle(self.root, "2.35")
        with patch.object(gate, "check_bundle", side_effect=gate.GlibcError("bad")):
            self.assertEqual(gate.main([str(self.root)]), 1)


if __name__ == "__main__":
    unittest.main()
