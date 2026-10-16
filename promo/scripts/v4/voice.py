"""The v4 film voice: one ElevenLabs take per line (cached), trimmed to its speech with a
short natural pad, measured. A line the voice reads faster than 155 words a minute is eased
to about 150 with a pitch preserving tempo change (never more than 12% slower, never faster);
everything else keeps the voice's own pace.

  python3 -I scripts/v4/voice.py [id=seed ...]
Writes public/v4/vo/<id>.wav (48 kHz mono) and src/v4/vo-measured.json: duration, word times,
words a minute over the spoken part, loudness, pitch movement. The key is read from promo/.env
by scripts/film/eleven.py and never printed.
"""
import json, os, subprocess, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "film"))
import eleven, measure

VOICE, MODEL = "EXAVITQu4vr4xnSDxMaL", "eleven_v4"  # Sarah, as the v3 film
SETTINGS = dict(stability=0.5, similarity_boost=0.75, style=0.0, use_speaker_boost=True)
ROOT = eleven.ROOT
lines = json.load(open(os.path.join(ROOT, "src/v4/vo-lines.json")))
seeds = dict(a.split("=") for a in sys.argv[1:])
out = os.path.join(ROOT, "public/v4/vo")
os.makedirs(out, exist_ok=True)
result = {}
for i, ln in enumerate(lines):
    ctx = ln.get("context", True)
    prev = lines[i - 1]["text"] if i and ctx else None
    nxt = lines[i + 1]["text"] if i + 1 < len(lines) and ctx else None
    seed = int(seeds[ln["id"]]) if ln["id"] in seeds else ln.get("seed")
    mp3, meta = eleven.tts(VOICE, MODEL, ln["text"], SETTINGS, previous_text=prev, next_text=nxt, seed=seed)
    al = meta["alignment"]
    words, cur, st, last = [], "", None, None
    for c, s, e in zip(al["characters"], al["character_start_times_seconds"], al["character_end_times_seconds"]):
        if c == " ":
            if cur:
                words.append(dict(w=cur, s=st, e=last)); cur = ""
            continue
        if not cur:
            st = s
        cur += c; last = e
    if cur:
        words.append(dict(w=cur, s=st, e=last))
    rep = measure.report(mp3, al)
    a = max(0.0, rep["lead"] - 0.06)
    b = rep["dur"] - max(0.0, rep["tail"] - 0.25)
    wav = os.path.join(out, ln["id"] + ".wav")
    raw_wpm = len(words) / (words[-1]["e"] - words[0]["s"]) * 60
    tempo = max(0.88, min(1.0, 150 / raw_wpm)) if raw_wpm > 155 else 1.0
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", mp3, "-af",
                    f"atrim={a:.3f}:{b:.3f},asetpts=PTS-STARTPTS,atempo={tempo:.4f},afade=t=in:d=0.02,"
                    f"afade=t=out:st={(b - a) / tempo - 0.08:.3f}:d=0.08",
                    "-ar", "48000", "-ac", "1", wav], check=True)
    for w in words:
        w["s"] = round((w["s"] - a) / tempo, 3); w["e"] = round((w["e"] - a) / tempo, 3)
    b = a + (b - a) / tempo
    spoken = words[-1]["e"] - words[0]["s"]
    wpm = round(len(words) / spoken * 60, 1)
    result[ln["id"]] = dict(text=ln["text"], dur=round(b - a, 3), words=words, wpm=wpm, lufs=rep["lufs"],
                            pitch_sd=rep["sd_st"], pauses=rep["pauses"], tempo=round(tempo, 3))
    print(f'{ln["id"]:10s} {b - a:5.2f}s  {wpm:5.1f} wpm  tempo {tempo:.3f}  lufs {rep["lufs"]}  pitch sd {rep["sd_st"]}  pauses {rep["pauses"]}')
json.dump(result, open(os.path.join(ROOT, "src/v4/vo-measured.json"), "w"), indent=1)
