"""Contact sheets of a rendered film, one frame every `step` seconds, time labelled:
  python3 -I scripts/v4/sheet.py out/glasspad-film-v4.mp4 [step=0.5] [out dir=out/v4-sheets]
Writes sheetN.jpg, 20 frames (4 x 5) a page, for checking every range by eye."""
import os, subprocess, sys, tempfile
from PIL import Image, ImageDraw
src = sys.argv[1]; step = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5
out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(src), "v4-sheets")
os.makedirs(out, exist_ok=True)
tmp = tempfile.mkdtemp()
subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", src, "-vf", f"fps=1/{step},scale=480:-2", os.path.join(tmp, "f%05d.jpg")], check=True)
fs = sorted(os.listdir(tmp))
cols, per = 4, 20
for p in range(0, len(fs), per):
    page = fs[p:p + per]; rows = (len(page) + cols - 1) // cols
    S = Image.new("RGB", (cols * 484, rows * 274), (50, 50, 50))
    for i, f in enumerate(page):
        im = Image.open(os.path.join(tmp, f)).convert("RGB")
        t = (p + i) * step
        d = ImageDraw.Draw(im); d.rectangle([0, 0, 70, 16], fill=(0, 0, 0)); d.text((4, 2), f"{t:.1f}s", fill=(255, 220, 0))
        S.paste(im, ((i % cols) * 484, (i // cols) * 274))
    path = os.path.join(out, f"sheet{p // per + 1:02d}.jpg"); S.save(path, quality=82); print(path)
