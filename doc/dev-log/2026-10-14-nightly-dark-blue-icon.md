# Nightly app icon on dark blue

The nightly desktop build (`.github/workflows/nightly-desktop.yml`) now
carries its own icon: the stable mark with the background gradient swapped
from Dart blue (#16BAFD→#0169B4) to dark blue (#1E4CA8→#0A1C5C), so a
nightly is told apart from a stable install in the Dock/taskbar and on the
in-app menu button.

- `app/tool/gen_nightly_icon.py` writes `app/packaging/nightly/`
  (macOS appiconset PNGs, Windows multi-res `app_icon.ico`, the
  `web/icons/Icon-512.png` Flutter asset the app menu button shows). It
  recolours the committed stable assets in place instead of re-rendering
  doc/logo.svg, so each platform's framing (macOS 824/1024 inset, rounded
  Windows/web mark) is inherited exactly. Pixels outside the page (a
  32-radius rounded rect minus the fold triangle, from logo.svg) are
  decomposed against the old gradient: darker = drop shadow, kept as a
  luminance ratio; lighter = anti-aliased page edge, kept as a white blend.
  Re-run it after any change to the stable icons.
- The workflow copies those files over the stable ones just before
  `flutter build` on both runners. Stable builds and the repo checkout are
  untouched. The installer's uninstall-entry DisplayIcon reads the exe's
  resources, so it follows automatically; the .pdf document icon is unchanged.
