"""Faster delivery for the voice, without changing its pitch.

eleven_v4 (the most natural voice in the audition) ignores the `speed` setting (measured:
4.96 s at 1.0, 4.88 s at 1.2), and multilingual v2, which honours it, measured more robotic
(uniform 0.23 s pauses, narrower pitch range). So the v4 takes are tightened here:
  1. pauses inside a line longer than 0.22 s are shortened to 0.20 s, cut at silence;
  2. a 12% tempo lift with ffmpeg atempo (WSOLA: duration changes, pitch does not).
Writes public/v2/vo-fast/<id>.wav and src/v2/vo-fast.json (durations and word times).
  python3 -I scripts/film/tighten_voice.py
"""
import json, os, subprocess, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measure

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEMPO = 1.12
KEEP, LONGEST = 0.20, 0.22
SR = 48000
src = json.load(open(os.path.join(ROOT, "src/v2/vo-measured.json")))
out_dir = os.path.join(ROOT, "public/v2/vo-fast")
os.makedirs(out_dir, exist_ok=True)


def load(p):
    return np.frombuffer(subprocess.run(["ffmpeg", "-v", "error", "-i", p, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                                        capture_output=True, check=True).stdout, np.float32).copy()


result = {}
for lid, d in src.items():
    x = load(os.path.join(ROOT, "public/v2/vo", lid + ".wav"))
    fr = int(0.01 * SR)
    db = np.array([20 * np.log10(np.sqrt(np.mean(x[i:i + fr] ** 2)) + 1e-9) for i in range(0, len(x) - fr, fr)])
    loud = np.where(db > -40)[0]
    s0, s1 = loud[0], loud[-1]
    cuts = []  # (start_s, removed_s)
    run = None
    for i in range(s0, s1):
        if db[i] <= -40:
            run = i if run is None else run
        else:
            if run is not None and (i - run) / 100 > LONGEST:
                a, b = run / 100, i / 100
                rem = (b - a) - KEEP
                cuts.append((a + KEEP / 2, rem))
            run = None
    y = x.copy()
    xf = int(0.015 * SR)
    for a, rem in sorted(cuts, reverse=True):
        i, j = int(a * SR), int((a + rem) * SR)
        fade = np.linspace(1, 0, xf, dtype=np.float32)
        head = y[:i].copy()
        tail = y[j:].copy()
        head[-xf:] = head[-xf:] * fade + tail[:xf] * (1 - fade)
        y = np.concatenate([head, tail[xf:]])
    tmp = os.path.join(ROOT, "voice/work/_tight.wav")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", tmp], input=y.tobytes(), check=True)
    wav = os.path.join(out_dir, lid + ".wav")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-af", f"atempo={TEMPO}", "-ar", str(SR), "-ac", "1", wav], check=True)

    def remap(t):
        removed = sum(rem for a, rem in cuts if a < t)
        return round((t - removed) / TEMPO, 3)

    words = [dict(w=w["w"], s=remap(w["s"]), e=remap(w["e"])) for w in d["words"]]
    dur = len(load(wav)) / SR
    before = measure.f0_track(measure.load(os.path.join(ROOT, "public/v2/vo", lid + ".wav")))
    after = measure.f0_track(measure.load(wav))
    p0, p1 = np.nanmedian(before), np.nanmedian(after)
    result[lid] = dict(text=d["text"], dur=round(dur, 3), words=words)
    print(f"{lid:9s} {d['dur']:5.2f}s -> {dur:5.2f}s  ({dur / d['dur']:.2f}x)  pauses cut {len(cuts)}  pitch {p0:.0f} -> {p1:.0f} Hz")
json.dump(result, open(os.path.join(ROOT, "src/v2/vo-fast.json"), "w"), indent=1)
