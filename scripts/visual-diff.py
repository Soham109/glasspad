#!/usr/bin/env python3
"""Compares a folder of screenshots with a baseline folder.

A pixel counts as changed when any channel moved more than the fuzz (3% by default, like
ImageMagick's `compare -metric AE -fuzz 3%`). A screen counts as changed when the share of
changed pixels is over its allowance. For each changed, new or missing screen it writes a side
by side picture (baseline, now, changes in red; the Dynamic Island area is ignored) to <out>/diff/, and a summary to <out>/report.md.

Usage: visual-diff.py <baseline dir> <current dir> <out dir> [--allow name=percent ...]
                      [--default 0.3] [--fuzz 3]
Exit 0 when nothing changed beyond its allowance, 1 otherwise. Needs Pillow.
"""
import argparse
import os
import sys

from PIL import Image, ImageChops, ImageDraw


IGNORE_ISLAND = True


def changed_share(a, b, fuzz):
    if a.size != b.size:
        return 1.0, None
    diff = ImageChops.difference(a.convert("RGB"), b.convert("RGB"))
    # Largest channel difference per pixel, then a mask of those over the fuzz.
    r, g, bl = diff.split()
    biggest = ImageChops.lighter(ImageChops.lighter(r, g), bl)
    limit = int(round(255 * fuzz / 100))
    mask = biggest.point(lambda v: 255 if v > limit else 0)
    # The Dynamic Island: the connection Live Activity shows there or not depending on timing,
    # so that area never counts.
    w, h = mask.size
    island = None
    if IGNORE_ISLAND:
        island = (int(w * 0.3), 0, int(w * 0.7), int(h * 0.06)) if h > w else (0, int(h * 0.3), int(w * 0.06), int(h * 0.7))
    if island:
        ImageDraw.Draw(mask).rectangle(island, fill=0)
    hist = mask.histogram()
    changed = hist[255]
    return changed / (a.size[0] * a.size[1]), mask


def side_by_side(base, cur, mask, path, title):
    h = 900
    def fit(im):
        if im is None:
            return Image.new("RGB", (int(h * 0.46), h), (60, 60, 60))
        return im.convert("RGB").resize((max(1, int(im.size[0] * h / im.size[1])), h))
    a, b = fit(base), fit(cur)
    if mask is not None and cur is not None:
        red = Image.new("RGB", cur.size, (255, 0, 0))
        shown = Image.composite(red, cur.convert("RGB").point(lambda v: v // 3), mask)
        c = fit(shown)
    else:
        c = Image.new("RGB", b.size, (60, 60, 60))
    gap = 16
    out = Image.new("RGB", (a.size[0] + b.size[0] + c.size[0] + gap * 4, h + 80), (24, 24, 24))
    d = ImageDraw.Draw(out)
    x = gap
    for im, label in ((a, "baseline"), (b, "now"), (c, "changed pixels")):
        out.paste(im, (x, 44))
        d.text((x, 14), label, fill=(230, 230, 230))
        x += im.size[0] + gap
    d.text((gap, h + 54), title, fill=(255, 200, 120))
    out.save(path)


def main():
    # `visual-diff.py --same a.png b.png`: exit 0 when the two are alike (used to wait until a
    # screen stops moving before keeping it).
    if sys.argv[1:2] == ["--same"]:
        share, _ = changed_share(Image.open(sys.argv[2]), Image.open(sys.argv[3]), 3)
        return 0 if share < 0.0005 else 1
    ap = argparse.ArgumentParser()
    ap.add_argument("baseline")
    ap.add_argument("current")
    ap.add_argument("out")
    ap.add_argument("--allow", action="append", default=[])
    ap.add_argument("--default", type=float, default=0.3)
    ap.add_argument("--fuzz", type=float, default=3)
    ap.add_argument("--current-only", action="store_true", help="skip baseline screens not taken this time")
    ap.add_argument("--no-island", action="store_true", help="Mac pictures: compare the whole picture")
    o = ap.parse_args()
    global IGNORE_ISLAND
    IGNORE_ISLAND = not o.no_island
    allow = {}
    for a in o.allow:
        k, v = a.split("=")
        allow[k] = float(v)
    os.makedirs(os.path.join(o.out, "diff"), exist_ok=True)
    base = {f for f in os.listdir(o.baseline) if f.endswith(".png")} if os.path.isdir(o.baseline) else set()
    cur = {f for f in os.listdir(o.current) if f.endswith(".png")}
    if o.current_only:
        base &= cur
    rows, bad = [], 0
    for f in sorted(base | cur):
        name = f[:-4]
        screen = name.split("@")[0]
        # An allowance names a screen, or the start of the names of several (Mac pictures).
        limit = allow.get(screen, next((v for k, v in allow.items() if screen.startswith(k)), o.default))
        b = Image.open(os.path.join(o.baseline, f)) if f in base else None
        c = Image.open(os.path.join(o.current, f)) if f in cur else None
        if b is None or c is None:
            status, share, mask = ("new" if b is None else "missing"), None, None
        else:
            share, mask = changed_share(b, c, o.fuzz)
            status = "changed" if share * 100 > limit else "same"
        if status != "same":
            bad += 1
            pic = os.path.join(o.out, "diff", f)
            side_by_side(b, c, mask, pic, f"{name}: {status}" + (f" {share * 100:.2f}%" if share is not None else ""))
            rows.append((name, status, share, limit, pic))
    with open(os.path.join(o.out, "report.md"), "w") as fh:
        fh.write(f"# Visual check\n\nbaseline: {o.baseline}\nnow: {o.current}\n\n")
        fh.write(f"{len(cur)} screens taken, {bad} changed beyond their allowance.\n\n")
        for name, status, share, limit, pic in rows:
            amount = f"{share * 100:.2f}% of pixels (allowed {limit}%)" if share is not None else ""
            fh.write(f"- {name}: {status} {amount}\n  {pic}\n")
    for name, status, share, limit, pic in rows:
        amount = f" {share * 100:.2f}%" if share is not None else ""
        print(f"{status:8} {name}{amount}  {pic}")
    print(f"visual: {len(cur)} screens, {bad} changed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
