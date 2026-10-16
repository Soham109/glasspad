"""Finds the touch dots the app draws in the trackpad recording, frame by frame, so the film's
rings sit exactly on the app's own dots.
  ~/Library/Caches/glasspad-film-venv/bin/python -I scripts/v4/touches.py
Reads public/v4/phone/trackpad.mp4; writes src/v4/tracks/trackpad-touches.json:
{ fps, frames: [[[u, v], ...], ...] } with u, v in 0..1 of the screen."""
import json, os
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
src = os.path.join(ROOT, "public/v4/phone/trackpad.mp4")
cap = cv2.VideoCapture(src)
frames = []
while True:
    ok, f = cap.read()
    if not ok:
        break
    frames.append(cv2.cvtColor(f, cv2.COLOR_BGR2GRAY))
cap.release()
st = np.stack(frames[::10])
bg = np.median(st, axis=0).astype(np.int16)
H, W = frames[0].shape
out = []
for i, f in enumerate(frames):
    if i < 3.0 * 60:  # the app is still launching
        out.append([]); continue
    d = np.abs(f.astype(np.int16) - bg).astype(np.uint8)
    d = cv2.GaussianBlur(d, (9, 9), 0)
    _, b = cv2.threshold(d, 10, 255, cv2.THRESH_BINARY)
    b[: int(0.08 * H)] = 0  # the status dot and the mode pill
    n, lab, stt, cen = cv2.connectedComponentsWithStats(b)
    pts = []
    for k in range(1, n):
        x, y, w, h, area = stt[k]
        if 400 < area < 60000 and 0.5 < w / max(1, h) < 2.0:
            pts.append([round(float(cen[k][0]) / W, 4), round(float(cen[k][1]) / H, 4)])
    out.append(pts)
json.dump(dict(fps=60, frames=out), open(os.path.join(ROOT, "src/v4/tracks/trackpad-touches.json"), "w"))
counts = [len(p) for p in out]
print(len(out), "frames;", "first touch", next((i / 60 for i, c in enumerate(counts) if c), None), "s; most fingers", max(counts))
# a lone frame or two is the launch, not a finger: dropped
i = 0
while i < len(out):
    if out[i]:
        j = i
        while j + 1 < len(out) and out[j + 1]: j += 1
        if j - i < 2:
            for k in range(i, j + 1): out[k] = []
        i = j + 1
    else:
        i += 1
json.dump(dict(fps=60, frames=out), open(os.path.join(ROOT, "src/v4/tracks/trackpad-touches.json"), "w"))
# the gestures, as runs of frames with the same number of fingers
runs, cur = [], None
for i, p in enumerate(out):
    c = len(p)
    if cur and cur[0] == c and i - cur[2] <= 2: cur[2] = i
    else:
        if cur and cur[0]: runs.append(cur)
        cur = [c, i, i]
if cur and cur[0]: runs.append(cur)
for c, a, b in runs: print(f"{c} finger(s) {a/60:5.2f} to {b/60:5.2f} s")
