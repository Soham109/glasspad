"""Renders the Glasspad wordmark and lockups (icon + wordmark), light and dark, as transparent PNGs.

Text is the site's font (-apple-system, which is SF Pro on a Mac), so render on a Mac.
Usage (repo root): python3 docs/brand/tools/wordmarks.py
"""
import json, pathlib, subprocess, tempfile
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[3]
BRAND = ROOT / "docs/brand"
OUT = BRAND / "wordmark"
ICON = BRAND / "icon/glasspad-icon-mac-1024.png"
FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', Arial, sans-serif"
INK, ON_DARK = "#1A1A1A", "#F2F1EE"
PAD = 40  # px of transparent margin kept around the artwork in each file

def page(color, icon):
    img = f'<img src="{ICON.as_uri()}" style="width:420px;height:420px;margin:0 -12px 0 -40px">' if icon else ""
    return f'''<html><body style="margin:0;background:transparent">
<div style="display:flex;align-items:center;height:700px;padding:0 80px;font-family:{FONT};font-weight:700;
font-size:250px;letter-spacing:-0.035em;color:{color};line-height:1">{img}<span style="padding-bottom:12px">Glasspad</span></div>
</body></html>'''

def main():
    OUT.mkdir(exist_ok=True)
    tmp = pathlib.Path(tempfile.mkdtemp())
    variants = {
        "glasspad-lockup-light": (INK, True), "glasspad-lockup-dark": (ON_DARK, True),
        "glasspad-wordmark-light": (INK, False), "glasspad-wordmark-dark": (ON_DARK, False),
    }
    jobs = []
    for name, (color, icon) in variants.items():
        (tmp / f"{name}.html").write_text(page(color, icon))
        jobs.append({"in": str(tmp / f"{name}.html"), "out": str(tmp / f"{name}.png"), "w": 1800, "h": 700, "transparent": True})
    (tmp / "jobs.json").write_text(json.dumps(jobs))
    subprocess.run(["node", "docs/brand/tools/shoot.mjs", str(tmp / "jobs.json")], cwd=ROOT, check=True)
    for name in variants:
        im = Image.open(tmp / f"{name}.png").convert("RGBA")
        box = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
        im = im.crop(box)
        canvas = Image.new("RGBA", (im.width + 2 * PAD, im.height + 2 * PAD), (0, 0, 0, 0))
        canvas.paste(im, (PAD, PAD))
        canvas.save(OUT / f"{name}.png", optimize=True)
        print(name, canvas.size)

main()
