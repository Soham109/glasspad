"""Prepares the stock footage for compositing (run after scripts/fetch-footage.sh).

For each clip in CLIPS it writes public/footage/<name>/:
  track.json   (also src/v4/tracks/<name>.json) the screen's four corners in every frame (source pixels), plus the clip's facts
  fg.mov       ProRes 4444, cropped around the screen: the footage with the green screen keyed
               out (hands, bezels and fingers stay opaque), green spill removed. The film puts
               the app under this layer, so real fingers pass over the real app.
  key.jpg      one frame with the tracked corners drawn, to check the track by eye

  ~/Library/Caches/glasspad-film-venv/bin/python -I scripts/v4/footage.py [name ...]
Needs opencv-python-headless and numpy (the film venv), and ffmpeg.

The screen is found as the largest green region; its outline is simplified and the four
longest sides are intersected, so rounded corners and fingers over an edge do not pull the
corners in. Corners are then smoothed over time (a short median, then a light low-pass),
because a track that shivers by one pixel reads as fake at once.
"""
import json, os, subprocess, sys
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "public/footage/src")
OUT = os.path.join(ROOT, "public/footage")

# name: first corner = the screen's top left as the app is drawn (index into the clockwise
# corners, starting from the one nearest the frame's top left); `screens` > 1 for two screens.
# inside: what to do with non-green pixels inside the tracked screen. Tracking markers on the
# screen must go; fingers over the screen must stay.
#   "key"      only the green key (nothing but green sits on the screen)
#   "clear"    everything inside goes (markers, and no hand ever crosses the screen)
#   "neutral"  grey, black and white pixels inside go (markers), coloured ones (skin) stay
CLIPS = {
    "desk-topdown": dict(inside="key"),
    "couch-phone": dict(inside="neutral"),
    "focus-laptop": dict(inside="clear"),
    "handoff": dict(inside="key"),
    "two-screens": dict(inside="clear", screens=2),
    "edit-suite": dict(inside="clear"),
    "hands-phone": dict(inside="neutral", whole_frame_green=True),
}


def green_alpha(bgr):
    """Foreground alpha (1 = keep) from how much green dominates, soft at the edges."""
    f = bgr.astype(np.float32)
    b, g, r = f[..., 0], f[..., 1], f[..., 2]
    d = g - np.maximum(r, b)  # green excess, 0..255
    # Keep anything with little green excess; drop clear green. The ramp is the soft edge.
    a = 1.0 - np.clip((d - 18.0) / 40.0, 0, 1)
    return a


def despill(bgr):
    f = bgr.astype(np.float32)
    b, g, r = f[..., 0], f[..., 1], f[..., 2]
    lim = np.maximum(r, b) * 1.02
    g2 = np.minimum(g, lim)
    return np.stack([b, g2, r], -1).clip(0, 255).astype(np.uint8)


def line_through(p, q):
    a = np.array([p[0], p[1], 1.0]); b = np.array([q[0], q[1], 1.0])
    return np.cross(a, b)


def quad_from_mask(mask):
    """Four corners of the largest blob in `mask` (uint8), clockwise from the top left."""
    cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not cnts:
        return None
    c = max(cnts, key=cv2.contourArea)
    if cv2.contourArea(c) < 2000:
        return None
    hull = cv2.convexHull(c)
    peri = cv2.arcLength(hull, True)
    for eps in (0.006, 0.01, 0.015, 0.02, 0.03):
        poly = cv2.approxPolyDP(hull, eps * peri, True).reshape(-1, 2).astype(np.float64)
        if len(poly) >= 4:
            break
    n = len(poly)
    edges = [(i, np.linalg.norm(poly[(i + 1) % n] - poly[i])) for i in range(n)]
    longest = sorted(sorted(edges, key=lambda e: -e[1])[:4], key=lambda e: e[0])
    lines = [line_through(poly[i], poly[(i + 1) % n]) for i, _ in longest]
    pts = []
    for k in range(4):
        x = np.cross(lines[k], lines[(k + 1) % 4])
        if abs(x[2]) < 1e-9:
            return None
        pts.append(x[:2] / x[2])
    pts = np.array(pts)
    # sanity: the corners must stay near the blob
    x0, y0, w, h = cv2.boundingRect(c)
    if (pts[:, 0].min() < x0 - 0.2 * w or pts[:, 0].max() > x0 + 1.2 * w or
            pts[:, 1].min() < y0 - 0.2 * h or pts[:, 1].max() > y0 + 1.2 * h):
        return None
    return order(pts)


def order(pts):
    """Clockwise (in image coordinates), starting from the corner nearest the top left."""
    c = pts.mean(0)
    ang = np.arctan2(pts[:, 1] - c[1], pts[:, 0] - c[0])
    pts = pts[np.argsort(ang)]
    i = int(np.argmin(pts[:, 0] + pts[:, 1]))
    return np.roll(pts, -i, axis=0)


def smooth(track):
    """Fill gaps, 5 frame median, then a zero phase low-pass on every coordinate."""
    T = len(track)
    arr = np.full((T, 8), np.nan)
    for i, q in enumerate(track):
        if q is not None:
            arr[i] = np.asarray(q).reshape(-1)
    for j in range(8):
        col = arr[:, j]
        ok = ~np.isnan(col)
        if ok.sum() == 0:
            return None
        col[~ok] = np.interp(np.flatnonzero(~ok), np.flatnonzero(ok), col[ok])
        med = np.array([np.median(col[max(0, i - 2):i + 3]) for i in range(T)])
        k = np.exp(-0.5 * (np.arange(-6, 7) / 2.2) ** 2); k /= k.sum()
        pad = np.pad(med, 6, mode="edge")
        arr[:, j] = np.convolve(pad, k, mode="valid")
    return arr


def process(name, cfg):
    src = os.path.join(SRC, name + ".mp4")
    out = os.path.join(OUT, name)
    os.makedirs(out, exist_ok=True)
    cap = cv2.VideoCapture(src)
    fps = cap.get(cv2.CAP_PROP_FPS)
    W = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)); H = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    screens = cfg.get("screens", 1)
    tracks = [[] for _ in range(screens)]
    T, mid = 0, None
    while True:
        ok, fr = cap.read()
        if not ok:
            break
        T += 1
        if T == 40:
            mid = fr.copy()
        a = green_alpha(fr)
        m = (a < 0.5).astype(np.uint8) * 255
        if cfg.get("whole_frame_green"):
            # Green behind the phone too: the screen is the green region inside the phone's
            # dark outline, so take the green blobs that do not touch the frame edge.
            n, lab, st, _ = cv2.connectedComponentsWithStats(m)
            keep = np.zeros_like(m)
            for k in range(1, n):
                x, y, w, h, area = st[k]
                if x > 2 and y > 2 and x + w < W - 2 and y + h < H - 2 and area > 5000:
                    keep[lab == k] = 255
            m = keep
        m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (41, 41)))
        if screens == 1:
            tracks[0].append(quad_from_mask(m))
        else:
            n, lab, st, _ = cv2.connectedComponentsWithStats(m)
            blobs = sorted(range(1, n), key=lambda k: -st[k][4])[:screens]
            blobs = sorted(blobs, key=lambda k: -st[k][4])  # biggest first
            for s in range(screens):
                if s < len(blobs):
                    tracks[s].append(quad_from_mask(((lab == blobs[s]) * 255).astype(np.uint8)))
                else:
                    tracks[s].append(None)
    cap.release()
    sm = [smooth(t) for t in tracks]
    # Crop for the foreground layer: every screen in every frame, with a margin for hands.
    allp = np.concatenate([s.reshape(-1, 2) for s in sm if s is not None])
    mx = int(0.06 * W)
    x0 = max(0, int(allp[:, 0].min()) - mx); x1 = min(W, int(allp[:, 0].max()) + mx)
    y0 = max(0, int(allp[:, 1].min()) - mx); y1 = min(H, int(allp[:, 1].max()) + mx)
    if cfg.get("whole_frame_green"):
        x0, y0, x1, y1 = 0, 0, W, H  # the whole frame is keyed: hands go onto the film's own set
    x0 -= x0 % 2; y0 -= y0 % 2; x1 -= (x1 - x0) % 2; y1 -= (y1 - y0) % 2
    cw, ch = x1 - x0, y1 - y0
    enc = subprocess.Popen(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgra",
                            "-s", f"{cw}x{ch}", "-r", f"{fps}", "-i", "-", "-c:v", "prores_ks", "-profile:v", "4444",
                            "-pix_fmt", "yuva444p10le", "-alpha_bits", "16", "-vendor", "apl0",
                            os.path.join(out, "fg.mov")], stdin=subprocess.PIPE)
    cap = cv2.VideoCapture(src)  # second pass: 4K frames are too big to keep in memory
    inside = cfg.get("inside", "key")
    fi = -1
    while True:
        ok, fr = cap.read()
        if not ok:
            break
        fi += 1
        c = fr[y0:y1, x0:x1]
        a = green_alpha(c)
        if inside != "key":
            poly = np.zeros(a.shape, np.uint8)
            for sc in sm:
                if sc is None:
                    continue
                q = sc[fi].reshape(4, 2) - [x0, y0]
                q = q.mean(0) + (q - q.mean(0)) * 0.985  # stay just inside the bezel
                cv2.fillPoly(poly, [np.round(q).astype(np.int32)], 1)
            if inside == "clear":
                a[poly == 1] = 0
            else:
                hsv = cv2.cvtColor(c, cv2.COLOR_BGR2HSV)
                neutral = (hsv[..., 1] < 70)  # saturation under ~27%: black, grey, white
                a[(poly == 1) & neutral] = 0
        # Shrink the matte a hair so no green fringe survives on the bezel edge.
        a = cv2.erode(a, np.ones((3, 3), np.uint8))
        a = cv2.GaussianBlur(a, (3, 3), 0)
        # Spill is removed only near the key (bezel edges, fingertips): elsewhere the crop must
        # stay identical to the plate under it, or its border would show.
        near = cv2.dilate((a < 0.98).astype(np.uint8), np.ones((25, 25), np.uint8)).astype(bool)
        rgb = c.copy()
        rgb[near] = despill(c)[near]
        bgra = np.dstack([rgb, (a * 255).astype(np.uint8)])
        enc.stdin.write(bgra.tobytes())
    enc.stdin.close(); enc.wait(); cap.release()
    for s in sm:
        if s is None:
            continue
        q = s[39].reshape(4, 2).astype(int)
        cv2.polylines(mid, [q], True, (0, 0, 255), 6)
        for i, p in enumerate(q):
            cv2.putText(mid, str(i), tuple(p), cv2.FONT_HERSHEY_SIMPLEX, 3, (0, 0, 255), 6)
    cv2.imwrite(os.path.join(out, "key.jpg"), cv2.resize(mid, (W // 3, H // 3)))
    info = dict(src=f"footage/src/{name}.mp4", fg=f"footage/{name}/fg.mov", fps=fps, w=W, h=H, frames=T,
                crop=[x0, y0, cw, ch],
                screens=[None if s is None else np.round(s, 2).tolist() for s in sm])
    json.dump(info, open(os.path.join(out, "track.json"), "w"))
    # The film reads the track from src (small, committed); the clips themselves stay out of git.
    os.makedirs(os.path.join(ROOT, "src/v4/tracks"), exist_ok=True)
    json.dump(info, open(os.path.join(ROOT, "src/v4/tracks", name + ".json"), "w"))
    print(f"{name}: {T} frames at {fps:.3f} fps, crop {cw}x{ch}, screens {screens}")


if __name__ == "__main__":
    names = sys.argv[1:] or list(CLIPS)
    for n in names:
        process(n, CLIPS[n])
