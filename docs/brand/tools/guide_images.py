"""Draws docs/brand/palette.png and docs/brand/clear-space.png with Pillow (SF Pro from macOS).
Usage (repo root): python3 docs/brand/tools/guide_images.py   (after wordmarks.py)
"""
import pathlib
from PIL import Image, ImageDraw, ImageFont

B = pathlib.Path(__file__).resolve().parents[1]

def font(size, weight):
    f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    f.set_variation_by_axes([100, min(96, max(17, size)), 400, weight])  # width, optical size, grade, weight
    return f

def palette():
    sw = [("Paper", "#F2F1EE"), ("Ink", "#1A1A1A"), ("Surface", "#FBFBF9"), ("Tile", "#EDECE8"), ("Graphite", "#141414")]
    W, H = 1600, 420
    im = Image.new("RGB", (W, H), "#FFFFFF"); d = ImageDraw.Draw(im)
    cw = W // len(sw)
    for i, (n, h) in enumerate(sw):
        x = i * cw
        d.rectangle([x, 0, x + cw, 300], fill=h)
        d.text((x + 28, 322), n, fill="#1A1A1A", font=font(34, 700))
        d.text((x + 28, 366), h, fill="#6B6B6B", font=font(26, 500))
    d.line([0, 300, W, 300], fill="#E0E0E0")
    im.save(B / "palette.png", optimize=True)

def clear_space():
    lock = Image.open(B / "wordmark/glasspad-lockup-light.png"); P = 40
    art = lock.crop((P, P, lock.width - P, lock.height - P))
    x = art.height // 2  # clear space: half the lockup's height on every side
    M = 60
    W, H = art.width + 2 * x + 2 * M, art.height + 2 * x + 2 * M
    im = Image.new("RGB", (W, H), "#F2F1EE"); d = ImageDraw.Draw(im)
    d.rectangle([M, M, W - M, H - M], fill="#E7E5DF")
    ox, oy = M + x, M + x
    im.paste(art, (ox, oy), art)
    def dash(x0, y0, x1, y1):
        n = int(max(abs(x1 - x0), abs(y1 - y0)) // 20)
        for k in range(0, n, 2):
            a, b = k / n, (k + 1) / n
            d.line([x0 + (x1 - x0) * a, y0 + (y1 - y0) * a, x0 + (x1 - x0) * b, y0 + (y1 - y0) * b], fill="#1A1A1A", width=3)
    dash(M, M, W - M, M); dash(M, H - M, W - M, H - M); dash(M, M, M, H - M); dash(W - M, M, W - M, H - M)
    d.rectangle([ox, oy, ox + art.width, oy + art.height], outline="#B8B5AE", width=2)
    f = font(48, 600)
    cx = ox + art.width // 2
    d.line([cx, M, cx, oy], fill="#1A1A1A", width=3); d.text((cx + 18, M + x // 2 - 30), "x", fill="#1A1A1A", font=f)
    cy = oy + art.height // 2
    d.line([M, cy, ox, cy], fill="#1A1A1A", width=3); d.text((M + x // 2 - 12, cy - 66), "x", fill="#1A1A1A", font=f)
    im = im.resize((im.width * 2 // 3, im.height * 2 // 3), Image.LANCZOS)
    im.save(B / "clear-space.png", optimize=True)

palette(); clear_space()
