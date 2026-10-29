# Phyllon Brand

The name, mark, colors and type of Phyllon, chosen on 2026-10-29. Everything in
this folder except this guide is produced by `generate.py`; change the script,
never the files.

## 🌱 The story

Greek _φύλλον_ means leaf: the leaf of a plant and the leaf of a book. Leaves
and seeds grow at the golden angle, 137.5°, which a formula describes exactly.
So the name carries the three things Phyllon stands for: growth, precision and a
library.

## 🌻 The mark

A sunflower seed head with a leaf at its heart. Seed `n` sits at radius `c·√n`,
turned by the golden angle from seed `n − 1` (Vogel's model). Nobody drew the
spiral arms you see; they follow from the formula, and the same script always
writes the same bytes. A deterministic logo for a platform built to be
deterministic.

| File            | Use                                                                                                                |
| --------------- | ------------------------------------------------------------------------------------------------------------------ |
| `logo.svg`      | The mark on light backgrounds                                                                                      |
| `logo-dark.svg` | The mark on dark backgrounds                                                                                       |
| `logo-mono.svg` | One ink color, for worksheets and anything printed in black and white                                              |
| `favicon.svg`   | Browser tab and app icon: a blue tile, 21 seeds and a large leaf, because 119 seeds do not survive 16 pixels       |
| `lockup.svg`    | Mark and wordmark side by side. The wordmark is live text in Fraunces; convert it to paths before it goes to print |

Keep a clear space of a quarter of the mark's width around it. Do not recolor
the mark except through the mono version, and do not redraw it by hand.

## 🎨 Colors: Frühling

Two brand colors from the mark, school-ink blue and leaf green, and two signal
colors from the school exercise book. Each color has one meaning and keeps it
everywhere.

| Token       | Light     | Dark      | Means                                                                                                   |
| ----------- | --------- | --------- | ------------------------------------------------------------------------------------------------------- |
| `blue`      | `#2B54C8` | `#93ACFF` | The brand, links, primary actions                                                                       |
| `leaf`      | `#16804A` | `#5FDB98` | Checked, approved, right (`leaf-text` `#0F7240` for small text on light)                                |
| `sunflower` | `#F5B700` | `#FFD24D` | Waiting for approval, marked for review: the highlighter (`sunflower-text` `#5E4500` for text on light) |
| `red-pen`   | `#BF2E24` | `#FF8A80` | A mistake or a failed check: the teacher's red pen                                                      |
| `ink`       | `#18213A` | `#EEF2FF` | Body text                                                                                               |
| `muted`     | `#4F5B78` | `#AEB9DA` | Secondary text                                                                                          |
| `paper`     | `#FFFFFF` | `#0F1A3A` | Page background                                                                                         |
| `surface`   | `#F4F7FF` | `#172452` | Cards and panels                                                                                        |
| `line`      | `#DFE6F7` | `#243369` | Borders                                                                                                 |

Every text color reaches WCAG AA (4.5:1) on its background and on its soft chip
background, measured on 2026-10-29. `palette.json` holds all tokens with the
soft variants, and `palette.css` exposes them as `--ph-*` custom properties that
follow `prefers-color-scheme`.

Worksheets print in black and white whatever the palette: color in a sheet may
support meaning but never carry it alone.

## 🔤 Type

- **Atkinson Hyperlegible Next** for the interface and for worksheets. It was
  designed to keep look-alike characters apart (1, l and I; 0 and O), which
  matters in math.
- **Fraunces** at weight 600, for the wordmark only.

Both are under the SIL Open Font License.

## 📐 Diagrams

`mermaid-theme.json` holds a light and a dark set of Mermaid `themeVariables`
for the `base` theme, built from the same tokens: blue nodes, green for what is
done, sunflower for what waits, red for what failed. A diagram in the docs opens
with an `init` directive that carries the light set.

## ❓ Open

- The wordmark as outlined paths, so the lockup does not depend on an installed
  font.
- A look at the favicon at real size in a browser tab.
