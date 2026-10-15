"""Contact sheet with time labels: python3 -I sheet.py <dir> [cols]. Writes <dir>/sheetN.png (16 per page)."""
import glob, os, sys
from PIL import Image, ImageDraw
d = sys.argv[1]; cols = int(sys.argv[2]) if len(sys.argv) > 2 else 4
files = sorted(glob.glob(os.path.join(d, "s*.png")))
files = [f for f in files if "sheet" not in os.path.basename(f)]
if not files: sys.exit("no stills")
w0, h0 = Image.open(files[0]).size
tw = 480 if w0 > h0 else 270; th = round(h0 * tw / w0)
per = 16 if w0 > h0 else 12
for p in range(0, len(files), per):
    page = files[p:p + per]; rows = (len(page) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw + (cols - 1) * 4, rows * th + (rows - 1) * 4), (60, 60, 60))
    for i, f in enumerate(page):
        im = Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS)
        dr = ImageDraw.Draw(im); lab = os.path.basename(f)[1:-4].lstrip("0") + "s"
        dr.rectangle([0, 0, 70, 20], fill=(0, 0, 0)); dr.text((5, 4), lab, fill=(255, 255, 255))
        sheet.paste(im, ((i % cols) * (tw + 4), (i // cols) * (th + 4)))
    out = os.path.join(d, f"sheet{p // per + 1}.png"); sheet.save(out); print(out)
