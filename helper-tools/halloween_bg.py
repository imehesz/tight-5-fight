#!/usr/bin/env python3
"""Rebuild the HALLOWEEN edition's street tile and its distant sky layer.

Two subcommands, and the ORDER MATTERS because make_parallax_layers.py runs
between them:

    python3 helper-tools/halloween_bg.py tile
    python3 helper-tools/make_parallax_layers.py street  halloween
    python3 helper-tools/make_parallax_layers.py stars   halloween
    python3 helper-tools/make_parallax_layers.py skyline halloween <source.png>
    python3 helper-tools/halloween_bg.py moon

WHY THE MOON AND BATS ARE NOT IN THE TILE
-----------------------------------------
make_parallax_layers.py reads this edition's palette back out of
street_tile.png, and two of its rules are easy to poison:

* It takes the highest non-sky pixel as the NEAREST BUILDING and samples 4px
  below it. Bats drawn up in the tile's sky are the highest non-sky pixels, so
  "nearest building" came back as sky, the distance haze was computed as
  lerp(sky, sky) and the whole skyline layer rendered invisible.
* It picks the STAR colour as the first colour in most-common order with luma
  >= 150 that is not the sky. The moon, and then the road stripe, each won that
  vote ahead of the actual white stars, so the sky filled with orange specks.

So the tile stays plain -- no moon, no bats -- and the lit windows and road
stripe are deliberately held UNDER luma 150. The moon and bats are painted
afterwards onto parallax_stars.png, which is where they belong anyway: that is
the far, opaque sky layer at factor 0.1, so they drift slowly instead of
tearing past at street speed.

Needs Pillow. Run from the repo root.
"""

import sys

from PIL import Image, ImageDraw

TILE = "games/halloween/assets/backgrounds/street_tile.png"
STARS = "games/halloween/assets/backgrounds/parallax_stars.png"

SKY = (26, 12, 44, 255)
STAR = (236, 228, 255, 255)
MOON, MOONSH = (255, 206, 130, 255), (228, 170, 96, 255)
BAT = (20, 9, 33, 255)
# luma 144.6 and 146 -- both deliberately under make_parallax_layers'
# STAR_LUMA_MIN of 150, so neither is mistaken for a star.
WIN_ON, WIN_OFF = (224, 126, 32, 255), (30, 16, 48, 255)
STRIPE = (214, 132, 40, 255)
BUILDS = ((0, 34, 70, (36, 20, 54)), (36, 30, 88, (46, 26, 66)),
          (68, 40, 60, (30, 16, 48)), (110, 48, 80, (42, 24, 60)))


def _rect(d, x0, y0, x1, y1, c):
    d.rectangle([x0, y0, x1, y1], fill=c)


def tile() -> None:
    """160x180 upscaled 2x -> the 320x360 street tile. Geometry matches
    tools/gen_assets.py gen_street_tile so the parallax helper still reads it."""
    img = Image.new("RGBA", (160, 180), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    _rect(d, 0, 0, 159, 129, SKY)
    for sx, sy in ((14, 12), (48, 28), (90, 8), (130, 52), (70, 40), (8, 45), (100, 22)):
        _rect(d, sx, sy, sx, sy, STAR)

    for bx, bw, bh, c in BUILDS:
        _rect(d, bx, 130 - bh, bx + bw - 1, 130, c + (255,))
        for wy in range(134 - bh, 126, 12):
            for wx in range(bx + 4, bx + bw - 5, 9):
                lit = (wx * 7 + wy * 13) % 3 != 0
                _rect(d, wx, wy, wx + 3, wy + 4, WIN_ON if lit else WIN_OFF)

    _rect(d, 0, 130, 159, 132, (78, 66, 92, 255))        # curb top
    _rect(d, 0, 132, 159, 164, (104, 92, 118, 255))      # sidewalk
    for lx in range(0, 160, 32):
        d.line([lx, 132, lx, 164], fill=(84, 72, 98, 255), width=1)
    _rect(d, 0, 164, 159, 166, (60, 50, 72, 255))        # curb face
    _rect(d, 0, 166, 159, 179, (40, 32, 50, 255))        # road
    _rect(d, 8, 172, 40, 174, STRIPE)
    _rect(d, 88, 172, 120, 174, STRIPE)

    img.resize((320, 360), Image.NEAREST).save(TILE)
    print(f"wrote {TILE} 320x360")


def moon() -> None:
    """Moon + bats onto the far sky layer. Run AFTER make_parallax_layers stars."""
    im = Image.open(STARS).convert("RGBA")
    d = ImageDraw.Draw(im)
    cx, cy, r = 486, 74, 29          # clear of both seams, so it is never halved
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=MOON)
    # Craters scattered off-axis on purpose: a symmetric pair over a curved
    # shadow reads as a smiley face, which it did on the first pass.
    for ox, oy, rr in ((9, -12, 4), (-11, 3, 3), (6, 13, 4), (-4, 18, 2)):
        d.ellipse([cx + ox - rr, cy + oy - rr, cx + ox + rr, cy + oy + rr], fill=MOONSH)
    for bx, by, s in ((150, 66, 3), (196, 92, 2), (258, 54, 2), (560, 118, 2), (92, 120, 2)):
        for k in range(4):
            x0 = bx + 2 * s * k
            y0 = by if k % 2 == 0 else by - 2 * s
            y1 = by - 2 * s if k % 2 == 0 else by
            d.line([x0, y0, x0 + 2 * s, y1], fill=BAT, width=max(1, s // 2))
    im.save(STARS)
    print(f"painted moon + bats onto {STARS}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "tile":
        tile()
    elif cmd == "moon":
        moon()
    else:
        raise SystemExit(__doc__)
