"""Mix the film and teaser audio from src/v2/edit.json.

  python3 -I scripts/film/mix.py
Writes public/v2/mix-film.wav, mix-film-novo.wav, mix-teaser.wav (48 kHz stereo, -14 LUFS,
true peak under -1 dBTP) and prints the measurements.

Music: "Uplifting Electronic Indie" by WinnieTheMoog, CC BY 4.0 (see MUSIC.md), edited on its
own bar grid. Picture cues are authored on the picture timeline; every cue time here goes
through the same warp the picture uses (edit.json "warp"), and the voice is the tightened take
(vo-fast.json) placed by build_edit.py.
Sound design is synthesized here (no samples), so it carries no licence of its own.
"""
import json, os, subprocess, sys
import numpy as np
from scipy.signal import butter, sosfilt

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SR = 48000
EDIT = json.load(open(os.path.join(ROOT, "src/v2/edit.json")))
MEAS = json.load(open(os.path.join(ROOT, "src/v2/vo-measured.json")))
FAST = json.load(open(os.path.join(ROOT, "src/v2/vo-fast.json")))
MUSIC = os.path.join(ROOT, "voice/work/music/winnie-uplifting-electronic-indie.ogg")
CUT = {"name": "film"}


def warp(t, cut=None):
    k = EDIT["warp"][cut or CUT["name"]]
    for (o0, n0), (o1, n1) in zip(k, k[1:]):
        if t <= o1:
            return n0 + (t - o0) * (n1 - n0) / (o1 - o0)
    return k[-1][1] + (t - k[-1][0])
rng = np.random.default_rng(7)


def load(path, ch=2):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", str(ch), "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, ch).copy()


def save(path, x):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "pcm_s24le", path], input=x.astype(np.float32).tobytes(), check=True)


def ebur(path):
    r = subprocess.run(["ffmpeg", "-v", "info", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    I = TP = LRA = None
    for line in r.splitlines():
        t = line.strip()
        if t.startswith("I:"): I = float(t.split()[1])
        if t.startswith("Peak:"): TP = float(t.split()[1])
        if t.startswith("LRA:"): LRA = float(t.split()[1])
    return I, TP, LRA


def db(x): return 10 ** (x / 20)


# ---------- music edit ----------
def bar_time(k): return EDIT["grid2"]["offset"] + EDIT["grid2"]["bar"] * k


def music_edit(cut, track):
    dur = EDIT["audio"][cut]["duration"]
    out = np.zeros((int(dur * SR) + SR, 2), np.float32)
    xf = int(0.012 * SR)  # 12 ms equal-power splice, centred 6 ms before the downbeat
    pre = int(0.006 * SR)
    segs = EDIT["audio"][cut]["music"]
    for i, sg in enumerate(segs):
        a = int(bar_time(sg["fromBar"]) * SR) - pre
        b = int(bar_time(sg["toBar"]) * SR) - pre
        if sg.get("stop"):
            b += int(0.35 * SR)  # keep the stop hit itself
        b = min(b, len(track))
        piece = track[a:b + xf].copy()
        n = len(piece)
        env = np.ones(n, np.float32)
        if i > 0:
            env[:xf] = np.sin(np.linspace(0, np.pi / 2, xf)) ** 1
        if i + 1 < len(segs):
            env[-xf:] = np.cos(np.linspace(0, np.pi / 2, xf))
        piece *= env[:, None]
        at = int(sg["at"] * SR) - pre
        lo = max(0, at)
        out[lo:at + n] += piece[lo - at:][: len(out) - lo]
        if sg.get("stop"):
            # the track ends on a hard stop; a synthesized room tail lets the last hit ring
            ir_n = int(2.4 * SR)
            ir = rng.standard_normal((ir_n, 2)) * np.exp(-np.arange(ir_n) / (0.55 * SR))[:, None]
            ir = np.stack([lp(ir[:, c], 5000) for c in range(2)], 1)
            last = piece[-int(1.0 * SR):]
            from scipy.signal import fftconvolve
            wet = np.stack([fftconvolve(last[:, c], ir[:, c]) for c in range(2)], 1)
            wet *= 0.5 * np.abs(last).max() / (np.abs(wet).max() + 1e-9)
            i0 = at + n - len(last)
            m = min(len(wet), len(out) - i0)
            out[i0:i0 + m] += wet[:m]
    out = out[:int(dur * SR)]
    # fade in from the first sample, and a long fade at the very end
    fi = int(0.05 * SR)
    out[:fi] *= np.linspace(0, 1, fi)[:, None]
    fo = int(0.4 * SR)
    out[-fo:] *= (np.linspace(1, 0, fo) ** 2)[:, None]
    return out


# ---------- sound design (synthesized) ----------
def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def lp(x, f, order=2):
    return sosfilt(butter(order, f, btype="low", fs=SR, output="sos"), x)


def env_exp(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def sfx_click(gain=-24):
    n = int(0.05 * SR)
    noise = bp(rng.standard_normal(n), 2500, 7000) * env_exp(n, 0.0025)
    t = np.arange(n) / SR
    tick = np.sin(2 * np.pi * 1750 * t) * env_exp(n, 0.008)
    x = 0.6 * noise / (np.abs(noise).max() + 1e-9) + 0.5 * tick
    return x * db(gain)


def sfx_tock(gain=-20):
    """The haptic, heard: a short low knock under a click."""
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * (165 * t - 40 * t * t)) * env_exp(n, 0.022)
    x = body.copy()
    c = sfx_click(0)
    x[:len(c)] += 0.6 * c
    return x / np.abs(x).max() * db(gain)


def sfx_whoosh(dur=0.6, gain=-27, lo=300, hi=3500):
    n = int(dur * SR)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    # moving band: centre sweeps up then down
    steps = 24
    for k in range(steps):
        a, b = k * n // steps, (k + 1) * n // steps
        u = (k + 0.5) / steps
        c = lo * (hi / lo) ** np.sin(np.pi * u)
        seg = bp(noise[max(0, a - 512):b], c * 0.6, min(c * 1.6, SR / 2 - 100))[-(b - a):]
        out[a:b] = seg
    e = np.sin(np.linspace(0, np.pi, n)) ** 2
    x = out * e
    return x / (np.abs(x).max() + 1e-9) * db(gain)


def sfx_blip(gain=-30, f0=880, f1=1320):
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    f = np.linspace(f0, f1, n)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(n, 0.025) * np.minimum(1, t / 0.004)
    return x * db(gain)


def sfx_riser(dur=1.4, gain=-26):
    n = int(dur * SR)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    steps = 28
    for k in range(steps):
        a, b = k * n // steps, (k + 1) * n // steps
        c = 400 * (8000 / 400) ** (k / steps)
        out[a:b] = lp(noise[max(0, a - 512):b], c)[-(b - a):]
    e = (np.arange(n) / n) ** 2.4
    x = out * e
    return x / (np.abs(x).max() + 1e-9) * db(gain)


def sfx_impact(gain=-17, dur=1.6):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 46 + 40 * np.exp(-t / 0.05)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(n, 0.35)
    air = lp(rng.standard_normal(n), 2500) * env_exp(n, 0.05) * 0.35
    x = sub + air
    return x / np.abs(x).max() * db(gain)


def place(buf, x, t, pan=0.0, align="start"):
    """`t` is picture time; it is warped to the final cut. align: where t sits on the sound."""
    i = int(warp(t) * SR) - (len(x) if align == "end" else len(x) // 2 if align == "center" else 0)
    if i < 0:
        x, i = x[-i:], 0
    if i >= len(buf): return
    x = x[: len(buf) - i]
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    buf[i:i + len(x), 0] += x * l * 1.41
    buf[i:i + len(x), 1] += x * r * 1.41


def film_sfx(dur):
    b = np.zeros((int(dur * SR), 2), np.float32)
    w = lambda t, d=0.6, g=-28, pan=0.0, lo=300, hi=3500: place(b, sfx_whoosh(d, g, lo, hi), t, pan, "center")
    w(3.55, 1.3, -25, 0.2, 150, 2400)                   # the phone rises in the music's rest
    place(b, sfx_tock(-24), 5.05)                       # the dot lands
    place(b, sfx_riser(1.5, -27), 8.0, align="end")     # into the hit
    place(b, sfx_impact(-16), 7.985)                    # the title
    w(10.9, 0.9, -27, 0, 200, 2200)                     # field folds into the glass
    place(b, sfx_blip(-31, 990, 1480), 12.55)           # Connected
    w(14.4, 0.7, -30)                                   # camera to the touch shot
    place(b, sfx_blip(-33, 700, 1050), 16.45)           # dot becomes the pointer
    for i in range(24):                                 # display ticks
        place(b, sfx_click(-40 - (i % 2) * 2), 19.1 + i * 4 / 60, 0.3)
    place(b, sfx_tock(-19), 21.31, -0.3)                # the tap, felt
    place(b, sfx_click(-27), 21.33, 0.3)                # the click on the Mac
    w(23.6, 0.8, -30)                                   # to the Spaces shot
    w(25.75, 1.2, -26, 0.2, 180, 2600)                  # Spaces slide
    w(27.6, 1.0, -29, -0.2, 180, 2200)
    w(31.45, 0.7, -30)
    for t in ("settings", 5), ("settings", 6), ("settings", 8):
        tt = EDIT_WORD(*t)
        place(b, sfx_click(-29), tt, 0.4)
        place(b, sfx_blip(-34, 820, 1230), tt + 0.6, -0.3)
    w(39.5, 0.9, -27, -0.2, 200, 2600)                  # picked up
    place(b, sfx_tock(-22), EDIT_WORD("modes", 0) + 0.28, -0.2)   # pill
    place(b, sfx_tock(-23), 42.36, -0.2)                           # Apps
    place(b, sfx_tock(-21), EDIT_WORD("apps", 1) + 0.05, -0.2)     # Word
    for k in range(2):                                             # Dock bounce
        place(b, sfx_blip(-31, 520 - 60 * k, 700 - 60 * k), EDIT_WORD("apps", 1) + 0.55 + k * 0.36, 0.3)
    w(47.4, 0.8, -29)
    place(b, sfx_click(-25), EDIT_WORD("actions2", 2) + 0.06, -0.3)  # click Safari
    place(b, sfx_blip(-30, 880, 1320), 52.3, 0.3)                    # phone follows
    for t in (54.0, 54.5):
        place(b, sfx_blip(-36, 660, 660), t, 0.35)
    place(b, sfx_tock(-21), 55.0, 0.3)                               # Dark mode
    w(55.35, 0.8, -29, -0.3, 200, 1800)
    place(b, sfx_impact(-22, 1.2), 39.985)                           # the lift at Modes
    place(b, sfx_impact(-21, 1.4), 67.785)                           # the return, end card
    place(b, sfx_impact(-22, 1.6), 71.985)                           # the stop, URLs
    w(58.9, 0.9, -32, 0.3, 400, 3000)                                # scrub
    w(60.1, 0.9, -25, 0, 150, 2400)                                  # cover opens
    place(b, sfx_tock(-26), EDIT_WORD("privacy2", 3) + 0.05)        # the lock
    w(67.45, 0.8, -27, 0, 200, 2500)                                 # fold
    w(68.5, 0.7, -32, 0.2, 500, 3500)                                # the icon's glide
    return b


def teaser_sfx(dur):
    b = np.zeros((int(dur * SR), 2), np.float32)
    w = lambda t, d=0.6, g=-28, pan=0.0, lo=300, hi=3500: place(b, sfx_whoosh(d, g, lo, hi), t, pan, "center")
    place(b, sfx_tock(-24), 3.1)
    place(b, sfx_riser(1.2, -27), 4.0, align="end")
    place(b, sfx_impact(-16), 3.985)
    w(6.4, 0.9, -27, 0, 200, 2200)
    w(9.3, 1.2, -26, 0.2, 180, 2600)
    w(11.7, 0.8, -28)
    place(b, sfx_impact(-23, 1.2), 11.985)
    place(b, sfx_click(-25), EDIT_WORD("actions2", 2, "teaser") + 0.06)
    place(b, sfx_blip(-30, 880, 1320), EDIT_WORD("actions2", 2, "teaser") + 0.85)
    w(19.7, 0.9, -27, 0, 200, 2500)
    place(b, sfx_impact(-21, 1.4), 23.985)
    place(b, sfx_impact(-22, 1.6), 27.985)
    return b


def EDIT_WORD(line, i, cut="film"):
    """Picture-time start of a word (place() warps it)."""
    at = next(v["at"] for v in EDIT[cut]["vo"] if v["id"] == line)
    return at + MEAS[line]["words"][i]["s"]


# ---------- voice ----------
def voice_track(cut, dur):
    v = np.zeros((int(dur * SR), 2), np.float32)
    spans = []
    for item in EDIT["audio"][cut]["vo"]:
        x = load(os.path.join(ROOT, "public/v2/vo-fast", item["id"] + ".wav"), 1)[:, 0]
        # level each line to the same loudness (-18 LUFS before the master gain)
        tmp = os.path.join(ROOT, "voice/work/_line.wav")
        save(tmp, np.stack([x, x], 1))
        I, _, _ = ebur(tmp)
        x = x * db(-18 - I)
        i = int(item["at"] * SR)
        n = min(len(x), len(v) - i)
        v[i:i + n, 0] += x[:n]
        v[i:i + n, 1] += x[:n]
        spans.append((item["at"], item["at"] + len(x) / SR))
    return v, spans


def duck_env(spans, dur, depth_db=-8.5, attack=0.18, release=0.45):
    n = int(dur * SR)
    g = np.zeros(n)
    t = np.arange(n) / SR
    for a, b in spans:
        up = np.clip((t - (a - attack)) / attack, 0, 1)
        down = np.clip(1 - (t - b) / release, 0, 1)
        g = np.maximum(g, np.minimum(up, down))
    g = (1 - np.cos(np.pi * g)) / 2  # smooth
    return db(depth_db * g)


def master(x, target=-14.0, tp_ceiling=-1.5, path=None):
    """Gain to target loudness, then a soft-knee peak limiter (true peak checked by ebur128)."""
    tmp = path or os.path.join(ROOT, "voice/work/_m.wav")
    save(tmp, x)
    I, _, _ = ebur(tmp)
    x = x * db(target - I)
    # look-ahead limiter on the 4x oversampled envelope keeps inter-sample peaks under the ceiling
    from scipy.signal import resample_poly
    ceil = db(tp_ceiling)
    up = resample_poly(np.abs(x).max(1), 4, 1)
    peak = np.maximum.reduceat(up, np.arange(0, len(up), 4))[: len(x)]
    need = np.minimum(1, ceil / np.maximum(peak, 1e-9))
    la = int(0.003 * SR)
    # smooth gain: instant attack via look-ahead minimum, 80 ms release
    from scipy.ndimage import minimum_filter1d
    g = minimum_filter1d(need, size=2 * la + 1)
    rel = np.exp(-1 / (0.08 * SR))
    out = np.empty_like(g)
    cur = 1.0
    for i in range(len(g)):
        cur = g[i] if g[i] < cur else g[i] + (cur - g[i]) * rel
        out[i] = cur
    x = x * out[:, None]
    save(tmp, x)
    I2, TP2, LRA = ebur(tmp)
    x = x * db(target - I2)  # re-trim after limiting
    return x


def build(cut, with_vo=True):
    CUT["name"] = cut
    dur = EDIT["audio"][cut]["duration"]
    track = load(MUSIC)
    m = music_edit(cut, track)
    sfx = film_sfx(dur) if cut == "film" else teaser_sfx(dur)
    if with_vo:
        v, spans = voice_track(cut, dur)
        m = m * duck_env(spans, dur)[:, None]
        mix = m * db(-4) + v + sfx
    else:
        mix = m * db(-4) + sfx
    return master(mix)


if __name__ == "__main__":
    os.makedirs(os.path.join(ROOT, "public/v2"), exist_ok=True)
    for name, cut, vo in (("mix-film.wav", "film", True), ("mix-film-novo.wav", "film", False), ("mix-teaser.wav", "teaser", True)):
        out = os.path.join(ROOT, "public/v2", name)
        save(out, build(cut, vo))
        I, TP, LRA = ebur(out)
        print(f"{name:20s} I {I} LUFS  true peak {TP} dBTP  LRA {LRA}")
