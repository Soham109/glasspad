"""Re-time the edit to the faster voice and the new score.

The picture is authored on the original timeline (edit.json "film"/"teaser" with
vo-measured.json). This writes a time warp from that timeline to the final one:
  - music hits are pinned: each listed picture moment lands on a bar of the new track;
  - inside every voice line the warp runs at that line's own speed-up (vo-fast.json), so each
    word still lands on its picture cue;
  - the gaps between lines take up the rest.
Outputs edit.json keys: grid2, warp.{film,teaser}, audio.{film,teaser} (music segments, voice
placements, duration).  python3 -I scripts/film/build_edit.py
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
P = os.path.join(ROOT, "src/v2/edit.json")
E = json.load(open(P))
OLD = json.load(open(os.path.join(ROOT, "src/v2/vo-measured.json")))
NEW = json.load(open(os.path.join(ROOT, "src/v2/vo-fast.json")))

# "Uplifting Electronic Indie" by WinnieTheMoog: 144.998 BPM, bar 0 at 0.4310 s (fitted, 1.5 ms residual).
GRID = {"offset": 0.4310, "bar": 0.41380 * 4}
B = GRID["bar"]

CUTS = {
    # picture-time hits -> bar positions in the final cut (seconds)
    "film": {
        "hits": [(0.0, 0.0), (8.0, 4 * B), (40.0, 20 * B), (56.0, 28 * B), (59.85, 30 * B), (67.8, 34 * B), (72.0, 37 * B)],
        "end": (74.8, 37 * B + 2.36),
        "music": [  # final-cut start, track bars
            {"at": 0.0, "fromBar": 0, "toBar": 30},
            {"at": 30 * B, "fromBar": 56, "toBar": 60},
            {"at": 34 * B, "fromBar": 96, "toBar": 99, "stop": True},
        ],
    },
    "teaser": {
        "hits": [(0.0, 0.0), (3.97, 2 * B), (12.0, 6 * B), (20.0, 10 * B), (24.0, 12 * B), (28.0, 15 * B)],
        "end": (30.0, 15 * B + 1.67),
        "music": [
            {"at": 0.0, "fromBar": 2, "toBar": 8},
            {"at": 6 * B, "fromBar": 20, "toBar": 24},
            {"at": 10 * B, "fromBar": 58, "toBar": 60},
            {"at": 12 * B, "fromBar": 96, "toBar": 99, "stop": True},
        ],
    },
}

out_warp, out_audio = {}, {}
for cut, spec in CUTS.items():
    hits = spec["hits"] + [spec["end"]]
    lines = [(v["id"], v["at"], v["at"] + OLD[v["id"]]["dur"]) for v in E[cut]["vo"]]
    knots = [(0.0, 0.0)]
    for (h0, H0), (h1, H1) in zip(hits, hits[1:]):
        # pieces of [h0, h1]: line parts scale by their speed-up, gaps share the rest
        pts = sorted({h0, h1, *[t for _, a, b in lines for t in (a, b) if h0 < t < h1]})
        pieces = []
        for a, b in zip(pts, pts[1:]):
            mid = (a + b) / 2
            ln = next((l for l in lines if l[1] <= mid < l[2]), None)
            f = NEW[ln[0]]["dur"] / OLD[ln[0]]["dur"] if ln else None
            pieces.append((a, b, f))
        fixed = sum((b - a) * f for a, b, f in pieces if f)
        gap = sum(b - a for a, b, f in pieces if not f)
        g = (H1 - H0 - fixed) / gap if gap else 1
        assert g > 0.3, (cut, h0, h1, g)
        t = H0
        for a, b, f in pieces:
            t += (b - a) * (f if f else g)
            knots.append((round(b, 4), round(t, 4)))
        print(f"{cut:6s} {h0:6.2f}-{h1:6.2f} -> {H0:6.3f}-{H1:6.3f}  gap factor {g:.2f}")
    # de-duplicate
    k2 = []
    for o, n in knots:
        if not k2 or o > k2[-1][0] + 1e-6:
            k2.append([o, n])
    out_warp[cut] = k2

    def warp(t, k=k2):
        for (o0, n0), (o1, n1) in zip(k, k[1:]):
            if t <= o1:
                return n0 + (t - o0) * (n1 - n0) / (o1 - o0)
        return k[-1][1]

    vo = [{"id": i, "at": round(warp(a), 3)} for i, a, b in lines]
    for x, y in zip(vo, vo[1:]):
        endx = x["at"] + NEW[x["id"]]["dur"]
        assert endx < y["at"], (cut, x, y)
    out_audio[cut] = {"duration": round(spec["end"][1], 3), "music": spec["music"], "vo": vo}
    print(cut, "duration", round(spec["end"][1], 2), "s;", " ".join(f"{v['id']}@{v['at']:.2f}" for v in vo))

E["grid2"] = GRID
E["warp"] = out_warp
E["audio"] = out_audio
E["_"] = ("Timing. 'film'/'teaser' are the picture timelines the scenes are authored on (with "
          "vo-measured.json). 'warp' maps them to the final cut; 'audio' holds the final cut's music "
          "(grid2: the WinnieTheMoog track) and voice placements (vo-fast.json). Built by scripts/film/build_edit.py.")
json.dump(E, open(P, "w"), indent=1)
