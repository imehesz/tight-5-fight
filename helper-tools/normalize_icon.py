#!/usr/bin/env python3
"""Turn a generated logo picture into a game-ready square UI icon.

The social buttons on the main menu (and anything else that wants a small
pixel badge) all share one shape: a transparent-background square PNG on a
chunky pixel grid, imported with filtering OFF so it stays crisp when the
menu scales up on a phone.

    python3 helper-tools/normalize_icon.py raw.png shared/assets/ui/social_fb.png

It flood-fills the background in from the four corners -- not a "white is
transparent" threshold, because these badges have white glyphs and pale
highlights of their own -- then squares the cut-out up and box-samples it
down to --size. The alpha is re-thresholded after the resize so the edge
lands on the pixel grid instead of fading out over three soft pixels.

Needs Pillow.
"""

import argparse
from collections import deque

from PIL import Image


def cut_background(img: Image.Image, tol: int) -> Image.Image:
    """Erase the connected background reachable from the four corners."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    refs = [px[s][:3] for s in seeds]
    seen = bytearray(w * h)
    q = deque(seeds)
    for s in seeds:
        seen[s[1] * w + s[0]] = 1
    while q:
        x, y = q.popleft()
        r, g, b, _ = px[x, y]
        if not any(abs(r - cr) <= tol and abs(g - cg) <= tol and abs(b - cb) <= tol
                   for cr, cg, cb in refs):
            continue
        px[x, y] = (r, g, b, 0)
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
                seen[ny * w + nx] = 1
                q.append((nx, ny))
    return img


def square(img: Image.Image, pad: int) -> Image.Image:
    """Crop to the art, then centre it on a transparent square canvas."""
    box = img.getbbox()
    if box:
        img = img.crop(box)
    side = max(img.size) + pad * 2
    out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    out.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    return out


def to_pixel_grid(img: Image.Image, size: int, cutoff: int) -> Image.Image:
    """Box-sample down to size x size, then snap the alpha back to on/off.

    Averaging (not nearest) is what keeps the Instagram gradient smooth; the
    alpha snap afterwards is what keeps the outline from going gauzy.
    """
    small = img.resize((size, size), Image.BOX)
    px = small.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255 if a >= cutoff else 0)
    return small


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("dest")
    ap.add_argument("--size", type=int, default=64, help="output edge in px (default 64)")
    ap.add_argument("--tol", type=int, default=28,
                    help="background colour tolerance for the flood fill (default 28)")
    ap.add_argument("--pad", type=int, default=0,
                    help="transparent margin around the art, in source px")
    ap.add_argument("--alpha-cutoff", type=int, default=110,
                    help="alpha at or above this survives the resize (default 110)")
    args = ap.parse_args()

    img = cut_background(Image.open(args.src), args.tol)
    img = square(img, args.pad)
    img = to_pixel_grid(img, args.size, args.alpha_cutoff)
    img.save(args.dest)
    print("wrote %s (%dx%d)" % (args.dest, args.size, args.size))


if __name__ == "__main__":
    main()
