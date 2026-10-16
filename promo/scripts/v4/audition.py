"""Tries seeds for chosen lines and prints each take's pace and pitch movement, to pick the
most natural take (140 to 155 words a minute, lively pitch, no clipped end).
  python3 -I scripts/v4/audition.py 1,2,3 <id> [<id> ...]
Takes are cached (scripts/film/eleven.py), so the chosen one costs nothing when voice.py runs
with its seed. Put the chosen seed in src/v4/vo-lines.json as "seed"."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "film"))
import eleven, measure

VOICE, MODEL = "EXAVITQu4vr4xnSDxMaL", "eleven_v4"
SETTINGS = dict(stability=0.5, similarity_boost=0.75, style=0.0, use_speaker_boost=True)
lines = json.load(open(os.path.join(eleven.ROOT, "src/v4/vo-lines.json")))
idx = {ln["id"]: i for i, ln in enumerate(lines)}
seeds = [int(x) for x in sys.argv[1].split(",")]
for lid in sys.argv[2:]:
    i = idx[lid]
    prev = lines[i - 1]["text"] if i else None
    nxt = lines[i + 1]["text"] if i + 1 < len(lines) else None
    for seed in seeds:
        mp3, meta = eleven.tts(VOICE, MODEL, lines[i]["text"], SETTINGS, previous_text=prev, next_text=nxt, seed=seed)
        al = meta["alignment"]
        st = al["character_start_times_seconds"]; en = al["character_end_times_seconds"]
        n = len(lines[i]["text"].split())
        rep = measure.report(mp3, al)
        wpm = n / (en[-1] - st[0]) * 60
        print(f"{lid:10s} seed {seed:3d}  {wpm:5.1f} wpm  pitch sd {rep['sd_st']}  range {rep['range_st']}  pauses {rep['pauses']}  end {rep['end_db']}  {os.path.basename(mp3)}")
