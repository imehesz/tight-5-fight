#!/usr/bin/env python3
"""Turn a generated weapon image into a game-ready weapon sprite.

The melee weapons are generated on flat white (see helper-tools/README.md for
the prompt recipe), and every one of them has to land on the same canvas as the
original mic stand, because the swing and carry code sizes them from the
canvas, not from the art:

  * 302x900 RGBA, weapon vertical, striking end up, grip end down
  * art occupying y 22..872, horizontally centred — the mic stand's own bounds

Background removal is a flood fill from the four corners rather than a global
"white is transparent" threshold: these weapons have white highlights and pale
steel of their own, and only the background is connected to the frame edge.
The generator also lays a faint drop shadow under the object; the fill's
tolerance swallows it as long as it stays connected to the corners.

Pass --rotate180 for anything whose striking end is naturally at the BOTTOM of
a normal picture of it — a guitar is swung by the neck, so its body has to end
up at the top of the canvas. Generators draw those subjects far better the
right way up, so the turn happens here instead of in the prompt.

Run:  python3 helper-tools/normalize_weapon.py <raw.png> <out.png> [--rotate180]
"""
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# Matches weapon_mic-in-stand_small.png exactly, so a swapped-in weapon needs
# no per-weapon numbers anywhere in the game code.
CANVAS = (302, 900)
TOP, BOTTOM = 22, 872
# Left/right breathing room, so a wide weapon (the chainsaw) still gets a
# couple of clear pixels at the canvas edge.
SIDE_MARGIN = 6
# Per-band tolerance for the corner fill. High enough to eat the soft shadow
# and the off-white cast some generations come back with, low enough to stop
# at a pale steel blade.
FLOOD_TOLERANCE = 34
KEY = (255, 0, 255)


def cut_out(raw: Image.Image) -> Image.Image:
    """RGBA copy of `raw` with the background-connected region made clear."""
    rgb = raw.convert("RGB")
    w, h = rgb.size
    for corner in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        # Already keyed (all four corners are usually one region) — skip, or
        # floodfill would spread from a magenta seed into the artwork.
        if rgb.getpixel(corner) == KEY:
            continue
        ImageDraw.floodfill(rgb, corner, KEY, thresh=FLOOD_TOLERANCE)
    # Keyed pixels are exactly KEY in all three bands; anything the fill did
    # not reach keeps its own colour and fails at least one of the three.
    bands = [band.point(lambda v, k=k: 255 if v == k else 0)
             for band, k in zip(rgb.split(), KEY)]
    keyed = ImageChops.multiply(ImageChops.multiply(bands[0], bands[1]), bands[2])
    alpha = ImageChops.invert(keyed)
    # One pass of blur softens the fill's hard staircase before the downscale.
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.6))
    out = raw.convert("RGBA")
    out.putalpha(alpha)
    return out


def normalize(cut: Image.Image) -> Image.Image:
    """Scale and centre the cut-out onto the shared 302x900 weapon canvas."""
    box = cut.getbbox()
    if box is None:
        raise SystemExit("nothing left after background removal")
    art = cut.crop(box)
    max_h = BOTTOM - TOP
    max_w = CANVAS[0] - 2 * SIDE_MARGIN
    # Height-driven, so every weapon reads the same length on the player's
    # back; width only takes over when the art would otherwise run off canvas.
    scale = min(max_h / art.height, max_w / art.width)
    art = art.resize((max(round(art.width * scale), 1),
                      max(round(art.height * scale), 1)), Image.LANCZOS)
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    canvas.paste(art, ((CANVAS[0] - art.width) // 2,
                       TOP + (max_h - art.height) // 2), art)
    return canvas


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    if len(args) != 2 or flags - {"--rotate180"}:
        raise SystemExit(__doc__)
    src, dst = args
    raw = Image.open(src)
    if "--rotate180" in flags:
        raw = raw.rotate(180)
    out = normalize(cut_out(raw))
    out.save(dst)
    print("%s -> %s  bbox=%s" % (src, dst, out.getbbox()))


if __name__ == "__main__":
    main()
