"""Checks the v4 timing: voice lines never overlap, each has a breath before the next, each
reads at a natural pace, and each sits inside its scene. Prints a table; exits 1 on a problem.
  python3 -I scripts/v4/verify.py"""
import json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
E = json.load(open(os.path.join(ROOT, "src/v4/edit.json")))
M = json.load(open(os.path.join(ROOT, "src/v4/vo-measured.json")))
B = E["bar"]
scenes = [(s["id"], s["from"] * B, s["to"] * B) for s in E["scenes"]]
owner = {"open": "open", "actions1": "actions", "actions2": "actions", "pinned1": "pinned", "pinned2": "pinned",
         "layouts": "layouts", "edit": "edit", "present": "present", "remote1": "remote", "remote2": "remote",
         "clipboard": "clipboard", "displays": "displays", "more1": "more", "more2": "more", "private": "private", "end": "end"}
vo = sorted(E["vo"], key=lambda v: v["at"])
bad = 0
print(f"{'line':10s} {'start':>7s} {'end':>7s} {'wpm':>6s} {'breath':>7s}  scene")
for i, v in enumerate(vo):
    a = v["at"]; b = a + M[v["id"]]["dur"]; wpm = M[v["id"]]["wpm"]
    gap = vo[i + 1]["at"] - b if i + 1 < len(vo) else None
    sid = owner[v["id"]]; s0, s1 = next((x, y) for n, x, y in scenes if n == sid)
    notes = []
    if gap is not None and gap < 0.5: notes.append("no breath"); bad += 1
    if wpm > 160: notes.append("fast"); bad += 1
    if a < s0 or b > s1 + 0.6: notes.append(f"outside {sid} ({s0:.2f} to {s1:.2f})"); bad += 1
    print(f"{v['id']:10s} {a:7.2f} {b:7.2f} {wpm:6.1f} {('' if gap is None else f'{gap:7.2f}'):>7s}  {sid} {' '.join(notes)}")
total_words = sum(len(M[v['id']]['words']) for v in vo)
print(f"{total_words} words in {E['duration']:.1f} s ({total_words / E['duration'] * 60:.0f} words a minute overall)")
sys.exit(1 if bad else 0)
