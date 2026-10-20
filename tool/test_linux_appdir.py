"""Host-portable regression tests for AppImage staging, not a GUI substitute."""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

from stage_linux_appdir import APP_ID, APPIMAGE_METAINFO, BINARY, stage_appdir


class AppDirTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dartpdf-appdir-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / "bundle"
        self.appdir = self.root / "DartPDF.AppDir"
        for directory in ["data", "lib", "share/applications", "share/metainfo",
                          "share/icons/hicolor/512x512/apps"]:
            (self.bundle / directory).mkdir(parents=True, exist_ok=True)
        (self.bundle / BINARY).write_text('#!/bin/bash\nprintf "%s\\n" "$@"\n')
        (self.bundle / BINARY).chmod(0o755)
        (self.bundle / "dartpdf-cli").write_bytes(b"original cli")
        (self.bundle / "lib/plugin.so").write_bytes(b"original plugin")
        (self.bundle / "lib/alias.so").symlink_to("plugin.so")
        (self.bundle / "data/icudtl.dat").write_bytes(b"original flutter resource")
        self.desktop = self.bundle / "share/applications" / f"{APP_ID}.desktop"
        self.desktop.write_text(
            '[Desktop Entry]\nType=Application\nName=DartPDF\n'
            'Name[de]=DartPDF\nExec=dartpdf %U\nTryExec=dartpdf\n'
            f'Icon={APP_ID}\nCategories=Office;Viewer;Graphics;\n'
            'MimeType=application/pdf;\n', encoding="utf-8")
        self.metainfo = self.bundle / "share/metainfo" / f"{APP_ID}.metainfo.xml"
        self.metainfo.write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<component type="desktop-application">'
            f'<id>{APP_ID}</id><name>DartPDF</name>'
            '<metadata_license>CC0-1.0</metadata_license>'
            '<project_license>Apache-2.0</project_license>'
            f'<launchable type="desktop-id">{APP_ID}.desktop</launchable>'
            '<description><p>Fill and sign PDFs.</p></description>'
            '<url type="homepage">https://dart-pdf.com</url>'
            '<screenshots><screenshot type="default"><image>'
            'https://example.invalid/doc/marketing/app/macos/02-editor.png'
            '</image></screenshot></screenshots>'
            '<releases><release version="8.0.0" date="2026-10-09"/></releases>'
            '</component>', encoding="utf-8")
        self.icon = self.bundle / "share/icons/hicolor/512x512/apps" / f"{APP_ID}.png"
        self.icon.write_bytes(b"unchanged icon bytes")

    def test_standard_share_layout_and_single_root_desktop(self):
        stage_appdir(self.bundle, self.appdir)
        self.assertFalse((self.appdir / "usr/bin/share").exists())
        self.assertTrue((self.appdir / "usr/share/metainfo" / APPIMAGE_METAINFO).is_file())
        self.assertEqual([p.name for p in self.appdir.glob("*.desktop")], [self.desktop.name])
        self.assertTrue((self.appdir / self.desktop.name).is_symlink())

    def test_binary_resources_cli_and_symlinks_preserved(self):
        stage_appdir(self.bundle, self.appdir)
        for name in [BINARY, "dartpdf-cli", "lib/plugin.so", "data/icudtl.dat"]:
            self.assertEqual((self.bundle / name).read_bytes(),
                             (self.appdir / "usr/bin" / name).read_bytes())
        self.assertEqual((self.appdir / "usr/bin/lib/alias.so").readlink(), Path("plugin.so"))
        self.assertTrue(os.access(self.appdir / "usr/bin" / BINARY, os.X_OK))

    def test_portable_desktop_preserves_localization_categories_and_mime(self):
        stage_appdir(self.bundle, self.appdir)
        text = (self.appdir / self.desktop.name).read_text(encoding="utf-8")
        self.assertIn(f"Exec={BINARY} %F\n", text)
        self.assertNotIn("TryExec=", text)
        for line in ["Name[de]=DartPDF", "Categories=Office;Viewer;Graphics;",
                     "MimeType=application/pdf;", f"Icon={APP_ID}"]:
            self.assertIn(line, text)

    def test_source_metadata_unchanged_and_appimage_retains_nonmedia_content(self):
        before = self.metainfo.read_bytes()
        stage_appdir(self.bundle, self.appdir)
        self.assertEqual(self.metainfo.read_bytes(), before)
        original = ET.fromstring(before)
        original.remove(original.find("screenshots"))
        staged = ET.parse(self.appdir / "usr/share/metainfo" / APPIMAGE_METAINFO).getroot()
        self.assertEqual(ET.tostring(original), ET.tostring(staged))
        self.assertIsNone(staged.find("screenshots"))

    def test_icon_links_resolve_to_original_bytes(self):
        stage_appdir(self.bundle, self.appdir)
        self.assertEqual((self.appdir / ".DirIcon").read_bytes(), self.icon.read_bytes())
        self.assertEqual((self.appdir / f"{APP_ID}.png").read_bytes(), self.icon.read_bytes())

    def test_packager_spelling_has_only_one_component_file(self):
        stage_appdir(self.bundle, self.appdir)
        files = list((self.appdir / "usr/share/metainfo").iterdir())
        self.assertEqual([p.name for p in files], [APPIMAGE_METAINFO])
        self.assertTrue(self.metainfo.is_file())

    def test_native_linux_media_retained_and_default_reassigned(self):
        original = ET.parse(self.metainfo)
        screenshots = original.getroot().find("screenshots")
        linux = ET.SubElement(screenshots, "screenshot")
        ET.SubElement(linux, "image").text = "https://example.invalid/app/linux/editor.png"
        original.write(self.metainfo)
        stage_appdir(self.bundle, self.appdir)
        staged = ET.parse(self.appdir / "usr/share/metainfo" / APPIMAGE_METAINFO).getroot()
        remaining = staged.findall("screenshots/screenshot")
        self.assertEqual(len(remaining), 1)
        self.assertEqual(remaining[0].get("type"), "default")
        self.assertEqual(remaining[0].findtext("image"), linux.findtext("image"))

    def test_existing_unverified_promo_video_omitted_only_from_appimage(self):
        original = ET.parse(self.metainfo)
        screenshots = original.getroot().find("screenshots")
        video = ET.SubElement(screenshots, "screenshot")
        ET.SubElement(video, "video").text = "https://dart-pdf.com/assets/promo-app.webm"
        original.write(self.metainfo)
        before = self.metainfo.read_bytes()
        stage_appdir(self.bundle, self.appdir)
        staged = ET.parse(self.appdir / "usr/share/metainfo" / APPIMAGE_METAINFO).getroot()
        self.assertIsNone(staged.find("screenshots"))
        self.assertEqual(before, self.metainfo.read_bytes())

    def test_apprun_makes_standard_share_directory_visible(self):
        (self.bundle / BINARY).write_text('#!/bin/bash\nprintf "%s" "$XDG_DATA_DIRS"\n')
        stage_appdir(self.bundle, self.appdir)
        result = subprocess.run([str(self.appdir / "AppRun")],
                                env={**os.environ, "XDG_DATA_DIRS": "/existing/share"},
                                capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout, f"{self.appdir.resolve()}/usr/share:/existing/share")

    def test_invalid_xml_creates_no_output(self):
        self.metainfo.write_text("<component>")
        with self.assertRaises(ET.ParseError):
            stage_appdir(self.bundle, self.appdir)
        self.assertFalse(self.appdir.exists())

    def test_apprun_forwards_space_containing_filenames(self):
        stage_appdir(self.bundle, self.appdir)
        result = subprocess.run([str(self.appdir / "AppRun"), "a PDF.pdf", "second.pdf"],
                                capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout, "a PDF.pdf\nsecond.pdf\n")

    def test_refuses_existing_output_without_overwriting(self):
        self.appdir.mkdir()
        sentinel = self.appdir / "user-file"
        sentinel.write_text("keep")
        with self.assertRaisesRegex(ValueError, "already exists"):
            stage_appdir(self.bundle, self.appdir)
        self.assertEqual(sentinel.read_text(), "keep")

    def test_refuses_output_nested_in_bundle(self):
        with self.assertRaisesRegex(ValueError, "outside"):
            stage_appdir(self.bundle, self.bundle / "nested.AppDir")

    def test_missing_required_input_creates_no_output(self):
        self.icon.unlink()
        with self.assertRaisesRegex(ValueError, "Missing required"):
            stage_appdir(self.bundle, self.appdir)
        self.assertFalse(self.appdir.exists())

    def test_rejects_wrong_component_before_output(self):
        self.metainfo.write_text(self.metainfo.read_text().replace(f"<id>{APP_ID}</id>", "<id>wrong</id>"))
        with self.assertRaisesRegex(ValueError, "identity"):
            stage_appdir(self.bundle, self.appdir)
        self.assertFalse(self.appdir.exists())

    def test_rejects_wrong_launchable_before_output(self):
        self.metainfo.write_text(self.metainfo.read_text().replace(f">{APP_ID}.desktop<", ">wrong.desktop<"))
        with self.assertRaisesRegex(ValueError, "launchable"):
            stage_appdir(self.bundle, self.appdir)
        self.assertFalse(self.appdir.exists())

    def test_rejects_duplicate_exec_before_output(self):
        self.desktop.write_text(self.desktop.read_text() + "Exec=unexpected\n")
        with self.assertRaisesRegex(ValueError, "exactly one"):
            stage_appdir(self.bundle, self.appdir)
        self.assertFalse(self.appdir.exists())


if __name__ == "__main__":
    unittest.main()
