"""Renders one 1200x630 Open Graph image per page in web/site/pages.ts to web/public/og/<slug>.png.

Same family as web/public/og-light.png: paper background, bold title on the left, a real app
screen on the right (from docs/img/screens, or a real Mac view from docs/brand/screenshots).
Slug: "/" -> "home", "/use/x" -> "use-x". Pages with no entry in SHOT get no card of their own and
use the site card, web/public/og-light.png, which this script also renders (icon, wordmark and the
definition line from web/site/content.ts). Render on a Mac (the title font is SF Pro).
Usage (repo root): python3 docs/brand/tools/og.py
"""
import json, pathlib, re, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
SCREENS = ROOT / "docs/img/screens"
MAC = ROOT / "docs/brand/screenshots"
ICON = ROOT / "docs/brand/icon/glasspad-icon-mac-1024.png"
OUT = ROOT / "web/public/og"

# Page path -> the screen(s) on its card. "mac:" means a real Mac view, drawn as a card. glasspad-mac-settings-iphone-light.png is cropped to its content (top 400 px).
SHOT = {
    "/": ["actions", "media"],
    "/guide": ["menu"],
    "/install": ["mac:glasspad-mac-popover-connected-light"],
    "/about": ["themes"],
    "/privacy": ["mac:glasspad-mac-settings-iphone-light"],
    "/terms": ["dock"],
    "/use/iphone-as-mac-trackpad": ["trackpad"],
    "/use/iphone-as-mac-keyboard": ["keyboard"],
    "/use/iphone-remote-for-mac": ["remote"],
    "/use/iphone-presentation-remote-mac": ["present"],
    "/use/stream-deck-alternative-mac": ["actions"],
    "/use/mac-split-screen-from-iphone": ["folder"],
    "/use/control-mac-displays-from-iphone": ["displays"],
    "/use/iphone-to-mac-clipboard": ["clipboard"],
    "/use/control-mac-from-iphone": ["layouts"],
    "/compare/stream-deck-mobile": ["library"],
    "/compare/remote-mouse": ["media"],
    "/compare/mobile-mouse": ["trackpad"],
    "/compare/coast": ["actions"],
    "/compare/universal-control": ["displays"],
}
LANDSCAPE = {"trackpad", "layouts", "standby"}

def pages():
    src = (ROOT / "web/site/pages.ts").read_text()
    body = src[src.index("export const pages"):]
    out = []
    for block in re.findall(r"\{(.*?)\n  \}", body, re.S):
        path = re.search(r'path: "([^"]+)"', block).group(1)
        title = re.search(r'\btitle: "([^"]+)"', block).group(1)
        og = re.search(r'ogTitle: "([^"]+)"', block)
        out.append((path, og.group(1) if og else title))
    return out

def display_title(path, t):
    t = re.sub(r"\s*\|\s*Glasspad$", "", t)
    if t.startswith("Glasspad: "):
        t = t[len("Glasspad: "):]
        t = t[0].upper() + t[1:]
    return t

def slug(path):
    return "home" if path == "/" else path.strip("/").replace("/", "-")

def art(shots):
    if shots[0].startswith("mac:"):
        src = (MAC / f"{shots[0][4:]}.png").as_uri()
        return f'<div class="mac"><img src="{src}"></div>'
    if len(shots) == 2:
        a, b = (SCREENS / f"{s}.png" for s in shots)
        return f'<img class="ph two a" src="{a.as_uri()}"><img class="ph two b" src="{b.as_uri()}">'
    s = shots[0]
    cls = "land" if s in LANDSCAPE else "ph"
    return f'<img class="{cls}" src="{(SCREENS / f"{s}.png").as_uri()}">'

CSS = """
* { margin: 0; box-sizing: border-box; }
body { width: 1200px; height: 630px; overflow: hidden; background: #F2F1EE; color: #1A1A1A;
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', Arial, sans-serif; position: relative; }
.l { position: absolute; left: 72px; top: 0; bottom: 0; width: 540px; display: flex; flex-direction: column; justify-content: center; }
.brand { position: absolute; top: 60px; left: 0; display: flex; align-items: center; gap: 12px; font-size: 30px; font-weight: 700; letter-spacing: -0.02em; }
.brand img { width: 60px; height: 60px; margin: -6px -8px -6px -6px; }
h1 { font-size: 58px; line-height: 1.06; font-weight: 700; letter-spacing: -0.035em; text-wrap: balance; }
h1.s { font-size: 50px; }
.foot { position: absolute; bottom: 58px; left: 0; font-size: 22px; font-weight: 500; color: rgba(26,26,26,0.62); letter-spacing: -0.01em; }
.r { position: absolute; left: 640px; right: 0; top: 0; bottom: 0; }
.ph { position: absolute; width: 440px; left: 70px; top: 26px; }
.ph.two { width: 400px; }
.ph.two.a { left: -10px; top: 70px; }
.ph.two.b { left: 230px; top: 22px; }
.land { position: absolute; width: 620px; left: -30px; top: 150px; }
.mac { position: absolute; left: 20px; top: 50%; transform: translateY(-50%); width: 500px; border-radius: 22px; background: #FFFFFF; padding: 14px 10px; overflow: hidden;
  box-shadow: 0 0 0 1px rgba(26,26,26,0.08), 0 24px 60px rgba(26,26,26,0.16); }
.mac img { display: block; width: 100%; }
"""

def html(path, title):
    small = len(title) > 44
    return f"""<html><head><style>{CSS}</style></head><body>
<div class="l"><div class="brand"><img src="{ICON.as_uri()}">Glasspad</div>
<h1 class="{'s' if small else ''}">{title}</h1>
<div class="foot">Free and open source &middot; glasspad.sohamaggarwal.com</div></div>
<div class="r">{art(SHOT[path])}</div></body></html>"""

def definition():
    src = (ROOT / "web/site/content.ts").read_text()
    return re.search(r'export const DEFINITION = "([^"]+)"', src).group(1)

SITE_CSS = """
* { margin: 0; box-sizing: border-box; }
body { width: 1200px; height: 630px; overflow: hidden; background: #F2F1EE; color: #1A1A1A;
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', Arial, sans-serif;
  display: flex; flex-direction: column; justify-content: center; padding: 0 96px; }
.brand { display: flex; align-items: center; gap: 28px; font-size: 104px; font-weight: 700; letter-spacing: -0.035em; line-height: 1; }
.brand img { width: 176px; height: 176px; margin: -14px -18px -14px -14px; }
p { margin-top: 44px; max-width: 980px; font-size: 36px; line-height: 1.3; font-weight: 500; letter-spacing: -0.01em; color: rgba(26,26,26,0.72); text-wrap: balance; }
.foot { position: absolute; bottom: 52px; left: 96px; font-size: 22px; font-weight: 500; color: rgba(26,26,26,0.62); }
"""

def site_card():
    return f"""<html><head><style>{SITE_CSS}</style></head><body>
<div class="brand"><img src="{ICON.as_uri()}">Glasspad</div>
<p>{definition()}</p>
<div class="foot">glasspad.sohamaggarwal.com</div></body></html>"""

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = pathlib.Path(tempfile.mkdtemp())
    (tmp / "site.html").write_text(site_card())
    jobs = [{"in": str(tmp / "site.html"), "out": str(ROOT / "web/public/og-light.png"), "w": 1200, "h": 630}]
    for path, t in pages():
        if path not in SHOT:
            continue          # uses the site card
        name = slug(path)
        (tmp / f"{name}.html").write_text(html(path, display_title(path, t)))
        jobs.append({"in": str(tmp / f"{name}.html"), "out": str(OUT / f"{name}.png"), "w": 1200, "h": 630})
    (tmp / "jobs.json").write_text(json.dumps(jobs))
    subprocess.run(["node", "docs/brand/tools/shoot.mjs", str(tmp / "jobs.json")], cwd=ROOT, check=True)

main()
