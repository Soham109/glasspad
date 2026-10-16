"""Mix the v4 film's audio from src/v4/edit.json, the voice (public/v4/vo) and the picture's
sound cues (src/v4/cues.json, written by `pnpm v4:cues`).

  python3 -I scripts/v4/mix.py
Writes public/v4/mix-film.wav and mix-film-novo.wav (48 kHz stereo, 24 bit) and the stems in
voice/work/v4-stems, and prints loudness: each stem, the voice alone, the music under speech
and in the breaths between lines, and the master (integrated, true peak, range).

Music: "Uplifting Electronic Indie" by WinnieTheMoog, CC BY 4.0 (MUSIC.md), cut on its own
bar grid (12 ms equal power splices just before downbeats). It is ducked under the voice with
a smooth side chain (attack 120 ms, release 450 ms): low under speech, rising in the breaths.
Sound design is synthesized here (no samples), quiet, and only where something happens.
"""
import json, os, subprocess, sys
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SR = 48000
E = json.load(open(os.path.join(ROOT, "src/v4/edit.json")))
CUES = json.load(open(os.path.join(ROOT, "src/v4/cues.json")))
MEAS = json.load(open(os.path.join(ROOT, "src/v4/vo-measured.json")))
MUSIC = os.path.join(ROOT, "voice/work/music/winnie-uplifting-electronic-indie.ogg")
OUT = os.path.join(ROOT, "public/v4")
STEMS = os.path.join(ROOT, "voice/work/v4-stems")
os.makedirs(STEMS, exist_ok=True)
rng = np.random.default_rng(11)

# Levels (dB). The voice is set to its target loudness; the bed sits under it.
VOICE_LUFS = -16.0
BED_OPEN = -9.0  # music gain in the breaths (relative to the track as mastered)
BED_DUCK = -19.5  # music gain under speech
SFX_DB = -6.0  # overall sound design trim


def load(path, ch=2):
    raw = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-ac", str(ch), "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, ch).copy()


def save(path, x):
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "pcm_s24le", path], input=x.astype(np.float32).tobytes(), check=True)


def ebur(path):
    r = subprocess.run(["ffmpeg", "-nostdin", "-v", "info", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    I = TP = LRA = None
    for line in r.splitlines():
        t = line.strip()
        if t.startswith("I:"): I = float(t.split()[1])
        if t.startswith("Peak:"): TP = float(t.split()[1])
        if t.startswith("LRA:"): LRA = float(t.split()[1])
    return I, TP, LRA


def lufs_of(x):
    tmp = os.path.join(STEMS, "_m.wav")
    save(tmp, x if x.ndim == 2 else np.stack([x, x], 1))
    return ebur(tmp)[0]


def db(v): return 10 ** (v / 20)
def lp(x, f, o=2): return sosfilt(butter(o, f, btype="low", fs=SR, output="sos"), x)
def hp(x, f, o=2): return sosfilt(butter(o, f, btype="high", fs=SR, output="sos"), x)
def bp(x, lo, hi, o=2): return sosfilt(butter(o, [lo, hi], btype="band", fs=SR, output="sos"), x)


DUR = E["duration"]
N = int(DUR * SR)
BAR = E["bar"]
GRID = E["grid"]


# ---------- music ----------
def bar_time(k): return GRID["offset"] + GRID["bar"] * k


def music_edit():
    track = load(MUSIC)
    out = np.zeros((N + SR, 2), np.float32)
    xf, pre = int(0.012 * SR), int(0.006 * SR)
    segs = E["music"]
    for i, sg in enumerate(segs):
        a = int(bar_time(sg["fromBar"]) * SR) - pre
        b = int(bar_time(sg["toBar"]) * SR) - pre
        if sg.get("stop"):
            b += int(0.35 * SR)
        b = min(b, len(track))
        piece = track[a:b + xf].copy()
        n = len(piece)
        env = np.ones(n, np.float32)
        if i > 0:
            env[:xf] = np.sin(np.linspace(0, np.pi / 2, xf))
        if i + 1 < len(segs):
            env[-xf:] = np.cos(np.linspace(0, np.pi / 2, xf))
        piece *= env[:, None]
        at = int(sg["at"] * BAR * SR) - pre
        lo = max(0, at)
        out[lo:at + n] += piece[lo - at:][: len(out) - lo]
        if sg.get("stop"):
            # the track ends on a hard stop; a short synthesized room tail lets it ring
            ir_n = int(2.4 * SR)
            ir = rng.standard_normal((ir_n, 2)) * np.exp(-np.arange(ir_n) / (0.55 * SR))[:, None]
            ir = np.stack([lp(ir[:, c], 5000) for c in range(2)], 1)
            last = piece[-int(1.0 * SR):]
            wet = np.stack([fftconvolve(last[:, c], ir[:, c]) for c in range(2)], 1)
            wet *= 0.45 * np.abs(last).max() / (np.abs(wet).max() + 1e-9)
            i0 = at + n - len(last)
            m = min(len(wet), len(out) - i0)
            out[i0:i0 + m] += wet[:m]
    out = out[:N]
    fi = int(1.2 * SR)  # fade in over the first touch
    out[:fi] *= (np.linspace(0, 1, fi) ** 1.5)[:, None]
    fo = int(0.6 * SR)
    out[-fo:] *= (np.linspace(1, 0, fo) ** 2)[:, None]
    return out


# ---------- voice ----------
def voice_track():
    v = np.zeros(N, np.float32)
    active = np.zeros(N, np.float32)
    for line in E["vo"]:
        x = load(os.path.join(OUT, "vo", line["id"] + ".wav"), ch=1)[:, 0]
        # each line to the same loudness, so no line jumps out
        g = db(VOICE_LUFS - lufs_of(x))
        x = hp(x * g, 70)
        i = int(line["at"] * SR)
        m = min(len(x), N - i)
        v[i:i + m] += x[:m]
        active[i:i + m] = 1
    return v, active


def duck_curve(active):
    """Music gain per sample: BED_DUCK while the voice speaks, BED_OPEN otherwise, with a
    lookahead so the bed is already down when the first word lands."""
    look = int(0.15 * SR)
    a = np.concatenate([active[look:], np.zeros(look, np.float32)])
    a = np.maximum(a, active)
    att, rel = 0.12, 0.45
    env = np.zeros_like(a)
    ka, kr = 1 - np.exp(-1 / (att * SR)), 1 - np.exp(-1 / (rel * SR))
    # one pole smoothing, run at a coarse rate for speed then upsampled
    step = 48
    coarse = a[::step]
    e = np.zeros_like(coarse)
    cur = 0.0
    ka_c, kr_c = 1 - (1 - ka) ** step, 1 - (1 - kr) ** step
    for i, val in enumerate(coarse):
        k = ka_c if val > cur else kr_c
        cur += (val - cur) * k
        e[i] = cur
    env = np.interp(np.arange(len(a)), np.arange(len(coarse)) * step, e)
    gain_db = BED_OPEN + (BED_DUCK - BED_OPEN) * env
    return db(gain_db).astype(np.float32)


# ---------- sound design (synthesized) ----------
def env_exp(n, tau): return np.exp(-np.arange(n) / (tau * SR))


def tap(level=-30):
    n = int(0.05 * SR)
    click = bp(rng.standard_normal(n), 1800, 6000) * env_exp(n, 0.004)
    thump = np.sin(2 * np.pi * 140 * np.arange(n) / SR) * env_exp(n, 0.012) * 0.6
    x = click / (np.abs(click).max() + 1e-9) * 0.6 + thump
    return x / np.abs(x).max() * db(level)


def key(level=-36):
    n = int(0.03 * SR)
    x = bp(rng.standard_normal(n), 2500, 8000) * env_exp(n, 0.003)
    return x / np.abs(x).max() * db(level)


def haptic(level=-24):
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * 75 * t) * env_exp(n, 0.02) + 0.3 * np.sin(2 * np.pi * 150 * t) * env_exp(n, 0.01)
    return x / np.abs(x).max() * db(level)


def whoosh(dur=0.5, level=-30):
    n = int(dur * SR)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    blk = int(0.01 * SR)
    for i in range(0, n, blk):
        u = i / n
        f = 300 + 3500 * np.sin(np.pi * u) ** 2
        seg = bp(noise[max(0, i - 400):i + blk], f * 0.6, min(f * 1.6, 20000))[-blk:]
        out[i:i + len(seg)] = seg[: n - i]
    e = np.sin(np.pi * np.linspace(0, 1, n)) ** 2
    x = out * e
    return x / (np.abs(x).max() + 1e-9) * db(level)


def chime(level=-32):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    x = (np.sin(2 * np.pi * 1318.5 * t) * env_exp(n, 0.35) + 0.6 * np.sin(2 * np.pi * 1975.5 * t) * env_exp(n, 0.25) * (t > 0.09))
    return x / np.abs(x).max() * db(level)


def slide(dur, level=-38):
    n = int(dur * SR)
    x = lp(rng.standard_normal(n), 1800) * np.sin(np.pi * np.linspace(0, 1, n)) ** 1.5
    return x / (np.abs(x).max() + 1e-9) * db(level)


def place(buf, x, t, pan=0.0):
    i = int(t * SR)
    if i >= len(buf) or i + len(x) <= 0:
        return
    j0 = max(0, -i)
    m = min(len(x) - j0, len(buf) - max(0, i))
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    buf[max(0, i):max(0, i) + m, 0] += x[j0:j0 + m] * l * 1.414
    buf[max(0, i):max(0, i) + m, 1] += x[j0:j0 + m] * r * 1.414


def sfx_track():
    s = np.zeros((N, 2), np.float32)
    for t in CUES.get("tap", []): place(s, tap(), t)
    for t in CUES.get("click", []): place(s, tap(-32), t, -0.2)
    for t in CUES.get("key", []): place(s, key(), t)
    for t in CUES.get("haptic", []) + CUES.get("blade", []) + CUES.get("lock", []): place(s, haptic(), t)
    for t in CUES.get("whoosh", []): place(s, whoosh(), t - 0.25)
    for t in CUES.get("skip", []): place(s, whoosh(0.35, -32), t - 0.15, 0.2)
    for t in CUES.get("land", []): place(s, tap(-30), t + 0.4)
    for t in CUES.get("chime", []): place(s, chime(), t, 0.35)
    for t in CUES.get("wake", []): place(s, whoosh(0.9, -34), t - 0.5)
    for a, b in CUES.get("drag", []) + CUES.get("swipe", []): place(s, slide(b - a + 0.1), a)
    return s * db(SFX_DB)


def limiter(x, ceiling_db=-1.2):
    """Lookahead peak limiter on 4x oversampled peaks (a true peak estimate)."""
    from scipy.signal import resample_poly
    c = db(ceiling_db)
    up = np.abs(resample_poly(x, 4, 1, axis=0)).max(axis=1)
    pk = up.reshape(-1, 4).max(axis=1)[: len(x)]
    need = np.minimum(1.0, c / np.maximum(pk, 1e-9))
    # smooth the gain: instant attack via a running minimum over 5 ms, 80 ms release
    w = int(0.005 * SR)
    from scipy.ndimage import minimum_filter1d
    g = minimum_filter1d(need, size=2 * w + 1)
    rel = 1 - np.exp(-1 / (0.08 * SR))
    out = np.empty_like(g)
    cur = 1.0
    for i in range(0, len(g), 32):
        blk = g[i:i + 32].min()
        cur = blk if blk < cur else cur + (blk - cur) * (1 - (1 - rel) ** 32)
        out[i:i + 32] = cur
    return x * out[:, None]


def main():
    music = music_edit()
    v, active = voice_track()
    gain = duck_curve(active)
    bed = music * gain[:, None]
    sfx = sfx_track()
    vo2 = np.stack([v, v], 1)
    for name, x in [("music-bed", bed), ("voice", vo2), ("sfx", sfx)]:
        save(os.path.join(STEMS, name + ".wav"), x)
    # the bed measured where the voice speaks and where it rests
    spk = active > 0.5
    def seg_lufs(x, mask):
        idx = np.flatnonzero(mask)
        return lufs_of(x[idx]) if len(idx) > SR else None
    full = vo2 + bed + sfx
    novo = bed / gain[:, None] * db(BED_OPEN) + sfx  # no voice: the bed never ducks
    # master to about -16 LUFS integrated, then limit true peaks under -1 dBTP
    gains = {}
    for name, x, target in [("mix-film", full, -16.0), ("mix-film-novo", novo, -17.0)]:
        g = gains[name] = db(target - lufs_of(x))
        y = limiter(x * g)
        path = os.path.join(OUT, name + ".wav")
        save(path, y)
        I, TP, LRA = ebur(path)
        print(f"{name}: integrated {I} LUFS, true peak {TP} dBTP, range {LRA} LU")
    g = gains["mix-film"]
    I_v = lufs_of(vo2 * g)
    print(f"voice alone (in the master): {I_v:.1f} LUFS")
    a, b = seg_lufs(bed * g, spk), seg_lufs(bed * g, ~spk)
    print(f"music under speech: {a:.1f} LUFS, in the breaths: {b:.1f} LUFS (voice to bed {I_v - a:.1f} LU)")


if __name__ == "__main__":
    main()
