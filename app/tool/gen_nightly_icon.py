#!/usr/bin/env python3
"""Regenerate the nightly-channel app icons: the stable mark on dark blue.

The nightly sits beside (or over) a stable install, so its Dock / taskbar /
app-menu icon swaps the bright Dart-blue background gradient (#16BAFD ->
#0169B4, doc/logo.svg) for a dark blue one. Everything on the page - the
sheet, fold, content lines and ink swoosh - is left untouched.

Each stable asset is recoloured in place rather than re-rendered, so the
platform framing (macOS's 80.5% Big Sur inset, the rounded Windows/web mark)
is inherited exactly. Background pixels are decomposed against the old
gradient: darker than it is the page's drop shadow (kept as a brightness
ratio), lighter is an anti-aliased page edge (kept as a blend with white).

.github/workflows/nightly-desktop.yml copies the outputs over the stable
assets before `flutter build`. Requires Pillow. Run from anywhere:

    python3 app/tool/gen_nightly_icon.py

Outputs (overwritten in place), under app/packaging/nightly/:
    macos/AppIcon.appiconset/app_icon_{16..1024}.png
    windows/app_icon.ico
    web/Icon-512.png
"""
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)  # app/
OUT = os.path.join(APP, "packaging/nightly")
APPICONSET = "macos/Runner/Assets.xcassets/AppIcon.appiconset"

OLD_TOP, OLD_BOTTOM = (0x16, 0xBA, 0xFD), (0x01, 0x69, 0xB4)
NEW_TOP, NEW_BOTTOM = (0x1E, 0x4C, 0xA8), (0x0A, 0x1C, 0x5C)

# The page in master (1024) coordinates, from doc/logo.svg: a 32-radius
# rounded rectangle with the folded top-right corner cut away.
PAGE, PAGE_RADIUS = (272, 192, 752, 832), 32
FOLD = [(612, 192), (753, 191), (753, 332)]


def _lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def _lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def recolor(img, scale, offset):
    """Recolour [img], the mark drawn at master*scale + offset."""
    img = img.convert("RGBA")
    w, h = img.size
    page = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(page)
    draw.rounded_rectangle([v * scale + offset for v in PAGE],
                           radius=PAGE_RADIUS * scale, fill=255)
    draw.polygon([(x * scale + offset, y * scale + offset) for x, y in FOLD],
                 fill=0)
    # Shrink by a pixel so the anti-aliased rim goes through the blend below.
    page = page.filter(ImageFilter.MinFilter(3))
    src, mask, out = img.load(), page.load(), img.copy()
    dst = out.load()
    white = (255, 255, 255)
    for y in range(h):
        for x in range(w):
            r, g, b, a = src[x, y]
            if a == 0 or mask[x, y]:
                continue
            mx, my = (x + 0.5 - offset) / scale, (y + 0.5 - offset) / scale
            t = min(max((mx + my) / 2048, 0.0), 1.0)
            old, new = _lerp(OLD_TOP, OLD_BOTTOM, t), _lerp(NEW_TOP, NEW_BOTTOM, t)
            ratio = _lum((r, g, b)) / _lum(old)
            if ratio <= 1:
                c = tuple(v * ratio for v in new)
            else:
                k = min((ratio - 1) * _lum(old) / (255 - _lum(old)), 1.0)
                c = _lerp(new, white, k)
            dst[x, y] = tuple(int(round(min(max(v, 0), 255))) for v in c) + (a,)
    return out


def main():
    # macOS: the rounded mark at 824/1024, centred (100px margin at 1024).
    os.makedirs(os.path.join(OUT, "macos/AppIcon.appiconset"), exist_ok=True)
    for n in (16, 32, 64, 128, 256, 512, 1024):
        name = f"app_icon_{n}.png"
        img = Image.open(os.path.join(APP, APPICONSET, name))
        recolor(img, n * 824 / 1024 / 1024, n * 100 / 1024).save(
            os.path.join(OUT, "macos/AppIcon.appiconset", name))

    # Windows: every frame of the multi-resolution .ico, full-size mark.
    ico = Image.open(os.path.join(APP, "windows/runner/resources/app_icon.ico"))
    sizes = sorted(ico.info["sizes"])
    frames = []
    for size in sizes:
        ico.size = size
        frames.append(recolor(ico, size[0] / 1024, 0))
    os.makedirs(os.path.join(OUT, "windows"), exist_ok=True)
    frames[-1].save(os.path.join(OUT, "windows/app_icon.ico"), sizes=sizes,
                    append_images=frames[:-1])

    # The in-app menu button (web/icons/Icon-512.png is a Flutter asset).
    os.makedirs(os.path.join(OUT, "web"), exist_ok=True)
    img = Image.open(os.path.join(APP, "web/icons/Icon-512.png"))
    recolor(img, 0.5, 0).save(os.path.join(OUT, "web/Icon-512.png"))


if __name__ == "__main__":
    main()
