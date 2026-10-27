"""Portable launcher tests with isolated homes and synthetic executable payloads."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from stage_linux_appdir import stage_appdir

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "app/linux/install-desktop.py"
spec = importlib.util.spec_from_file_location("installer", SCRIPT)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class DesktopTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / "portable space"
        self.bundle.mkdir()
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = patch.dict(os.environ, {"HOME": str(self.home),
            "XDG_DATA_HOME": str(self.home / "custom data"), "APPIMAGE": ""})
        self.env.start()
        self.addCleanup(self.env.stop)
        share = self.bundle / "share"
        (share / "applications").mkdir(parents=True)
        shutil.copy(ROOT / "app/linux/dev.milanko.dartpdf.desktop", share / "applications")
        (share / "metainfo").mkdir()
        shutil.copy(ROOT / "app/linux/dev.milanko.dartpdf.metainfo.xml", share / "metainfo")
        shutil.copytree(ROOT / "app/linux/icons", share / "icons")
        for directory in ("lib", "data"):
            (self.bundle / directory).mkdir()
        self.runner = self.bundle / "dart_pdf_editor_app"
        self.runner.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$HOME/args"\n')
        self.runner.chmod(0o755)
        shutil.copy(SCRIPT, self.bundle)

    def test_register_idempotent_and_preserve_package_launcher(self):
        home = installer.data_home()
        packaged = home / "applications/dev.milanko.dartpdf.desktop"
        packaged.parent.mkdir(parents=True)
        packaged.write_text("package manager entry")
        target = installer.install(self.bundle)
        before = target.read_bytes()
        self.assertEqual(installer.install(self.bundle).read_bytes(), before)
        text = before.decode()
        self.assertIn('Exec="' + str(self.runner) + '" %U', text)
        self.assertNotIn("TryExec=", text)
        self.assertIn("Keywords=PDF;editor;", text)
        self.assertIn("Comment[de]=", text)
        self.assertEqual(packaged.read_text(), "package manager entry")
        icon = home / "icons/hicolor/512x512/apps/dev.milanko.dartpdf.portable.png"
        self.assertTrue(icon.is_file())
        subprocess.run(["python3", str(self.bundle / SCRIPT.name), "--uninstall"], check=True)
        self.assertFalse(target.exists())
        self.assertFalse(icon.exists())
        self.assertTrue(self.runner.exists())
        self.assertEqual(packaged.read_text(), "package manager entry")

    def test_status_missing_present_stale_and_missing_icon(self):
        self.assertEqual(installer.registration_status(self.bundle), "missing")
        target = installer.install(self.bundle)
        self.assertEqual(installer.registration_status(self.bundle), "registered")
        target.write_text(target.read_text().replace(str(self.runner), "/missing/dartpdf"))
        self.assertEqual(installer.registration_status(self.bundle), "missing")
        installer.install(self.bundle)
        (installer.data_home() / "icons/hicolor/512x512/apps/dev.milanko.dartpdf.portable.png").unlink()
        self.assertEqual(installer.registration_status(self.bundle), "missing")

    def test_status_unsupported_sandbox_and_incomplete_bundle(self):
        with patch.dict(os.environ, {"SNAP": "/snap/dartpdf/current"}):
            self.assertEqual(installer.registration_status(self.bundle), "unsupported")
        with patch.dict(os.environ, {"FLATPAK_ID": "dev.milanko.dartpdf"}):
            self.assertEqual(installer.registration_status(self.bundle), "unsupported")
        self.runner.unlink()
        self.assertEqual(installer.registration_status(self.bundle), "unsupported")

    def test_damaged_owned_entries_offer_repair(self):
        target = installer.install(self.bundle)
        valid = target.read_text()
        for broken in [valid.replace("[Desktop Entry]", "[Wrong]"),
                       valid.replace("Type=Application", "Type=Link"),
                       valid + "TryExec=/missing/binary\n",
                       valid + "Hidden=true\n"]:
            target.write_text(broken)
            self.assertEqual(installer.registration_status(self.bundle), "missing")
        target.write_bytes(b"\xff")
        self.assertEqual(installer.registration_status(self.bundle), "missing")

    def test_appimage_status_tracks_outer_image(self):
        appdir = self.root / "mount"
        stage_appdir(self.bundle, appdir)
        image = self.root / "app.AppImage"
        image.write_text("#!/bin/sh\n")
        image.chmod(0o755)
        bundle = appdir / "usr/bin"
        self.assertEqual(installer.registration_status(bundle, str(image)), "missing")
        installer.install(bundle, str(image))
        self.assertEqual(installer.registration_status(bundle, str(image)), "registered")
        moved = self.root / "moved.AppImage"
        image.rename(moved)
        self.assertEqual(installer.registration_status(bundle, str(moved)), "missing")

    def test_third_party_entry_targets_this_exact_executable(self):
        from types import SimpleNamespace
        from unittest.mock import Mock
        entry = Mock()
        entry.get_id.return_value = "third-party.desktop"
        entry.should_show.return_value = True
        entry.get_executable.return_value = str(self.runner)
        gio = SimpleNamespace(AppInfo=SimpleNamespace(get_all=lambda: [entry]))
        with patch.dict("sys.modules", {"gi.repository": SimpleNamespace(Gio=gio)}):
            self.assertEqual(installer.registration_status(self.bundle), "registered")
            entry.get_executable.return_value = "/other/dart_pdf_editor_app"
            self.assertEqual(installer.registration_status(self.bundle), "missing")
        with patch.dict("sys.modules", {"gi": None, "gi.repository": None}):
            self.assertEqual(installer.registration_status(self.bundle), "missing")

    def test_opt_is_not_treated_as_package_managed(self):
        # No writes under /opt: only the path/metadata checks are mocked.
        with patch.object(Path, "resolve", lambda path: path), \
             patch.object(Path, "is_file", return_value=True), \
             patch.object(Path, "exists", return_value=False), \
             patch("os.access", return_value=True), \
             patch.dict("sys.modules", {"gi": None, "gi.repository": None}):
            self.assertEqual(installer.registration_status(Path("/opt/DartPDF")), "missing")

    def test_status_cli_is_read_only(self):
        import json
        result = subprocess.run(["python3", str(self.bundle / SCRIPT.name), "--status"],
                                capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), {"status": "missing"})
        self.assertFalse(installer.data_home().exists())

    def test_relative_xdg_ignored(self):
        os.environ["XDG_DATA_HOME"] = "relative"
        self.assertEqual(installer.data_home(), self.home / ".local/share")

    def test_percent_path_rejected_before_writing(self):
        moved = self.root / "percent%F"
        self.bundle.rename(moved)
        with self.assertRaisesRegex(ValueError, "percent"):
            installer.install(moved)
        self.assertFalse(installer.data_home().exists())

    def test_missing_payload_fails_before_registration(self):
        self.runner.unlink()
        with self.assertRaises(ValueError):
            installer.install(self.bundle)
        self.assertFalse(installer.data_home().exists())

    def test_appimage_registration_keeps_outer_image_path(self):
        appdir = self.root / "mounted image"
        # Recovery packaging also supports older tarballs lacking the helper.
        (self.bundle / SCRIPT.name).unlink()
        stage_appdir(self.bundle, appdir)
        image = self.root / "Dart PDF.AppImage"
        image.write_text("#!/bin/sh\nexit 0\n")
        image.chmod(0o755)
        env = dict(os.environ, APPIMAGE=str(image))
        subprocess.run([str(appdir / "AppRun"), "--install-desktop"], env=env, check=True)
        target = installer.data_home() / "applications/dev.milanko.dartpdf.portable.desktop"
        text = target.read_text()
        self.assertIn('Exec="' + str(image) + '" %U', text)
        self.assertNotIn(str(appdir), text)
        subprocess.run([str(appdir / "AppRun"), "--uninstall-desktop"], env=env, check=True)
        self.assertFalse(target.exists())
        # Ordinary launch remains portable and never registers automatically.
        subprocess.run([str(appdir / "AppRun"), "two words.pdf", "--combine"], env=env, check=True)
        self.assertEqual((self.home / "args").read_text(), "two words.pdf\n--combine\n")
        self.assertFalse(target.exists())

    @unittest.skipUnless(shutil.which("desktop-file-validate"), "desktop-file-utils unavailable")
    def test_desktop_validator(self):
        subprocess.run(["desktop-file-validate", str(installer.install(self.bundle))], check=True)

    @unittest.skipUnless(Path("/usr/bin/python3").exists(), "system Python unavailable")
    def test_glib_launch_handles_metacharacters_and_file_arguments(self):
        # Real GLib parses the desktop entry, rather than a test reimplementing it.
        probe = subprocess.run(["/usr/bin/python3", "-c", "from gi.repository import Gio"], capture_output=True)
        if probe.returncode:
            self.skipTest("GObject introspection unavailable")
        moved = self.root / ('spaces $cash ' + chr(96) + 'quote" slash\\ unicode-é')
        self.bundle.rename(moved)
        self.bundle = moved
        target = installer.install(self.bundle)
        code = """from gi.repository import Gio
import sys
app = Gio.DesktopAppInfo.new_from_filename(sys.argv[1])
assert app is not None
assert app.should_show()
app.launch([Gio.File.new_for_path(sys.argv[2])], None)
"""
        filename = str(self.root / "two words.pdf")
        subprocess.run(["/usr/bin/python3", "-c", code, str(target), filename], check=True)
        import time
        for _ in range(100):
            if (self.home / "args").exists():
                break
            time.sleep(.01)
        self.assertEqual((self.home / "args").read_text(), filename + "\n")


if __name__ == "__main__":
    unittest.main()
