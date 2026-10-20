#!/usr/bin/env python3
"""Regenerate the Android adaptive launcher icon from the app icon master.

Legacy launcher icons are a full-bleed blue square; on Android 8+ the launcher
masks that square into a circle/squircle and clips the blue corners, so the
mark reads as "cropped in". An adaptive icon fixes this by splitting the mark
into two 108dp layers the launcher composes under its own mask:

    background : the brand blue gradient, full-bleed (becomes the whole circle)
    foreground : just the white document sheet, sized into the 66dp safe zone

The document is lifted out of the master by flood-filling the connected blue
background to transparent (the signature squiggle survives because the white
sheet encloses it). Requires Pillow. Run from anywhere:

    python3 app/tool/gen_android_adaptive_icon.py

Outputs (overwritten in place, under app/android/app/src/main/res/):
    mipmap-<dpi>/ic_launcher_foreground.png
    mipmap-<dpi>/ic_launcher_background.png
    mipmap-<dpi>/ic_launcher.png              (legacy square, pre-API-26)
    mipmap-anydpi-v26/ic_launcher.xml         (+ ic_launcher_round.xml)
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)  # app/
MASTER = os.path.join(
    APP, "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png")
RES = os.path.join(APP, "android/app/src/main/res")

# Brand gradient endpoints, sampled from the master along the TL->BR diagonal.
GRAD_TL = (19, 173, 242)
GRAD_BR = (4, 118, 191)

# Adaptive-icon layers are 108dp squares; the guaranteed-visible safe zone is
# the central 66dp. mdpi = 108px, everything else scales from there.
DENSITIES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}
# Legacy square icon sizes (what the launcher masks on API < 26).
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

# Fraction of the 108dp tile the document should span (keeps it in the 66dp
# safe zone with a little breathing room).
FG_SPAN = 0.60


def gradient_background(size):
    """Full-bleed diagonal brand gradient as an RGBA image."""
    im = Image.new("RGBA", (size, size))
    px = im.load()
    denom = 2 * (size - 1)
    for y in range(size):
        for x in range(size):
            t = (x + y) / denom  # 0 at top-left, 1 at bottom-right
            px[x, y] = (
                round(GRAD_TL[0] + (GRAD_BR[0] - GRAD_TL[0]) * t),
                round(GRAD_TL[1] + (GRAD_BR[1] - GRAD_TL[1]) * t),
                round(GRAD_TL[2] + (GRAD_BR[2] - GRAD_TL[2]) * t),
                255,
            )
    return im


def extract_document(master):
    """Lift the white document sheet out of the blue master, transparent bg."""
    im = master.convert("RGBA")
    w, h = im.size
    # Flood-fill the connected blue background to transparent from several
    # seeds so the whole gradient clears despite its spread. The squiggle is
    # walled off by the white sheet, so it is never reached.
    seeds = [(w // 2, 12), (w // 2, h - 12), (12, h // 2), (w - 12, h // 2),
             (w // 2, h // 2 - int(h * 0.34)), (w // 2, h // 2 + int(h * 0.34))]
    for seed in seeds:
        ImageDraw.floodfill(im, seed, (0, 0, 0, 0), thresh=70)
    # Keep only the connected document component (the centered sheet), dropping
    # anti-aliased blue crumbs the fills left along the old rounded corners.
    binary = im.getchannel("A").point(lambda v: 255 if v > 0 else 0)
    sel = binary.copy()
    ImageDraw.floodfill(sel, (im.width // 2, im.height // 2), 128, thresh=0)
    keep = sel.point(lambda v: 255 if v == 128 else 0)
    im.putalpha(keep)
    return im.crop(keep.getbbox())


def foreground_layer(doc, size):
    """Center the document glyph inside a transparent 108dp-equivalent tile."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    target = size * FG_SPAN
    scale = min(target / doc.width, target / doc.height)
    glyph = doc.resize((max(1, round(doc.width * scale)),
                        max(1, round(doc.height * scale))), Image.LANCZOS)
    layer.alpha_composite(glyph, ((size - glyph.width) // 2,
                                  (size - glyph.height) // 2))
    return layer


def legacy_icon(background, doc, size):
    """Rounded-square legacy icon (blue gradient + centered document)."""
    bg = background.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=round(size * 0.22), fill=255)
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.paste(bg, (0, 0), mask)
    target = size * 0.66
    scale = min(target / doc.width, target / doc.height)
    glyph = doc.resize((max(1, round(doc.width * scale)),
                        max(1, round(doc.height * scale))), Image.LANCZOS)
    icon.alpha_composite(glyph, ((size - glyph.width) // 2,
                                 (size - glyph.height) // 2))
    return icon


ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""


def main():
    master = Image.open(MASTER).convert("RGBA")
    background = gradient_background(432)
    doc = extract_document(master)

    for dpi, size in DENSITIES.items():
        d = os.path.join(RES, f"mipmap-{dpi}")
        os.makedirs(d, exist_ok=True)
        background.resize((size, size), Image.LANCZOS).save(
            os.path.join(d, "ic_launcher_background.png"))
        foreground_layer(doc, size).save(
            os.path.join(d, "ic_launcher_foreground.png"))
        legacy_icon(background, doc, LEGACY[dpi]).save(
            os.path.join(d, "ic_launcher.png"))

    anydpi = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(os.path.join(anydpi, name), "w") as f:
            f.write(ADAPTIVE_XML)
    print("wrote adaptive icon layers, legacy icons, and anydpi-v26 XML")


if __name__ == "__main__":
    main()
