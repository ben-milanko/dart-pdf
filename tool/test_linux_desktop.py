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
