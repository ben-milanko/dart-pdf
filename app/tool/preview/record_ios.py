#!/usr/bin/env python3
"""Records the App Store preview tour on an iOS simulator.

    python3 tool/preview/record_ios.py --out build/preview-ios      (from app/)
    python3 tool/preview/compose_preview.py --video build/preview-ios/raw.mov \\
        --log build/preview-ios/tour.log --out build/preview-ios/preview-iphone.mp4

Boots the simulator (iPhone 17 Pro Max by default, whose screen records at
1320x2868), sets the App Store status bar (9:41, full signal, charged battery),
and runs tool/preview_main.dart with `flutter run`. When the app prints
@@PREVIEW_READY@@ it starts `simctl io recordVideo`, and from the moment the
recorder reports it has started, every @@PREVIEW@@ marker the tour prints is
written to tour.log prefixed with the seconds since recording began
(simctl announces the start on stdout; the file only appears at the end). At
@@PREVIEW_DONE@@ it stops the recorder (SIGINT, so the file is finalised) and
quits the app.

The simulator only runs debug builds, which stall now and then. That costs
only time: the tour runs on frame time and stamps each frame with its number,
and compose_preview.py places frames by those numbers (the host times in
tour.log are for reading along, not for the cut).
"""
import argparse
import json
import os
import queue
import signal
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
    ap.add_argument("--timeout", type=float, default=900)
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
        [*args.flutter.split(), "run", "-d", udid, "-t", "tool/preview_main.dart"],
        cwd=APP, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1)
    lines = queue.Queue()
    # Stamp each line as it arrives, not when the loop below gets to it.
    threading.Thread(
        target=lambda: [lines.put((time.monotonic(), l)) for l in run.stdout]
        + [lines.put(None)],
        daemon=True).start()

    recorder = None
    t0 = None
    markers = []
    deadline = time.monotonic() + args.timeout
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
            if "@@PREVIEW_READY@@" in line and recorder is None:
                launched = time.monotonic()
                recorder = subprocess.Popen(
                    ["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force",
                     os.path.join(out, "raw.mov")],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                # Time zero is when the recorder reports it has started (on
                # stdout in current Xcodes); keep draining it after that.
                started = threading.Event()

                def drain(r=recorder):
                    for msg in r.stdout:
                        print(f"[simctl] {msg.rstrip()}", flush=True)
                        if "Recording started" in msg:
                            started.set()

                threading.Thread(target=drain, daemon=True).start()
                if started.wait(timeout=30):
                    t0 = time.monotonic()
                else:
                    # simctl starts writing about half a second after launch.
                    t0 = launched + 0.5
                    print("==> simctl never said 'Recording started'; "
                          "timing from its launch", flush=True)
                print("==> recording", flush=True)
            elif "@@PREVIEW@@" in line:
                # Stamped on arrival; written once time zero is known.
                markers.append((now, line))
                if "@@PREVIEW@@ error" in line:
                    break
            elif "@@PREVIEW_DONE@@" in line:
                ok = t0 is not None
                break
    finally:
        with open(os.path.join(out, "tour.log"), "w") as log:
            for now, line in markers:
                log.write(f"{now - (t0 or now):.3f} {line}\n")
        if recorder is not None:
            time.sleep(0.5)
            recorder.send_signal(signal.SIGINT)
            recorder.wait(timeout=60)
        try:
            run.stdin.write("q")
            run.stdin.flush()
            run.wait(timeout=30)
        except Exception:
            run.kill()
    if not ok:
        sys.exit("the tour did not finish cleanly; see the output above")
    print(f"==> wrote {out}/raw.mov and {out}/tour.log")


if __name__ == "__main__":
    main()
