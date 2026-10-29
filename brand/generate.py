"""Generate Phyllon's logo files and theme tokens.

The mark is drawn by a formula, not by hand: seed n of the spiral sits at radius c * sqrt(n) and is
turned by the golden angle (137.5 degrees) from seed n - 1 (Vogel's model of a sunflower head). The
same input always produces the same files, so the logo is as deterministic as the platform.

Run: python3 brand/generate.py   (writes into brand/)
"""
import json
import math
from pathlib import Path

OUT = Path(__file__).resolve().parent
GOLDEN_ANGLE = 137.50776405003785

# Frühling, chosen 2026-10-29. "text" variants are darkened where a color carries text, to reach WCAG AA.
PALETTE = {
    "light": {
        "paper": "#FFFFFF", "surface": "#F4F7FF", "line": "#DFE6F7", "ink": "#18213A", "muted": "#4F5B78",
        "blue": "#2B54C8", "blue-soft": "#E2E9FC", "seed": "#93ACF5",
        "leaf": "#16804A", "leaf-text": "#0F7240", "leaf-soft": "#D9F3E4",
        "sunflower": "#F5B700", "sunflower-text": "#5E4500", "sunflower-soft": "#FFF1C2",
        "red-pen": "#BF2E24", "red-pen-soft": "#FDE3E0",
    },
    "dark": {
        "paper": "#0F1A3A", "surface": "#172452", "line": "#243369", "ink": "#EEF2FF", "muted": "#AEB9DA",
        "blue": "#93ACFF", "blue-soft": "#22357A", "seed": "#4F6BD8",
        "leaf": "#5FDB98", "leaf-text": "#5FDB98", "leaf-soft": "#163F2D",
        "sunflower": "#FFD24D", "sunflower-text": "#FFD24D", "sunflower-soft": "#3D3414",
        "red-pen": "#FF8A80", "red-pen-soft": "#4C1F25",
    },
}
MEANING = {
    "blue": "school-ink blue: the brand, links, primary actions",
    "leaf": "checked, approved, right",
    "sunflower": "waiting for approval, marked for review (the highlighter)",
    "red-pen": "a mistake, a failed check (the teacher's red pen)",
    "ink": "body text", "muted": "secondary text", "paper": "page background", "surface": "cards and panels",
    "line": "borders and the faint grid", "seed": "the light end of the logo's seed gradient",
}

LEAF = ("M 0,-80 C 5,-70 13,-60 25,-50 C 50,-30 57,8 44,38 C 32,60 14,70 0,72 C -14,70 -32,60 -44,38 "
        "C -57,8 -50,-30 -25,-50 C -13,-60 -5,-70 0,-80 Z")


def lerp(a, b, t):
    a = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(a, b))


def seeds(inner, outer, n_dots=144, skip=26, radius=88.0, r_min=1.6, r_max=4.6):
    c = radius / math.sqrt(n_dots)
    out = []
    for n in range(skip, n_dots + 1):
        t = math.sqrt(n / n_dots)
        a = math.radians(n * GOLDEN_ANGLE)
        x, y = c * math.sqrt(n) * math.cos(a), c * math.sqrt(n) * math.sin(a)
        r = r_min + (r_max - r_min) * t
        out.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{r:.2f}" fill="{lerp(inner, outer, t)}"/>')
    return "".join(out)


def leaf(color, uid, scale=0.37):
    """The plain leaf with its midrib cut out as a real hole, so it works on any background."""
    return (f'<defs><mask id="rib-{uid}" maskUnits="userSpaceOnUse" x="-100" y="-110" width="200" height="220">'
            f'<rect x="-100" y="-110" width="200" height="220" fill="#fff"/>'
            f'<line x1="0" y1="-66" x2="0" y2="62" stroke="#000" stroke-width="5" stroke-linecap="round"/></mask></defs>'
            f'<g transform="scale({scale})">'
            f'<line x1="0" y1="70" x2="0" y2="104" stroke="{color}" stroke-width="10" stroke-linecap="round"/>'
            f'<path d="{LEAF}" fill="{color}" mask="url(#rib-{uid})"/></g>')


def svg(body, size=512, view="-100 -100 200 200", title="Phyllon"):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}" width="{size}" height="{size}" role="img">'
            f'<title>{title}</title>{body}</svg>\n')


def write(name, text):
    (OUT / name).write_text(text, encoding="utf-8")


def main():
    lt, dk = PALETTE["light"], PALETTE["dark"]
    write("logo.svg", svg(seeds(lt["seed"], lt["blue"]) + leaf(lt["leaf"], "l")))
    write("logo-dark.svg", svg(seeds(dk["seed"], "#C9D5FF") + leaf(dk["leaf"], "d")))
    write("logo-mono.svg", svg(seeds(lt["ink"], lt["ink"]) + leaf(lt["ink"], "m")))
    # The favicon cannot carry 119 seeds at 16 px: a blue tile, a ring of 21 seeds and a large white leaf.
    tile = f'<rect x="-100" y="-100" width="200" height="200" rx="40" fill="{lt["blue"]}"/>'
    write("favicon.svg", svg(tile + seeds(lt["seed"], lt["seed"], n_dots=34, skip=12, radius=92, r_min=6, r_max=9)
                             + leaf("#FFFFFF", "f", scale=0.62), size=64))
    lock = (seeds(lt["seed"], lt["blue"]) + leaf(lt["leaf"], "k")
            + f'<text x="118" y="34" font-family="Fraunces, Georgia, serif" font-weight="600" font-size="92" '
              f'letter-spacing="-1" fill="{lt["blue"]}">phyllon</text>')
    write("lockup.svg", f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-100 -100 640 200" width="640" height="200" '
                        f'role="img"><title>Phyllon</title>{lock}</svg>\n')

    write("palette.json", json.dumps({"name": "Frühling", "chosen": "2026-10-29", "meaning": MEANING,
                                      "light": lt, "dark": dk}, ensure_ascii=False, indent=2) + "\n")
    css = [":root {"] + [f"  --ph-{k}: {v};" for k, v in lt.items()] + ["}",
           "@media (prefers-color-scheme: dark) {", "  :root {"] + \
          [f"    --ph-{k}: {v};" for k, v in dk.items()] + ["  }", "}"]
    write("palette.css", "\n".join(css) + "\n")

    def mermaid(p):
        return {"theme": "base", "themeVariables": {
            "fontFamily": "Atkinson Hyperlegible Next, system-ui, sans-serif",
            "background": p["paper"], "primaryColor": p["blue-soft"], "primaryTextColor": p["ink"],
            "primaryBorderColor": p["blue"], "secondaryColor": p["leaf-soft"], "secondaryTextColor": p["ink"],
            "secondaryBorderColor": p["leaf"], "tertiaryColor": p["sunflower-soft"], "tertiaryTextColor": p["ink"],
            "tertiaryBorderColor": p["sunflower"], "lineColor": p["muted"], "textColor": p["ink"],
            "mainBkg": p["blue-soft"], "nodeBorder": p["blue"], "clusterBkg": p["surface"], "clusterBorder": p["line"],
            "titleColor": p["ink"], "edgeLabelBackground": p["paper"], "noteBkgColor": p["sunflower-soft"],
            "noteTextColor": p["ink"], "noteBorderColor": p["sunflower"],
            "cScale0": p["blue"], "cScale1": p["leaf"], "cScale2": p["sunflower"], "cScale3": p["red-pen"]}}
    write("mermaid-theme.json", json.dumps({"light": mermaid(lt), "dark": mermaid(dk)}, indent=2) + "\n")


if __name__ == "__main__":
    main()
