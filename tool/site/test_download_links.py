"""Keep installation paths available when a release omits optional binaries."""

from html.parser import HTMLParser
import json
from pathlib import Path
import unittest


SITE = Path(__file__).resolve().parents[2] / "site"
MISSING_ASSETS = (
    "dartpdf-macos.dmg",
    "dartpdf-windows-installer.exe",
    "dartpdf-windows-portable.exe",
)


class Links(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.anchors = []
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.anchors.append(dict(attrs))


class DownloadLinksTest(unittest.TestCase):
    def setUp(self):
        self.source = (SITE / "index.html").read_text(encoding="utf-8")
        self.anchors = Links(self.source).anchors

    def test_unavailable_latest_release_assets_are_not_promised(self):
        # app-v8.0.0 does not publish these optional direct builds. Restore a
        # direct path only with a verified artifact and update this contract.
        for asset in MISSING_ASSETS:
            with self.subTest(asset=asset):
                self.assertNotIn("/releases/latest/download/" + asset, self.source)

    def test_each_native_platform_keeps_its_store_path_without_javascript(self):
        expected = {
            "ios": "https://apps.apple.com/app/dartpdf/id6780083686",
            "macos": "https://apps.apple.com/app/dartpdf/id6780083686?platform=mac",
            "android": "https://play.google.com/store/apps/details?id=dev.milanko.dartpdf",
            "windows": "https://apps.microsoft.com/detail/9n071vsv6rgk",
            "linux": "https://snapcraft.io/dartpdf",
        }
        stores = {a.get("data-platform"): a.get("href") for a in self.anchors
                  if a.get("data-download-kind") == "store"}
        self.assertEqual(stores, expected)

    def test_working_flatpak_and_web_options_remain(self):
        direct = {a.get("data-platform"): a.get("href") for a in self.anchors
                  if a.get("data-download-kind") == "desktop"}
        self.assertEqual(direct, {
            "linux": "https://dartpdf-flatpak.web.app/dartpdf.flatpakref",
            "web": "https://app.dart-pdf.com",
        })

    def test_locale_switching_cannot_restore_unavailable_downloads(self):
        locales = list((SITE / "i18n").glob("*.json"))
        self.assertEqual(len(locales), 20)
        for path in locales:
            text = path.read_text(encoding="utf-8")
            values = json.loads(text)
            with self.subTest(locale=path.stem):
                for key in ("dlMac_meta", "dlWin_meta", "dlWin_portable"):
                    self.assertNotIn(key, values)
                for asset in MISSING_ASSETS:
                    self.assertNotIn("/releases/latest/download/" + asset, text)

    def test_release_catalogue_remains_a_fallback(self):
        self.assertTrue(any(a.get("href") ==
                            "https://github.com/ben-milanko/dart-pdf/releases/latest"
                            for a in self.anchors))


if __name__ == "__main__":
    unittest.main()
