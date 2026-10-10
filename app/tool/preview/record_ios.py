#!/usr/bin/env python3
"""Records the App Store preview tour on an iOS simulator.

    python3 tool/preview/record_ios.py --out build/preview-ios      (from app/)
    python3 tool/preview/compose_preview.py --frames build/preview-ios/frames \\
        --chrome build/preview-ios/chrome.png --log build/preview-ios/tour.log \\
        --out build/preview-ios/preview-iphone.mp4

Boots the simulator (iPhone 17 Pro Max by default, whose screen is 1320x2868),
sets the App Store status bar (9:41, full signal, charged battery), and runs
tool/preview_main.dart with `flutter run` and PREVIEW_CAPTURE on: the tour runs
on frame time and saves every frame it draws as a PNG, so the cut never
depends on a screen recorder keeping up (`simctl io recordVideo` drops frames
whenever a debug build keeps the runner busy). The frames are the app's own
pixels; what the system draws on top - the status bar, the Dynamic Island and
the home indicator - comes from one `simctl io screenshot` (chrome.png) taken
as the tour starts, which the composer lays over every frame.

Writes <out>/frames/NNNNNN.png, <out>/chrome.png and <out>/tour.log (the
tour's markers, each prefixed with the host seconds since launch).
"""
import argparse
import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time

APP = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def simctl(*args, capture=False):
    return subprocess.run(["xcrun", "simctl", *args], check=True,
                          capture_output=capture, text=True).stdout


def find_device(name):
    devices = json.loads(simctl("list", "devices", "available", "-j", capture=True))["devices"]
    runtimes = sorted((r for r in devices if "iOS" in r), reverse=True)
    for want in (lambda d: d["name"] == name, lambda d: "Pro Max" in d["name"]):
        for runtime in runtimes:
            for d in devices[runtime]:
                if want(d):
                    return d["udid"], d["name"]
    sys.exit(f"no available simulator named {name!r} (or any Pro Max)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--device", default=os.environ.get("IOS_DEVICE", "iPhone 17 Pro Max"))
    ap.add_argument("--out", default="build/preview-ios")
    ap.add_argument("--flutter", default=os.environ.get("FLUTTER", "flutter"))
    ap.add_argument("--timeout", type=float, default=2400)
    args = ap.parse_args()

    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    udid, name = find_device(args.device)
    print(f"==> {name} ({udid})")
    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
    simctl("bootstatus", udid, "-b")
    simctl("ui", udid, "appearance", "light")
    simctl("status_bar", udid, "override", "--time", "9:41", "--dataNetwork", "wifi",
           "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active",
           "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100")

    run = subprocess.Popen(
        [*args.flutter.split(), "run", "-d", udid, "-t", "tool/preview_main.dart",
         "--dart-define=PREVIEW_CAPTURE=true"],
        cwd=APP, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1)
    lines = queue.Queue()
    threading.Thread(
        target=lambda: [lines.put((time.monotonic(), l)) for l in run.stdout]
        + [lines.put(None)],
        daemon=True).start()

    t0 = time.monotonic()
    markers = []
    frames_dir = None
    shot = False
    deadline = t0 + args.timeout
    ok = False
    try:
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=1)
            except queue.Empty:
                continue
            if line is None:
                break
            now, line = line[0], line[1].rstrip("\n")
            print(line, flush=True)
            if "@@PREVIEW_FRAMES@@" in line:
                frames_dir = line.split("@@PREVIEW_FRAMES@@", 1)[1].strip()
            elif "@@PREVIEW@@" in line:
                markers.append((now, line))
                if " start " in line and not shot:
                    # The system chrome (status bar, island, home indicator)
                    # for the composer to lay over the app's own frames.
                    simctl("io", udid, "screenshot", os.path.join(out, "chrome.png"))
                    shot = True
                if "@@PREVIEW@@ error" in line:
                    break
            elif "@@PREVIEW_DONE@@" in line:
                ok = shot and frames_dir is not None
                break
    finally:
        with open(os.path.join(out, "tour.log"), "w") as log:
            for now, line in markers:
                log.write(f"{now - t0:.3f} {line}\n")
        try:
            run.stdin.write("q")
            run.stdin.flush()
            run.wait(timeout=30)
        except Exception:
            run.kill()
    if frames_dir and os.path.isdir(frames_dir):
        dest = os.path.join(out, "frames")
        shutil.rmtree(dest, ignore_errors=True)
        shutil.copytree(frames_dir, dest)
        print(f"==> copied {len(os.listdir(dest))} frames to {dest}")
    if not ok:
        sys.exit("the tour did not finish cleanly; see the output above")
    print(f"==> wrote {out}/frames, {out}/chrome.png and {out}/tour.log")


if __name__ == "__main__":
    main()
