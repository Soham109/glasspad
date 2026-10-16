"""Checks a render of the motion film by eye and by numbers:
  python3 -I scripts/motion/check.py out/glasspad-motion.mp4 [out dir]
- contact sheets, one frame every 0.25 s (24 a page, time labelled): <dir>/sheetNN.jpg
- pops: frames whose change from the last frame is far larger than the change around them
  (a jump, a flash, a missing frame), listed with their time
- holds: stretches longer than 2 s where nothing on screen moves
"""
import os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw

src = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(src), "motion-sheets")
os.makedirs(out, exist_ok=True)
fps = 60

# frame differences at a small size, every frame
w, h = 192, 108
raw = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", src, "-vf", f"scale={w}:{h},format=gray", "-f", "rawvideo", "-"], capture_output=True, check=True).stdout
fr = np.frombuffer(raw, np.uint8).reshape(-1, h, w).astype(np.float32)
d = np.abs(np.diff(fr, axis=0)).mean(axis=(1, 2))
print(f"{len(fr)} frames")
pops = []
for i in range(2, len(d) - 2):
    around = np.median(np.r_[d[max(0, i - 6):i], d[i + 1:i + 7]])
    if d[i] > 1.2 and d[i] > 4 * max(around, 0.15):
        pops.append((i + 1, d[i], around))
print("pops (frame, time, change, around):")
for f, v, a in pops: print(f"  {f:5d} {f / fps:7.3f}s  {v:6.2f}  {a:5.2f}")
still = d < 0.02
holds, run = [], 0
for i, s in enumerate(still):
    run = run + 1 if s else 0
    if run == int(2 * fps): holds.append((i + 1 - run) / fps)
print("holds over 2 s start at:", ", ".join(f"{t:.2f}s" for t in holds) or "none")

# contact sheets
tmp = os.path.join(out, "_f"); os.makedirs(tmp, exist_ok=True)
for f in os.listdir(tmp): os.remove(os.path.join(tmp, f))
subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", src, "-vf", "fps=4,scale=480:-2", os.path.join(tmp, "f%05d.jpg")], check=True)
fs = sorted(os.listdir(tmp)); cols, per = 4, 24
for p in range(0, len(fs), per):
    page = fs[p:p + per]; rows = (len(page) + cols - 1) // cols
    S = Image.new("RGB", (cols * 484, rows * 274), (60, 60, 60))
    for i, f in enumerate(page):
        im = Image.open(os.path.join(tmp, f)).convert("RGB"); t = (p + i) * 0.25
        dd = ImageDraw.Draw(im); dd.rectangle([0, 0, 64, 15], fill=(0, 0, 0)); dd.text((3, 2), f"{t:.2f}s", fill=(255, 220, 0))
        S.paste(im, ((i % cols) * 484, (i // cols) * 274))
    S.save(os.path.join(out, f"sheet{p // per + 1:02d}.jpg"), quality=84)
for f in fs: os.remove(os.path.join(tmp, f))
os.rmdir(tmp)
print(f"{(len(fs) + per - 1) // per} sheets in {out}")
