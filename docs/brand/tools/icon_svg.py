"""Writes the iOS app icon as SVG, from the same numbers as scripts/make-icons.swift.

Usage (repo root): python3 docs/brand/tools/icon_svg.py
"""
import math, pathlib

THEMES = {
    # name: (outer, surface, edge colour, edge opacity, dot)
    "light": ("#E3E1DC", "#FCFBFA", "#1A1A1A", 0.06, "#1A1A1A"),
    "dark": ("#0A0A0A", "#282828", "#FFFFFF", 0.0, "#F2F1EE"),
}

def svg(outer, surface, edge, edge_op, dot):
    # make-icons.swift draws in a y-up space; these are the same points in SVG's y-down space.
    fx, fy, tx, ty = 276, 628, 668, 432
    r0, r1 = 26, 92
    # Outer tangents of the two circles (y-up maths, then flip).
    ux, uy = tx - fx, (1024 - ty) - (1024 - fy)
    d = math.hypot(ux, uy)
    theta = math.atan2(uy, ux)
    phi = math.acos((r0 - r1) / d)
    def p(cx, cy, r, a):  # cx, cy in y-down space, angle in y-up space
        return (cx + r * math.cos(a), cy - r * math.sin(a))
    a0, b0 = p(fx, fy, r0, theta + phi), p(fx, fy, r0, theta - phi)
    a1, b1 = p(tx, ty, r1, theta + phi), p(tx, ty, r1, theta - phi)
    quad = " ".join(f"{x:.2f},{y:.2f}" for x, y in (a0, a1, b1, b0))
    edge_attr = f' stroke="{edge}" stroke-opacity="{edge_op}" stroke-width="4"' if edge_op else ""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>Glasspad</title>
  <rect width="1024" height="1024" fill="{outer}"/>
  <rect x="84" y="204" width="856" height="616" rx="132" fill="{surface}"{edge_attr}/>
  <g fill="{dot}" opacity="0.16">
    <circle cx="{fx}" cy="{fy}" r="{r0}"/>
    <polygon points="{quad}"/>
  </g>
  <circle cx="{tx}" cy="{ty}" r="{r1}" fill="{dot}"/>
</svg>
'''

out = pathlib.Path(__file__).resolve().parent.parent / "icon"
out.mkdir(exist_ok=True)
for name, t in THEMES.items():
    (out / f"glasspad-icon-ios-{name}.svg").write_text(svg(*t))
print("wrote", out)
