#!/usr/bin/env python3
"""Cut a game's street background into the three advancedParallax layers.

A game ships ONE street_tile.png with the sky, the stars and the road all baked
together. Turning on "advancedParallax" in its game.json swaps that for three
strips that scroll at different speeds, and this builds them:

    parallax_stars.png      furthest, factor 0.10 — OPAQUE night sky + steady stars
    parallax_twinkle_a.png  with it,  factor 0.10 — blinking stars, faded on a loop
    parallax_twinkle_b.png  with it,  factor 0.10 — ditto, on a different period
    parallax_skyline.png    middle,   factor 0.50 — distant city, transparent sky
    parallax_street.png     nearest,  factor 1.00 — the old tile, sky knocked out

The two twinkle strips are optional: an edition without them just gets a steady
sky. `stars` writes all three star files in one go.

Every colour is read back OUT of the game's own street_tile.png — sky, star,
building and window tints all come from the art that edition already ships — so
a new city keeps its own palette without a single argument being passed.

Usage:
    python3 helper-tools/make_parallax_layers.py street  <game>
    python3 helper-tools/make_parallax_layers.py stars   <game> [--width 640]
    python3 helper-tools/make_parallax_layers.py skyline <game> <source.png> [--width 960]

The skyline source is any wide image of a city silhouette against a plainly
lighter background (an AI generation is fine — see the prompt in
games/README.md). Only its ROOFLINE is used: the shape is re-drawn from scratch
in the game's palette, so the source's own colours, texture and background never
survive into the game.
"""

import argparse
import os
import random
import sys
from collections import Counter

from PIL import Image

# Design viewport height. Every layer is authored full-height and top-aligned at
# y = 0, so the three PNGs line up with no per-layer offset to keep in sync.
OUT_H = 360

# Where the distant roofline is allowed to sit. The foreground buildings in the
# stock tile top out around y = 84 and notch down to y = 140, so a skyline drawn
# between these two lines shows above the low roofs and through the notches
# without ever poking off the top of the screen.
ROOF_MIN_Y = 34
ROOF_MAX_Y = 118
# Hard ceiling for outliers (antenna spires), so nothing reaches the top edge.
SPIRE_CEIL_Y = 12

# Columns at each end forced to a common roof height so the strip wraps without
# a visible step. 48px reads as one long flat rooftop crossing the seam.
SEAM_FLAT_PX = 48

# A pixel this much brighter than the sky is a star (in the street tile) or
# empty background (in a skyline source), never a building.
BUILDING_LUMA_MAX = 80
STAR_LUMA_MIN = 150

STAR_COUNT = 90
WINDOW_CHANCE = 0.055

# Share of the stars that blink rather than burn steady. Kept low on purpose:
# a whole sky of twinkling stars reads as noise, a handful against a steady
# field reads as a night sky. They are split across TWO strips so the engine can
# fade them on different periods — one strip alone pulses in unison.
TWINKLE_SHARE = 0.25


def luma(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def bg_dir(game):
    d = os.path.join("games", game, "assets", "backgrounds")
    if not os.path.isdir(d):
        sys.exit("no such game folder: %s" % d)
    return d


def load_tile(game):
    p = os.path.join(bg_dir(game), "street_tile.png")
    if not os.path.exists(p):
        sys.exit("missing %s" % p)
    return Image.open(p).convert("RGBA")


def roofline(im, is_sky):
    """Per-column y of the first non-sky pixel — i.e. the building tops."""
    w, h = im.size
    px = im.load()
    out = []
    for x in range(w):
        y = 0
        while y < h and is_sky(px[x, y]):
            y += 1
        out.append(y)
    return out


def read_palette(game):
    """Sky, star, distant-building and window colours, from the game's own art."""
    im = load_tile(game)
    w, h = im.size
    px = im.load()
    sky = Counter(px[x, 0] for x in range(w)).most_common(1)[0][0][:3]

    def is_sky(c):
        return c[:3] == sky or luma(c) >= STAR_LUMA_MIN

    roofs = roofline(im, is_sky)
    # The tallest building's fill, sampled just under its roof.
    tallest = min(range(w), key=lambda x: roofs[x])
    near = px[tallest, min(roofs[tallest] + 4, h - 1)][:3]
    # Distance haze: the far skyline sits half way between the sky and the
    # nearest buildings, which is what puts it visibly BEHIND them.
    far = lerp(sky, near, 0.5)

    star = (230, 230, 255)
    window = (255, 226, 130)
    for c, _ in Counter(px[x, y] for x in range(w) for y in range(h)).most_common():
        if luma(c) >= STAR_LUMA_MIN and c[:3] != sky:
            star = c[:3]
            break
    # Brightest warm colour in the tile = the lit windows; dimmed for distance.
    warm = [c[:3] for c in (px[x, y] for x in range(w) for y in range(h))
            if c[0] > 180 and c[2] < 160]
    if warm:
        window = Counter(warm).most_common(1)[0][0]
    window = tuple(int(v * 0.45) for v in window)
    return {"sky": sky, "star": star, "near": near, "far": far, "window": window}


# ------------------------------------------------------------------ street
def build_street(game):
    """The stock tile with everything above the rooftops knocked transparent."""
    im = load_tile(game)
    w, h = im.size
    px = im.load()
    sky = Counter(px[x, 0] for x in range(w)).most_common(1)[0][0][:3]
    cleared = 0
    for x in range(w):
        y = 0
        # Stars are isolated islands inside the sky, so they have to be walked
        # THROUGH rather than stopped at, or every star leaves a floating chip
        # of old sky behind once the real star layer is sliding underneath.
        while y < h and (px[x, y][:3] == sky or luma(px[x, y]) >= STAR_LUMA_MIN):
            px[x, y] = (0, 0, 0, 0)
            cleared += 1
            y += 1
    out = os.path.join(bg_dir(game), "parallax_street.png")
    im.save(out)
    print("street  %s  %dx%d  %d px cleared to transparent" % (out, w, h, cleared))


# ------------------------------------------------------------------- stars
def build_stars(game, width):
    """The sky strip plus its two twinkle strips.

    parallax_stars.png is OPAQUE — it is the backstop that paints the night sky,
    and it carries the steady stars. The two twinkle strips are transparent and
    hold nothing but the blinking stars, so the engine can fade them without
    dimming the sky along with them. No star is ever drawn on more than one
    strip, so a fade never reveals a duplicate underneath.

    All three are seamless by construction: nothing is placed within 2px of
    either edge, so a wrap can't clip a star in half.
    """
    pal = read_palette(game)
    sky = Image.new("RGBA", (width, OUT_H), pal["sky"] + (255,))
    twinkle = [Image.new("RGBA", (width, OUT_H), (0, 0, 0, 0)) for _ in range(2)]
    rnd = random.Random(1985)
    counts = [0, 0, 0]

    for i in range(STAR_COUNT):
        x = rnd.randrange(2, width - 3)
        # Out of the bottom third, where the street layer covers it anyway.
        y = rnd.randrange(2, int(OUT_H * 0.62))
        wide = rnd.random() < 0.22  # a few brighter two-pixel stars
        if rnd.random() < TWINKLE_SHARE:
            slot = i % 2
            target, idx = twinkle[slot], slot + 1
        else:
            target, idx = sky, 0
        px = target.load()
        px[x, y] = pal["star"] + (255,)
        if wide:
            px[x + 1, y] = pal["star"] + (255,)
        counts[idx] += 1

    out = os.path.join(bg_dir(game), "parallax_stars.png")
    sky.save(out)
    for slot, im in enumerate(twinkle):
        im.save(os.path.join(bg_dir(game), "parallax_twinkle_%s.png" % "ab"[slot]))
    print("stars   %s  %dx%d  sky %s" % (out, width, OUT_H, pal["sky"]))
    print("        %d steady + %d twinkle A + %d twinkle B" % tuple(counts))


# ----------------------------------------------------------------- skyline
def build_skyline(game, source, width):
    """Re-draw a source image's roofline as a flat silhouette in game colours."""
    pal = read_palette(game)
    src = Image.open(source).convert("RGB")
    sw, sh = src.size
    spx = src.load()

    # Source roofline: first dark pixel per column. Taking the MINIMUM over each
    # output column's source range keeps thin antenna spires, which a plain
    # nearest-neighbour sample would drop half the time.
    src_roof = []
    for x in range(sw):
        y = 0
        while y < sh and luma(spx[x, y]) > BUILDING_LUMA_MAX:
            y += 1
        src_roof.append(y if y < sh else sh)

    roof = []
    for x in range(width):
        a = int(x * sw / width)
        b = max(a + 1, int((x + 1) * sw / width))
        roof.append(min(src_roof[a:b]))

    # Map the source's own height range onto the band the game can actually
    # show. Percentiles rather than min/max so one tall spire doesn't squash
    # every other rooftop flat.
    ordered = sorted(roof)
    lo = ordered[int(len(ordered) * 0.04)]
    hi = ordered[int(len(ordered) * 0.96)]
    if hi <= lo:
        hi = lo + 1
    scaled = []
    for y in roof:
        t = (y - lo) / float(hi - lo)
        scaled.append(int(round(ROOF_MIN_Y + t * (ROOF_MAX_Y - ROOF_MIN_Y))))
    # A lone antenna spire sits well outside the percentile range and would map
    # off the top of the screen; SPIRE_CEIL_Y keeps it clearly above the roofs
    # without letting it touch the edge.
    scaled = [max(SPIRE_CEIL_Y, min(OUT_H - 1, y)) for y in scaled]

    # Seam: both ends flattened to the same roof height, so the strip wraps.
    edge = scaled[0]
    for x in range(SEAM_FLAT_PX):
        scaled[x] = edge
        scaled[width - 1 - x] = edge

    im = Image.new("RGBA", (width, OUT_H), (0, 0, 0, 0))
    px = im.load()
    rnd = random.Random(2026)
    for x in range(width):
        top = scaled[x]
        # Filled all the way down, not just to the horizon: the foreground
        # buildings notch down to y=140 and this is what shows through those
        # gaps. Anything below them is hidden by the street layer anyway.
        for y in range(top, OUT_H):
            px[x, y] = pal["far"] + (255,)
    for x in range(2, width - 2, 4):
        for y in range(scaled[x] + 6, OUT_H, 7):
            if rnd.random() < WINDOW_CHANCE:
                px[x, y] = pal["window"] + (255,)
                px[x + 1, y] = pal["window"] + (255,)

    out = os.path.join(bg_dir(game), "parallax_skyline.png")
    im.save(out)
    print("skyline %s  %dx%d  roofs y=%d..%d, colour %s"
          % (out, width, OUT_H, min(scaled), max(scaled), pal["far"]))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("street"); p.add_argument("game")
    p = sub.add_parser("stars"); p.add_argument("game"); p.add_argument("--width", type=int, default=640)
    p = sub.add_parser("skyline"); p.add_argument("game"); p.add_argument("source")
    p.add_argument("--width", type=int, default=960)
    a = ap.parse_args()
    if a.cmd == "street":
        build_street(a.game)
    elif a.cmd == "stars":
        build_stars(a.game, a.width)
    else:
        build_skyline(a.game, a.source, a.width)


if __name__ == "__main__":
    main()
