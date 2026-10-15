"""Objective listening for voice takes: pitch movement, pace, pauses, loudness, clipped ends.

A flat voice reads as robotic: narrow pitch range, even syllable timing, identical pauses.
These numbers are what the audition and the per-line checks compare.
"""
import subprocess, numpy as np

SR = 24000


def load(path, sr=SR):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"],
                         capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def f0_track(x, sr=SR, hop=0.01, win=0.04, fmin=70, fmax=350):
    """Plain normalised autocorrelation pitch per 10 ms frame. NaN where unvoiced."""
    n, h = int(win * sr), int(hop * sr)
    out = []
    lo, hi = int(sr / fmax), int(sr / fmin)
    for i in range(0, len(x) - n, h):
        f = x[i:i + n] * np.hanning(n)
        if np.sqrt(np.mean(f ** 2)) < 0.01:
            out.append(np.nan); continue
        ac = np.correlate(f, f, "full")[n - 1:]
        ac /= ac[0] + 1e-12
        lag = lo + np.argmax(ac[lo:hi])
        out.append(sr / lag if ac[lag] > 0.45 else np.nan)
    return np.array(out)


def lufs(path):
    r = subprocess.run(["ffmpeg", "-v", "info", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    I = TP = None
    for line in r.splitlines():
        s = line.strip()
        if s.startswith("I:"): I = float(s.split()[1])
        if s.startswith("Peak:"): TP = float(s.split()[1])
    return I, TP


def report(path, alignment=None):
    x = load(path)
    dur = len(x) / SR
    f0 = f0_track(x)
    v = f0[~np.isnan(f0)]
    semis = 12 * np.log2(v / np.median(v)) if len(v) else np.array([0])
    # pauses: runs of 10 ms frames below -40 dBFS inside the speech
    fr = int(0.01 * SR)
    db = np.array([20 * np.log10(np.sqrt(np.mean(x[i:i + fr] ** 2)) + 1e-9) for i in range(0, len(x) - fr, fr)])
    speech = np.where(db > -40)[0]
    pauses = []
    if len(speech):
        s, e = speech[0], speech[-1]
        run = 0
        for d in db[s:e]:
            if d <= -40: run += 1
            else:
                if run >= 12: pauses.append(run / 100)
                run = 0
        lead, tail = s / 100, dur - e / 100
    else:
        lead = tail = 0
    # clipped end: is the last speech frame still loud right at the file end?
    end_db = db[-3:].max() if len(db) >= 3 else -99
    words = None
    if alignment and alignment.get("characters"):
        text = "".join(alignment["characters"])
        words = len(text.split())
    I, TP = lufs(path)
    return dict(dur=round(dur, 2), lead=round(lead, 2), tail=round(tail, 2), end_db=round(float(end_db), 1),
                f0_med=round(float(np.median(v)), 1) if len(v) else 0,
                range_st=round(float(np.percentile(semis, 95) - np.percentile(semis, 5)), 2),
                sd_st=round(float(np.std(semis)), 2), pauses=[round(p, 2) for p in pauses],
                wps=round(words / (dur - lead - tail), 2) if words else None, lufs=I, tp=TP)
