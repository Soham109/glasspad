"""Generate the film voice line by line (cached), trim each to its speech with a short
natural pad, and write public/v2/vo/<id>.wav plus src/v2/vo-measured.json (durations,
word timings, loudness). Usage: python3 -I scripts/film/make_voice.py [id=seed ...]"""
import json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eleven, measure

VOICE, MODEL = "EXAVITQu4vr4xnSDxMaL", "eleven_v4"   # Sarah; see SCRIPT.md / report
SETTINGS = dict(stability=0.5, similarity_boost=0.75, style=0.0, use_speaker_boost=True)
ROOT = eleven.ROOT
lines = json.load(open(os.path.join(ROOT, "src/v2/vo-lines.json")))
seeds = dict(a.split("=") for a in sys.argv[1:])
out = os.path.join(ROOT, "public/v2/vo"); os.makedirs(out, exist_ok=True)
result = {}
for i, ln in enumerate(lines):
    ctx = ln.get("context", True)  # some lines get truncated by the model when given context
    prev = lines[i - 1]["text"] if i and ctx else None
    nxt = lines[i + 1]["text"] if i + 1 < len(lines) and ctx else None
    seed = int(seeds[ln["id"]]) if ln["id"] in seeds else None
    mp3, meta = eleven.tts(VOICE, MODEL, ln["text"], SETTINGS, previous_text=prev, next_text=nxt, seed=seed)
    al = meta["alignment"]
    # words with times from the character alignment
    words, cur, st = [], "", None
    for c, s, e in zip(al["characters"], al["character_start_times_seconds"], al["character_end_times_seconds"]):
        if c == " ":
            if cur: words.append(dict(w=cur, s=st, e=last)); cur = ""
            continue
        if not cur: st = s
        cur += c; last = e
    if cur: words.append(dict(w=cur, s=st, e=last))
    rep = measure.report(mp3, al)
    # trim: keep 60 ms before speech, 220 ms after (room for the release), fade the edges
    a = max(0.0, rep["lead"] - 0.06)
    b = rep["dur"] - max(0.0, rep["tail"] - 0.22)
    wav = os.path.join(out, ln["id"] + ".wav")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", mp3, "-af",
                    f"atrim={a:.3f}:{b:.3f},asetpts=PTS-STARTPTS,afade=t=in:d=0.02,afade=t=out:st={b - a - 0.06:.3f}:d=0.06",
                    "-ar", "48000", "-ac", "1", wav], check=True)
    for w in words: w["s"] = round(w["s"] - a, 3); w["e"] = round(w["e"] - a, 3)
    result[ln["id"]] = dict(text=ln["text"], dur=round(b - a, 3), words=words, raw=rep)
    print(f'{ln["id"]:9s} {b - a:5.2f}s  lufs {rep["lufs"]}  end_db {rep["end_db"]}  tail {rep["tail"]}  sd {rep["sd_st"]}  wps {rep["wps"]}')
json.dump(result, open(os.path.join(ROOT, "src/v2/vo-measured.json"), "w"), indent=1)
