#!/usr/bin/env python3
"""Synthesises the DartPDF sting soundtrack from the animation's cue sheet.

    node render.cjs --cues build/cues.json
    python3 soundtrack.py build/cues.json build/soundtrack.wav

Everything is generated (numpy only, no samples): a 120 BPM pad/bass/arp bed
that follows MUSIC in the HTML, plus one designed sound per CUES entry, so
picture and sound share a single timeline. Deterministic (fixed seed).
"""
import json
import sys
import wave

import numpy as np

SR = 48000
rng = np.random.default_rng(20261007)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def tvec(dur):
    return np.arange(int(dur * SR)) / SR


def fft_filter(x, lo=None, hi=None, soft=1.3):
    """Static band filter with smooth (non-ringing) edges."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR) + 1e-9
    g = np.ones_like(f)
    if lo:
        g *= 1 / (1 + (lo / f) ** (4 * soft))
    if hi:
        g *= 1 / (1 + (f / hi) ** (4 * soft))
    return np.fft.irfft(X * g, n)


def svf(x, fc, damp=0.9, mode="bp"):
    """Chamberlin state-variable filter with a per-sample cutoff array."""
    fc = np.broadcast_to(np.asarray(fc, dtype=float), x.shape)
    f = 2 * np.sin(np.pi * np.clip(fc, 20, SR / 6.5) / SR)
    low = band = 0.0
    out = np.empty_like(x)
    for i in range(len(x)):
        low += f[i] * band
        high = x[i] - low - damp * band
        band += f[i] * high
        out[i] = band if mode == "bp" else low if mode == "lp" else high
    return out


class Bus:
    def __init__(self, dur):
        self.L = np.zeros(int(dur * SR) + SR * 3)
        self.R = np.zeros_like(self.L)

    def add(self, t, sig, gain=1.0, pan=0.0):
        i = int(round(t * SR))
        if i < 0:
            sig = sig[-i:]
            i = 0
        j = min(len(self.L), i + len(sig))
        sig = sig[: j - i] * gain
        a = (pan + 1) * np.pi / 4
        self.L[i:j] += sig * np.cos(a)
        self.R[i:j] += sig * np.sin(a)


# ------------------------------------------------------------------ voices
def bell(f0, dur=1.6, bright=1.0):
    t = tvec(dur)
    out = np.zeros_like(t)
    for ratio, amp, dec in ((1, 1, 1.0), (2.76, 0.45 * bright, 0.45), (5.4, 0.25 * bright, 0.25), (8.93, 0.12 * bright, 0.12)):
        out += amp * np.sin(2 * np.pi * f0 * ratio * t) * np.exp(-t / (dec * dur / 2.2))
    return out * (1 - np.exp(-t / 0.002))


def pluck(f0, dur=0.35, dec=0.12):
    t = tvec(dur)
    s = np.sin(2 * np.pi * f0 * t) + 0.3 * np.sin(4 * np.pi * f0 * t) + 0.12 * np.sin(6 * np.pi * f0 * t)
    return s * np.exp(-t / dec) * (1 - np.exp(-t / 0.003))


def kick(dur=0.55, punch=1.0, low=45):
    t = tvec(dur)
    f = 150 * np.exp(-t / 0.035) + low
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / (0.28 * punch))
    click = fft_filter(rng.standard_normal(len(t)), lo=2500) * np.exp(-t / 0.003) * 0.25
    return body + click


def noise_burst(dur, lo, hi, dec, attack=0.001):
    t = tvec(dur)
    n = fft_filter(rng.standard_normal(len(t)), lo, hi)
    n /= np.max(np.abs(n)) + 1e-9
    return n * np.exp(-t / dec) * (1 - np.exp(-t / attack))


def sweep(dur, f0, f1, damp=0.6, curve=None, shape=None):
    """Band-passed noise whose centre moves f0 -> f1 (a whoosh)."""
    t = tvec(dur)
    u = t / dur
    fc = f0 * (f1 / f0) ** u
    s = svf(rng.standard_normal(len(t)), fc, damp)
    s /= np.max(np.abs(s)) + 1e-9
    env = shape(u) if shape else np.sin(np.pi * u) ** 1.5
    return s * env


def click(freq=2600, dec=0.012):
    t = tvec(0.06)
    return (np.sin(2 * np.pi * freq * t) * np.exp(-t / dec) * 0.8
            + noise_burst(0.06, 1500, 9000, 0.004) * 0.6)


def key(seed_pan):
    t = tvec(0.07)
    thock = np.sin(2 * np.pi * (170 + 40 * rng.random()) * t) * np.exp(-t / 0.018)
    tick = noise_burst(0.07, 1800, 6000, 0.006)
    return thock * 0.6 + tick * 0.7


# ------------------------------------------------------------------ cues
def render_cue(c, sfx, verb):
    t = c["t"]
    kind = c["type"]
    dur = c.get("dur", 0)
    if kind == "ticks":
        n = int(dur * 34)
        for i in range(n):
            tt = t + rng.random() * dur
            sfx.add(tt, noise_burst(0.03, 3000, 12000, 0.0025), 0.12 * (0.4 + rng.random()), rng.uniform(-0.8, 0.8))
    elif kind == "riser":
        s = sweep(dur + 0.2, 300, 6000, 0.5, shape=lambda u: u ** 2.2 * (1 - np.clip((u - 0.92) / 0.08, 0, 1)))
        sfx.add(t, s, 0.35)
        verb.add(t, s, 0.15)
    elif kind == "land":
        tt = tvec(0.5)
        boom = np.sin(2 * np.pi * (90 * np.exp(-tt / 0.08) + 55) * tt) * np.exp(-tt / 0.18)
        sfx.add(t, boom, 0.7)
        sfx.add(t, noise_burst(0.3, 200, 3000, 0.05), 0.25)
        b = bell(midi(76), 2.0, 0.6)
        verb.add(t, b, 0.2)
        sfx.add(t, b, 0.08)
    elif kind == "shimmer":
        notes = [72, 76, 79, 83, 84, 88, 91]
        for i in range(14):
            tt = t + i * dur / 14 + rng.random() * 0.05
            b = bell(midi(notes[rng.integers(len(notes))] + 12), 0.9, 0.5)
            sfx.add(tt, b, 0.035, rng.uniform(-0.6, 0.6))
            verb.add(tt, b, 0.05)
    elif kind == "highlight":
        tt = tvec(dur)
        u = tt / dur
        felt = svf(rng.standard_normal(len(tt)), 2400 + 900 * u, 1.2)
        felt /= np.max(np.abs(felt))
        grain = 1 + 0.35 * np.sin(2 * np.pi * 38 * tt + 3 * np.sin(2 * np.pi * 7 * tt))
        env = np.clip(u / 0.06, 0, 1) * np.clip((1 - u) / 0.12, 0, 1)
        sfx.add(t, felt * grain * env, 0.22, -0.2 + 0.4 * 0.5)
    elif kind == "pen":
        tt = tvec(dur)
        u = tt / dur
        scratch = svf(rng.standard_normal(len(tt)), 4200, 1.0)
        scratch /= np.max(np.abs(scratch))
        speed = 0.45 + 0.55 * np.abs(np.sin(np.pi * 6 * u + 0.4))
        env = np.clip(u / 0.04, 0, 1) * np.clip((1 - u) / 0.1, 0, 1)
        sfx.add(t, scratch * speed * env, 0.14, 0.25)
    elif kind == "click":
        sfx.add(t, click(), 0.3, 0.15)
    elif kind == "tick":
        sfx.add(t, click(3400, 0.008), 0.18, 0.1)
    elif kind == "swoosh":
        s = sweep(dur, 500, 3500, 0.7)
        sfx.add(t, s, 0.12, 0.3)
    elif kind == "typing":
        n = c.get("count", 10)
        for k in range(1, n + 1):
            tt = t + k * dur / n - 0.008
            sfx.add(tt, key(k), 0.22 * (0.8 + 0.4 * rng.random()), rng.uniform(-0.25, 0.1))
    elif kind == "fall":
        s = sweep(dur, 3000, 500, 0.8, shape=lambda u: u ** 1.5)
        sfx.add(t, s, 0.12)
    elif kind == "stamp":
        tt = tvec(0.9)
        thump = np.sin(2 * np.pi * np.cumsum(110 * np.exp(-tt / 0.06) + 38) / SR) * np.exp(-tt / 0.22)
        slap = noise_burst(0.15, 400, 5000, 0.025)
        dust = noise_burst(0.7, 1500, 8000, 0.25, attack=0.04)
        sfx.add(t, thump, 0.95)
        sfx.add(t, slap, 0.45)
        sfx.add(t + 0.02, dust, 0.06, 0.3)
        verb.add(t, slap, 0.15)
    elif kind == "whoosh":
        s = sweep(dur, 3500, 400, 0.6)
        sfx.add(t, s, 0.2)
        verb.add(t, s, 0.08)
    elif kind == "lift":
        tt = tvec(0.18)
        f = 380 + 400 * (tt / 0.18)
        s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / 0.18)
        sfx.add(t, s, 0.12)
    elif kind == "thunk":
        tt = tvec(0.3)
        s = np.sin(2 * np.pi * np.cumsum(220 * np.exp(-tt / 0.05) + 90) / SR) * np.exp(-tt / 0.07)
        sfx.add(t, s, 0.5)
        sfx.add(t, noise_burst(0.1, 800, 6000, 0.01), 0.2)
    elif kind == "ribbon":
        s = sweep(dur, 800, 5000, 0.5)
        sfx.add(t, s, 0.12, -0.5)
        sfx.add(t, s[::-1], 0.12, 0.5)
    elif kind == "lock":
        for dt, g in ((0.0, 1.0), (0.045, 0.7)):
            tt = tvec(0.2)
            metal = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt / d)
                        for f, d in ((3150, 0.04), (4720, 0.03), (6130, 0.02), (1870, 0.05)))
            sfx.add(t + dt, metal * 0.25 + noise_burst(0.2, 2000, 12000, 0.003) * 0.8, 0.35 * g)
        tt = tvec(0.25)
        sfx.add(t, np.sin(2 * np.pi * 120 * tt) * np.exp(-tt / 0.05), 0.35)
    elif kind == "ding":
        for n in (84, 91):
            b = bell(midi(n), 2.4, 0.8)
            sfx.add(t, b, 0.13)
            verb.add(t, b, 0.22)
    elif kind == "blip":
        n = (76, 79, 83)[c.get("note", 0)]
        tt = tvec(0.25)
        f = midi(n) * (1 + 0.04 * np.exp(-tt / 0.02))
        s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.07) * (1 - np.exp(-tt / 0.002))
        sfx.add(t, s, 0.18, 0.4)
        verb.add(t, s, 0.12)
    elif kind == "reverse":
        tt = tvec(dur)
        u = tt / dur
        s = svf(rng.standard_normal(len(tt)), 600 * (10 ** (1.0 * u)), 0.7)
        s /= np.max(np.abs(s))
        sfx.add(t, s * u ** 3, 0.3)
        verb.add(t, s * u ** 3, 0.1)
    elif kind == "logoHit":
        sfx.add(t, kick(1.2, 2.2, 38), 1.0)
        tt = tvec(2.5)
        sfx.add(t, np.sin(2 * np.pi * 41.2 * tt) * np.exp(-tt / 0.9) * (1 - np.exp(-tt / 0.01)), 0.5)
        sfx.add(t, noise_burst(1.2, 4000, 14000, 0.35), 0.1)
        for i, n in enumerate((60, 64, 67, 71, 74, 79)):
            b = bell(midi(n + 12), 3.0, 0.7)
            sfx.add(t + i * 0.012, b, 0.07, -0.5 + i * 0.2)
            verb.add(t + i * 0.012, b, 0.12)
    elif kind == "sparkle":
        for i in range(8):
            tt = t + i * dur / 8
            b = bell(midi((84, 88, 91, 95, 96, 100, 103, 107)[i]), 0.8, 0.4)
            sfx.add(tt, b, 0.03, -0.7 + i * 0.2)
            verb.add(tt, b, 0.05)


# ------------------------------------------------------------------ music
CHORDS = {
    "C": [48, 55, 59, 62, 64], "Am": [45, 52, 55, 59, 60],
    "F": [41, 48, 52, 55, 57], "G": [43, 50, 52, 59, 62],
}
ROOT = {"C": 36, "Am": 33, "F": 41, "G": 43}


def chord_track(music):
    hit = music["hit"]
    seq = [(0, "C"), (2, "Am"), (4, "F"), (6, "G"), (8, "C"), (10, "Am"), (12, "F"), (14, "G"),
           (15, "Am"), (16.5, "F"), (17.5, "G"), (hit, "C")]
    out = []
    for i, (t0, name) in enumerate(seq):
        t1 = seq[i + 1][0] if i + 1 < len(seq) else music["end"] + 1
        out.append((t0, t1, name))
    return out


def chord_at(track, t):
    for t0, t1, name in track:
        if t0 <= t < t1:
            return name
    return track[-1][2]


def render_music(music, bus, verb):
    dur = music["end"]
    beat = 60 / music["bpm"]
    track = chord_track(music)
    hit = music["hit"]
    n = len(bus.L)
    T = np.arange(n) / SR

    # pad, two detuned voices, crossfaded per chord
    padL = np.zeros(n)
    padR = np.zeros(n)
    for t0, t1, name in track:
        a = int(t0 * SR)
        b = min(n, int((t1 + 0.6) * SR))
        tt = np.arange(b - a) / SR
        env = (1 - np.exp(-tt / 0.35)) * np.clip((t1 + 0.6 - t0 - tt) / 0.6, 0, 1)
        if name == "C" and t0 == hit:
            env *= np.exp(-np.clip(tt - 1.5, 0, None) / 1.8)
        for nn in CHORDS[name]:
            for det, side in ((-5, 0), (5, 1)):
                f = midi(nn + 12) * 2 ** (det / 1200)
                ph = rng.random() * 6.28
                v = sum(np.sin(2 * np.pi * f * k * tt + ph * k) / k ** 1.3 for k in range(1, 7))
                (padL if side == 0 else padR)[a:b] += v * env * 0.05
    # filter opens with the edit, closes for the breakdown, blooms on the hit
    cutoff = np.interp(T, [0, 3.0, 6.0, 15.0, 15.5, 18.4, hit, hit + 2.5, dur + 3],
                       [350, 1500, 2600, 3000, 1100, 1300, 4500, 1600, 900])
    padL = svf(padL, cutoff, 1.1, "lp")
    padR = svf(padR, cutoff, 1.1, "lp")

    # sidechain duck from the kicks
    kicks = [k * beat for k in range(int(music["drumsIn"] / beat), int(music["breakdown"] / beat))]
    duck = np.ones(n)
    for k in kicks:
        i = int(k * SR)
        m = min(n, i + int(0.4 * SR))
        duck[i:m] *= 1 - 0.5 * np.exp(-np.arange(m - i) / SR / 0.12)
    bus.L += padL * duck * 0.9
    bus.R += padR * duck * 0.9
    verb.L += padL * 0.25
    verb.R += padR * 0.25

    for k in kicks:
        bus.add(k, kick(), 0.42)
    # heartbeat kicks under the signature
    for k in (15.0, 16.0, 17.0):
        bus.add(k, kick(0.5, 0.8), 0.3)

    # bass: 8th-note root pulse
    t = music["drumsIn"]
    while t < hit - 0.05:
        name = chord_at(track, t)
        g = 0.24 if t < music["breakdown"] else 0.12
        dec = 0.16 if t < music["breakdown"] else 0.3
        if t >= music["breakdown"] and (t * 2) % 1 > 0.01:
            t += beat / 2
            continue
        tt = tvec(0.45)
        f = midi(ROOT[name])
        s = (np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(4 * np.pi * f * tt)) * np.exp(-tt / dec) * (1 - np.exp(-tt / 0.004))
        bus.add(t, s, g)
        t += beat / 2

    # hats + clap
    t = music["hatsIn"]
    i = 0
    while t < music["breakdown"]:
        off = t + beat / 2
        bus.add(off, noise_burst(0.08, 7000, None, 0.035), 0.09, 0.35 if i % 2 else -0.35)
        if t >= 9.0:
            bus.add(t + beat / 4, noise_burst(0.05, 8000, None, 0.015), 0.035, 0.5)
            bus.add(t + 3 * beat / 4, noise_burst(0.05, 8000, None, 0.015), 0.035, -0.5)
        if abs((t % 2) - 0.5) < 1e-6 or abs((t % 2) - 1.5) < 1e-6:
            cl = noise_burst(0.25, 900, 5000, 0.07)
            tt = tvec(0.25)
            cl += 0.5 * np.sin(2 * np.pi * 190 * tt) * np.exp(-tt / 0.04)
            bus.add(t, cl, 0.2)
            verb.add(t, cl, 0.12)
        t += beat
        i += 1

    # arp: 16ths through the edit montage
    a0, a1 = music["arp"]
    pattern = [0, 2, 4, 3, 1, 2, 4, 3]
    t = a0
    i = 0
    while t < a1 - 1e-6:
        notes = CHORDS[chord_at(track, t)]
        nn = notes[pattern[i % 8]] + 24
        fade = min(1, (t - a0) / 1.0) * min(1, (a1 - t) / 0.5)
        p = pluck(midi(nn), 0.3, 0.09)
        bus.add(t, p, 0.045 * fade, 0.45 if i % 2 else -0.45)
        verb.add(t, p, 0.05 * fade)
        t += beat / 4
        i += 1


def reverb(verb, seconds=2.2):
    n_ir = int(seconds * SR)
    tt = np.arange(n_ir) / SR
    outs = []
    for ch, x in ((0, verb.L), (1, verb.R)):
        ir = rng.standard_normal(n_ir) * np.exp(-tt / (seconds / 6.9)) * (1 - np.exp(-tt / 0.01))
        ir = fft_filter(ir, 150, 7000)
        ir[: int(0.018 * SR)] = 0
        ir /= np.sqrt(np.sum(ir ** 2))
        size = 1 << int(np.ceil(np.log2(len(x) + n_ir)))
        y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
        outs.append(y)
    return outs


def main():
    cues_path, out_path = sys.argv[1], sys.argv[2]
    data = json.load(open(cues_path))
    dur = data["duration"]
    music = data["music"]
    mus, sfx, verb = Bus(dur), Bus(dur), Bus(dur)
    render_music(music, mus, verb)
    for c in data["cues"]:
        render_cue(c, sfx, verb)
    vL, vR = reverb(verb)
    L = mus.L * 0.8 + sfx.L + vL * 0.55
    R = mus.R * 0.8 + sfx.R + vR * 0.55
    n = int(dur * SR)
    L, R = L[:n], R[:n]
    # fade in/out with the picture
    T = np.arange(n) / SR
    fade = np.clip(T / 0.3, 0, 1) * np.clip((dur - T) / 0.6, 0, 1)
    L *= fade
    R *= fade
    # gentle glue: normalise, soft-clip, re-normalise to -1 dBFS
    peak = max(np.max(np.abs(L)), np.max(np.abs(R)))
    L, R = np.tanh(1.6 * L / peak) / np.tanh(1.6), np.tanh(1.6 * R / peak) / np.tanh(1.6)
    peak = max(np.max(np.abs(L)), np.max(np.abs(R)))
    g = 10 ** (-1 / 20) / peak
    L, R = L * g, R * g
    rms = np.sqrt(np.mean((L ** 2 + R ** 2) / 2))
    pcm = (np.stack([L, R], 1) * 32767).astype(np.int16)
    with wave.open(out_path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"wrote {out_path}: {dur:.1f}s, RMS {20 * np.log10(rms):.1f} dBFS")


if __name__ == "__main__":
    main()
