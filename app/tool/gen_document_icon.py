#!/usr/bin/env python3
"""Regenerate the PDF *document* icon for macOS and Windows from the app icon.

The document icon is a white sheet with a folded top-right corner, faint
brand-coloured content lines, and the DartPDF app icon badged in the lower
right. It is what Finder / Explorer draw for a .pdf file when DartPDF is the
default handler (macOS: CFBundleDocumentTypes -> CFBundleTypeIconFile in
macos/Runner/Info.plist; Windows: the DartPDF.pdf ProgID DefaultIcon written
by the NSIS installer in .github/workflows/release-app.yml, resource id 102).

Requires Pillow, and (macOS) `iconutil` + `sips`, and ImageMagick (`magick`)
for the .ico. Run from anywhere:

    python3 app/tool/gen_document_icon.py

Outputs (overwritten in place):
    app/macos/Runner/DocumentIcon.icns
    app/windows/runner/resources/document_icon.ico
"""
import os
import subprocess
import sys
import tempfile
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)  # app/
APP_ICON = os.path.join(
    APP, "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png")
ICNS_OUT = os.path.join(APP, "macos/Runner/DocumentIcon.icns")
ICO_OUT = os.path.join(APP, "windows/runner/resources/document_icon.ico")


def compose(size=1024):
    """Return the master document icon as an RGBA image."""
    s = size
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    left, top, right, bottom = 250, 96, 774, 928
    fold, radius = 150, 46
    white = (255, 255, 255, 255)

    # drop shadow behind the page
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [left, top + 12, right, bottom + 12], radius=radius, fill=(20, 40, 70, 80))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(20)))

    # page body with the folded corner cut away
    page = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    pd = ImageDraw.Draw(page)
    pd.rounded_rectangle([left, top, right, bottom], radius=radius, fill=white)
    pd.polygon([(right - fold, top - 2), (right + 2, top - 2),
                (right + 2, top + fold)], fill=(0, 0, 0, 0))

    # content lines (brand grays + one yellow accent)
    gray, yel = (183, 192, 204, 255), (245, 179, 1, 255)
    lx, lw, bar_h, gap = left + 70, right - left - 140, 34, 66
    y = top + 150
    for color, wfrac in [(gray, 0.62), (yel, 0.86), (gray, 0.5), (gray, 0.78)]:
        pd.rounded_rectangle([lx, y, lx + int(lw * wfrac), y + bar_h],
                             radius=bar_h // 2, fill=color)
        y += gap
    pd.line([(lx, top + 470), (lx + int(lw * 0.5), top + 470)], fill=gray,
            width=bar_h)
    canvas.alpha_composite(page)

    # turned-up folded corner
    fl = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fl)
    fd.polygon([(right - fold, top), (right, top + fold), (right - fold, top + fold)],
               fill=(214, 224, 234, 255))
    fd.line([(right - fold, top), (right, top + fold)], fill=(176, 190, 205, 255),
            width=3)
    canvas.alpha_composite(fl)

    # app-icon logo badge, lower-right
    # Keep the brand mark legible when the document icon is shown as a small
    # Finder/Explorer thumbnail. It deliberately overhangs the page corner.
    bs = 448
    logo = Image.open(APP_ICON).convert("RGBA").resize((bs, bs), Image.LANCZOS)
    bx, by = right - bs + 46, bottom - bs + 46
    bshadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(bshadow).rounded_rectangle(
        [bx + 6, by + 12, bx + bs + 6, by + bs + 12],
        radius=int(bs * 0.22), fill=(10, 30, 60, 95))
    canvas.alpha_composite(bshadow.filter(ImageFilter.GaussianBlur(20)))
    canvas.paste(logo, (bx, by), logo)
    return canvas


def make_icns(master, out):
    specs = [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
             (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
             (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")]
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "DocumentIcon.iconset")
        os.makedirs(iconset)
        for px, name in specs:
            master.resize((px, px), Image.LANCZOS).save(
                os.path.join(iconset, f"icon_{name}.png"))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out], check=True)
    print("wrote", out)


def make_ico(master, out):
    with tempfile.TemporaryDirectory() as tmp:
        png = os.path.join(tmp, "master.png")
        master.save(png)
        subprocess.run(["magick", png, "-define",
                        "icon:auto-resize=256,128,64,48,32,16", out], check=True)
    print("wrote", out)


if __name__ == "__main__":
    master = compose()
    if sys.platform == "darwin":
        make_icns(master, ICNS_OUT)
    else:
        print("skipping .icns (needs macOS iconutil)")
    make_ico(master, ICO_OUT)
