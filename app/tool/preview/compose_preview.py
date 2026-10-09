#!/usr/bin/env python3
"""Composes an App Store app preview from a screen recording of the tour.

    python3 compose_preview.py --video raw.mov --log tour.log \\
        --device iphone --out build/preview-iphone.mp4

The recording is the real app running tool/preview_main.dart (a screen capture,
as App Review Guideline 2.3.4 requires). `tour.log` is what the recorder saw on
the app's stdout, one line per marker, prefixed with the host clock:

    <seconds since the recording began> @@PREVIEW@@ caption highlight @250

The app's own `@<ms>` clock times the cues against each other; the host time of
the `start` marker anchors that clock in the video.

The output follows Apple's app preview spec: the device's accepted resolution
(iPhone 886x1920, iPad 1200x1600), H.264 High@4.0 at 30 fps and ~11 Mbps, and
stereo 256 kbps AAC at 48 kHz. The capture sits, scaled down but never cropped
or zoomed, under a caption band on the brand gradient used by the store
screenshots. The captions say what the app is doing, since previews autoplay
muted. The audio is the DartPDF sting's music bed
(doc/marketing/motion/soundtrack.py) aligned so its hit lands on the closing
caption, with a sound effect on each touch the tour reports. A poster PNG of the
closing frame is written next to the video.

Requires ffmpeg, numpy and Pillow.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
FONTS = os.path.join(REPO, "packages", "dart_pdf_editor_assets", "assets", "fonts")
SOUNDTRACK = os.path.join(REPO, "doc", "marketing", "motion", "soundtrack.py")

# Apple's accepted app preview resolutions (portrait).
DEVICES = {"iphone": (886, 1920), "ipad": (1200, 1600)}

# Headline + subtitle per chapter, keyed by the tour's caption ids. English;
# the captions carry the story because previews autoplay muted.
CAPTIONS = {
    "highlight": ("Highlight what matters", "Mark up any PDF with a swipe."),
    "fill": ("Fill in forms", "Type straight into the fields."),
    "organize": ("Rearrange pages", "Drag pages into the order you want."),
    "sign": ("Sign with your finger", "Right on the signature line."),
    "done": ("Private by design", "No account, no ads, no uploads."),
}

# The store screenshots' gradient (tool/compose_marketing.dart).
GRADIENT = [(0.0, (0x0A, 0x1B, 0x3D)), (0.5, (0x12, 0x3E, 0x92)), (1.0, (0x1A, 0xA0, 0xE0))]

FPS = 30
CAPTION_FADE = 0.3
CAPTION_RISE = 28  # px a caption rises as it fades in
END_FADE = 0.5

# The sting's music map (dartpdf-sting.html). Its chord hit is at 18.55s on that
# timeline; the preview's closing caption is lined up with it.
STING_MUSIC = {"bpm": 120, "drumsIn": 3.0, "hatsIn": 6.0, "arp": [6.0, 15.0],
               "breakdown": 15.0, "hit": 18.55}

MARKER = re.compile(r"^(?P<host>[0-9.]+) .*@@PREVIEW@@ (?P<body>.*?) @(?P<ms>\d+)\s*$")


def parse_log(path):
    events = []
    for line in open(path, encoding="utf-8", errors="replace"):
        m = MARKER.match(line.strip())
        if not m:
            continue
        words = m["body"].split()
        events.append({"host": float(m["host"]), "t": int(m["ms"]) / 1000,
                       "kind": words[0], "args": words[1:]})
    kinds = [e["kind"] for e in events]
    if "start" not in kinds or "end" not in kinds:
        sys.exit(f"{path}: no complete tour (need start and end markers)")
    if "error" in kinds:
        sys.exit(f"{path}: the tour reported an error: "
                 + " ".join(next(e for e in events if e["kind"] == "error")["args"]))
    return events


# ------------------------------------------------------------------ stills
def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def gradient(w, h):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            u = (x / w + y / h) / 2
            for (a, ca), (b, cb) in zip(GRADIENT, GRADIENT[1:]):
                if a <= u <= b:
                    k = (u - a) / (b - a)
                    px[x, y] = tuple(round(ca[i] + (cb[i] - ca[i]) * k) for i in range(3))
                    break
    return img


def layout(device, capture_size):
    """Canvas size, caption band height, and the screen's box on the canvas."""
    w, h = DEVICES[device]
    band = round(h * (0.17 if device == "iphone" else 0.15))
    margin = round(h * 0.035)
    avail_h = h - band - margin
    cw, ch = capture_size
    sh = avail_h
    sw = round(sh * cw / ch)
    if sw > w - 2 * margin:
        sw = w - 2 * margin
        sh = round(sw * ch / cw)
    sw -= sw % 2
    sh -= sh % 2
    return w, h, band, ((w - sw) // 2, band, sw, sh)


def background(w, h, box, radius):
    bg = gradient(w, h).convert("RGBA")
    x, y, sw, sh = box
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x, y + 10, x + sw, y + sh + 10), radius, fill=(0, 0, 0, 110))
    bg.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
    return bg


def screen_mask(sw, sh, radius):
    # Supersampled so the rounded corners stay smooth.
    k = 4
    m = Image.new("L", (sw * k, sh * k), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, sw * k - 1, sh * k - 1), radius * k, fill=255)
    return m.resize((sw, sh), Image.LANCZOS)


def caption(w, band, head, sub):
    img = Image.new("RGBA", (w, band), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    size = round(w * 0.082)
    hf = font("TeXGyreHeros-Bold.otf", size)
    while d.textlength(head, font=hf) > w * 0.9:
        size -= 2
        hf = font("TeXGyreHeros-Bold.otf", size)
    sf = font("TeXGyreHeros-Regular.otf", round(size * 0.52))
    cy = band * 0.5
    d.text((w / 2, cy), head, font=hf, fill=(255, 255, 255, 255), anchor="ms")
    d.text((w / 2, cy + size * 0.95), sub, font=sf, fill=(255, 255, 255, 214), anchor="ms")
    return img


# ------------------------------------------------------------------ camera
PUNCH_EASE = 0.5  # seconds to ease into or out of a punch-in


def camera_keys(events, duration):
    """Keyframes (t, zoom, cx, cy) from the tour's focus markers.

    `focus cx cy z` eases to a zoom of z on the normalised screen point
    (cx, cy) over PUNCH_EASE; `... now` cuts straight to it; `focus off`
    eases back to the whole screen. Times are on the output clip.
    """
    keys = [(0.0, 1.0, 0.5, 0.5)]
    for e in events:
        if e["kind"] != "focus":
            continue
        t = max(0.0, min(e["t"], duration))
        if e["args"][0] == "off":
            target = (1.0, 0.5, 0.5)
            ease = PUNCH_EASE
        else:
            cx, cy, z = (float(v) for v in e["args"][:3])
            target = (z, cx, cy)
            ease = 0.0 if "now" in e["args"][3:] else PUNCH_EASE
        t = max(t, keys[-1][0])
        if t > keys[-1][0]:
            keys.append((t, *keys[-1][1:]))
        if ease == 0:
            keys.append((t, *target))  # a zero-length segment: a cut
        else:
            keys.append((t + ease, *target))
    return keys


def camera_at(keys, t):
    """(zoom, cx, cy) at time t: smoothstep between the bracketing keys."""
    for (t0, *v0), (t1, *v1) in zip(keys, keys[1:]):
        if t < t1:
            if t1 <= t0:
                return tuple(v1)
            u = (t - t0) / (t1 - t0)
            u = u * u * (3 - 2 * u)
            return tuple(a + (b - a) * u for a, b in zip(v0, v1))
    return tuple(keys[-1][1:])


def render_screen(video, start, length, speed, size, keys, out):
    """Writes the screen track: the capture through the punch-in camera.

    Every frame is cropped at a fractional window around the focus point and
    resized straight to the screen box with Lanczos - sub-pixel smooth, and
    never upscaled (the capture is far larger than the box at these zooms).
    """
    cw, ch = probe_size(video)
    sw, sh = size
    decode = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-ss", f"{start:.3f}", "-t", f"{length:.3f}",
         "-i", video, "-vf", f"setpts=(PTS-STARTPTS)/{speed},fps={FPS}",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        stdout=subprocess.PIPE)
    encode = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", f"{sw}x{sh}", "-r", str(FPS), "-i", "-", "-c:v", "libx264",
         "-preset", "fast", "-crf", "8", "-pix_fmt", "yuv444p", out],
        stdin=subprocess.PIPE)
    frame_bytes = cw * ch * 3
    frames = round(length / speed * FPS)
    n = 0
    last = None
    while n < frames:
        raw = decode.stdout.read(frame_bytes)
        if len(raw) < frame_bytes:
            # A capture that stops early (a screencast only sends changed
            # frames) holds its last frame; the camera keeps moving over it.
            if last is None:
                break
            raw = last
        last = raw
        zoom, cx, cy = camera_at(keys, n / FPS)
        win_w, win_h = cw / zoom, ch / zoom
        x0 = min(max(cx * cw - win_w / 2, 0), cw - win_w)
        y0 = min(max(cy * ch - win_h / 2, 0), ch - win_h)
        frame = Image.frombuffer("RGB", (cw, ch), raw)
        frame = frame.resize((sw, sh), Image.LANCZOS,
                             box=(x0, y0, x0 + win_w, y0 + win_h))
        encode.stdin.write(frame.tobytes())
        n += 1
    encode.stdin.close()
    decode.stdout.close()
    decode.kill()
    decode.wait()
    if encode.wait() or n == 0:
        sys.exit("rendering the screen track failed")
    return n


# ------------------------------------------------------------------ audio
def soundtrack(events, duration, out_wav):
    """Renders the music bed + effects; event times are on the output clip."""
    done = next((e["t"] for e in events
                 if e["kind"] == "caption" and e["args"][:1] == ["done"]), duration - 2.5)
    # Start the sting's bed late enough that its chord hit lands on [done].
    offset = max(0.0, STING_MUSIC["hit"] - done)
    cues = []
    for e in events:
        if e["kind"] != "sfx":
            continue
        cue = {"type": e["args"][0], "t": e["t"] + offset}
        if len(e["args"]) > 1:
            cue["dur"] = float(e["args"][1])
        if cue["type"] == "typing":
            cue["count"] = max(4, round(cue.get("dur", 1) / 0.06))
        cues.append(cue)
    music = dict(STING_MUSIC, end=offset + duration)
    spec = {"duration": duration, "offset": offset, "music": music, "cues": cues}
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(spec, f)
    subprocess.run([sys.executable, SOUNDTRACK, f.name, out_wav], check=True)
    os.unlink(f.name)


# ------------------------------------------------------------------ video
def probe_size(video):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height", "-of", "csv=p=0:s=x", video],
        check=True, capture_output=True, text=True).stdout.strip()
    w, h = out.split("x")[:2]
    return int(w), int(h)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--video", required=True, help="screen recording of the tour")
    ap.add_argument("--log", required=True, help="host-timestamped tour markers")
    ap.add_argument("--device", choices=sorted(DEVICES), default="iphone")
    ap.add_argument("--out", required=True, help="output .mp4")
    ap.add_argument("--speed", type=float, default=1.0,
                    help="playback speed-up, for drafts recorded on slow hosts")
    ap.add_argument("--any-length", action="store_true",
                    help="allow a clip outside Apple's 15-30 s (drafts only)")
    ap.add_argument("--lead", type=float, default=0.0,
                    help="seconds of recording to keep before the start marker")
    args = ap.parse_args()

    events = parse_log(args.log)
    start_ev = next(e for e in events if e["kind"] == "start")
    end_ev = next(e for e in events if e["kind"] == "end")
    # Video time of app-clock time t: the start marker's host time anchors it.
    def vt(t):
        return start_ev["host"] + (t - start_ev["t"])

    clip_in = vt(start_ev["t"]) - args.lead
    clip_out = vt(end_ev["t"])
    speed = args.speed
    duration = (clip_out - clip_in) / speed
    if not 15 <= duration <= 30 and not args.any_length:
        sys.exit(f"{duration:.1f}s is outside Apple's 15-30s app preview length "
                 "(retime the tour, or pass --any-length for a draft)")

    capture = probe_size(args.video)
    w, h, band, box = layout(args.device, capture)
    x, y, sw, sh = box
    radius = round(sw * 0.075)

    out_dir = os.path.dirname(os.path.abspath(args.out))
    os.makedirs(out_dir, exist_ok=True)
    work = tempfile.mkdtemp(prefix="preview-")
    background(w, h, box, radius).save(os.path.join(work, "bg.png"))
    screen_mask(sw, sh, radius).save(os.path.join(work, "mask.png"))

    # Chapters: each caption runs until the next one (or the end).
    chapters = [e for e in events if e["kind"] == "caption"]
    spans = []
    for i, e in enumerate(chapters):
        a = (vt(e["t"]) - clip_in) / speed
        b = ((vt(chapters[i + 1]["t"]) - clip_in) / speed) if i + 1 < len(chapters) else duration
        head, sub = CAPTIONS[e["args"][0]]
        path = os.path.join(work, f"caption{i}.png")
        caption(w, band, head, sub).save(path)
        spans.append((max(0.0, a), b, path))
    # The first caption is up from the first frame: the clip opens mid-action.
    if spans:
        spans[0] = (0.0, spans[0][1], spans[0][2])

    # Sound cues on the output timeline (a sped-up draft scales them with it).
    wav = os.path.join(work, "soundtrack.wav")
    soundtrack([dict(e, t=(vt(e["t"]) - clip_in) / speed) for e in events],
               duration, wav)

    inputs = ["-i", os.path.join(work, "screen.mp4"),
              "-loop", "1", "-framerate", str(FPS), "-t", f"{duration:.3f}", "-i",
              os.path.join(work, "bg.png"),
              "-loop", "1", "-framerate", str(FPS), "-t", f"{duration:.3f}", "-i",
              os.path.join(work, "mask.png")]
    for _, _, path in spans:
        inputs += ["-loop", "1", "-framerate", str(FPS), "-t", f"{duration:.3f}", "-i", path]
    inputs += ["-i", wav]
    audio_index = 3 + len(spans)

    # The camera: the tour's focus markers become eased punch-ins.
    keys = camera_keys([dict(e, t=(vt(e["t"]) - clip_in) / speed) for e in events],
                       duration)
    screen = os.path.join(work, "screen.mp4")
    render_screen(args.video, clip_in, clip_out - clip_in, speed, (sw, sh), keys, screen)

    f = ["[0:v]format=rgba[scr]",
         "[2:v]format=gray[mask]",
         "[scr][mask]alphamerge[screen]",
         "[1:v]format=rgba[bg]",
         f"[bg][screen]overlay={x}:{y}:eof_action=repeat[v0]"]
    last = "v0"
    for i, (a, b, _) in enumerate(spans):
        fade_in = "" if a == 0 else f"fade=t=in:st={a:.3f}:d={CAPTION_FADE}:alpha=1,"
        fade_out = (f"fade=t=out:st={b - CAPTION_FADE:.3f}:d={CAPTION_FADE}:alpha=1"
                    if b < duration else "null")
        f.append(f"[{3 + i}:v]format=rgba,{fade_in}{fade_out}[c{i}]")
        # Each caption rises into place as it fades in.
        u = f"min(max((t-{a:.3f})/{CAPTION_FADE},0),1)"
        rise = "0" if a == 0 else f"{CAPTION_RISE}*(1-{u})*(1-{u})"
        f.append(f"[{last}][c{i}]overlay=x=0:y='{rise}':"
                 f"enable='between(t,{a:.3f},{b:.3f})'[v{i + 1}]")
        last = f"v{i + 1}"
    f.append(f"[{last}]fade=t=out:st={duration - END_FADE:.3f}:d={END_FADE},"
             f"format=yuv420p[out]")

    cmd = ["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", ";".join(f),
           "-map", "[out]", "-map", f"{audio_index}:a", "-t", f"{duration:.3f}",
           "-r", str(FPS), "-c:v", "libx264", "-preset", "slow", "-profile:v", "high",
           "-level:v", "4.0", "-pix_fmt", "yuv420p", "-b:v", "11M", "-maxrate", "12M",
           "-bufsize", "24M", "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
           "-movflags", "+faststart", args.out]
    subprocess.run(cmd, check=True)

    # Poster: the closing frame, just before the fade, with every edit on it.
    poster = os.path.splitext(args.out)[0] + "-poster.png"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-ss", f"{duration - END_FADE - 0.1:.3f}",
                    "-i", args.out, "-frames:v", "1", poster], check=True)
    print(f"wrote {args.out} ({w}x{h}, {duration:.1f}s) and {poster}")
    print(f"poster frame: {duration - END_FADE - 0.1:.2f}s (set it in App Store Connect)")


if __name__ == "__main__":
    main()
