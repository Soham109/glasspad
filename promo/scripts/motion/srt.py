"""Subtitles for the motion film (out/glasspad-motion.srt), from the voice placements in
src/motion/edit.json: one cue per line, never overlapping.
  python3 -I scripts/motion/srt.py"""
import json, os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
E = json.load(open(os.path.join(ROOT, "src/motion/edit.json")))
M = json.load(open(os.path.join(ROOT, "src/motion/vo-measured.json")))
def ts(t):
    ms = int(round(t * 1000)); h, ms = divmod(ms, 3600000); m, ms = divmod(ms, 60000); s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"
vo = sorted(E["vo"], key=lambda v: v["at"])
out = []
for i, v in enumerate(vo):
    a = v["at"]; b = a + M[v["id"]]["dur"] + 0.5
    if i + 1 < len(vo): b = min(b, vo[i + 1]["at"] - 0.05)
    out.append(f"{i + 1}\n{ts(a)} --> {ts(b)}\n{M[v['id']]['text']}\n")
os.makedirs(os.path.join(ROOT, "out"), exist_ok=True)
open(os.path.join(ROOT, "out/glasspad-motion.srt"), "w").write("\n".join(out))
print(len(out), "cues")
