"""Builds web/public/press/glasspad-press-kit.zip from docs/brand (and a PDF of the fact sheet).
Usage (repo root): python3 docs/brand/tools/press_kit.py
"""
import json, pathlib, subprocess, tempfile, zipfile
import markdown

ROOT = pathlib.Path(__file__).resolve().parents[3]
B = ROOT / "docs/brand"
OUT = ROOT / "web/public/press/glasspad-press-kit.zip"
SHOTS = ["glasspad-iphone-actions", "glasspad-iphone-keyboard", "glasspad-iphone-media", "glasspad-iphone-remote",
         "glasspad-iphone-present", "glasspad-iphone-displays", "glasspad-iphone-split", "glasspad-mac-popover-connected-light"]

CSS = """body{font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Arial,sans-serif;color:#1A1A1A;margin:44px 60px;font-size:12.5px;line-height:1.45}
h1{font-size:30px;letter-spacing:-0.02em;margin:0 0 6px}h2{font-size:17px;margin:22px 0 8px}
table{border-collapse:collapse;width:100%;font-size:12.5px}td:first-child{width:118px;font-weight:600;white-space:nowrap}td,th{text-align:left;vertical-align:top;padding:6px 10px 6px 0;border-bottom:1px solid #E6E4DF}
th{display:none}code{font-family:ui-monospace,Menlo,monospace;font-size:12px}ul{padding-left:18px}li{margin:3px 0}
.logo{width:56px;height:56px;margin:-6px 0 8px -6px}"""

def pdf(tmp):
    body = markdown.markdown((B / "fact-sheet.md").read_text(), extensions=["tables"])
    icon = (B / "icon/glasspad-icon-mac-256.png").as_uri()
    (tmp / "fact.html").write_text(f"<html><head><meta charset=utf-8><style>{CSS}</style></head><body><img class=logo src='{icon}'>{body}</body></html>")
    (tmp / "jobs.json").write_text(json.dumps([{"in": str(tmp / "fact.html"), "out": str(tmp / "fact-sheet.pdf"), "w": 816, "h": 1056, "pdf": True}]))
    subprocess.run(["node", "docs/brand/tools/shoot.mjs", str(tmp / "jobs.json")], cwd=ROOT, check=True)
    return tmp / "fact-sheet.pdf"

def main():
    tmp = pathlib.Path(tempfile.mkdtemp())
    files = [(pdf(tmp), "fact-sheet.pdf"), (B / "fact-sheet.md", "fact-sheet.md"), (B / "README.md", "brand-guide.md"),
             (B / "colors.json", "colors.json"), (B / "colors.css", "colors.css"), (B / "palette.png", "palette.png"), (B / "clear-space.png", "clear-space.png")]
    files += [(p, f"icon/{p.name}") for p in sorted((B / "icon").iterdir()) if p.suffix in (".png", ".svg")]
    files += [(p, f"wordmark/{p.name}") for p in sorted((B / "wordmark").glob("*.png"))]
    files += [(B / "screenshots" / f"{s}.png", f"screenshots/{s}.png") for s in SHOTS]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for src, name in files:
            z.write(src, f"glasspad-press-kit/{name}")
    print(OUT, OUT.stat().st_size, "bytes,", len(files), "files")

main()
