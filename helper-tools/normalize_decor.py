#!/usr/bin/env python3
"""Turn a generated prop picture into a game-ready street-decor sprite.

Street decor is the small stuff that dresses the street without ever being
gameplay: litter lying on the pavement, critters that scurry through the
foreground. The roster lives in shared/assets/decor/decor.json and is read by
scripts/street_decor.gd — data, like weapons.json.

Unlike the weapons there is no shared canvas here. Every prop keeps its own
proportions, because nothing about decor is sized from the canvas: how big it
lands on screen is the `Scale` number in decor.json. So all this does is cut
the background out, trim to the art, and scale to a sensible SOURCE height.
Retuning how big a rat looks is a JSON edit, never a regeneration.

Source height defaults to the bird sheet's 96px for the same reason the bird
uses it: the 640x360 design view is stretched to whatever the real screen is,
so a sprite that is 13 design-px tall still wants real pixels behind it on a
phone. Keep the source comfortably bigger than the on-screen size.

Generated on flat white with a bold dark outline (prompt recipe in
helper-tools/README.md). Background removal is the same four-corner flood fill
as normalize_weapon.py, and the dark outline is exactly what stops it leaking
into pale art — a crumpled newspaper is nearly the same colour as the
background it was generated on, and only the outline keeps them apart.

It also prints the bottom of the sprite's alpha profile, which is how you
pick `FootFrac` for a critter — see below.

Run:  python3 helper-tools/normalize_decor.py <raw.png> <out.png> [--height N]
"""
import argparse
import os
import sys

from PIL import Image

# cut_out is the weapon normalizer's, not a copy of it: same generator, same
# flat-white background, same failure modes worth fixing in one place.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from normalize_weapon import cut_out  # noqa: E402

DEFAULT_HEIGHT = 96


def normalize(cut: Image.Image, height: int) -> Image.Image:
    """Trim `cut` to its art and scale it to `height`, keeping the aspect."""
    box = cut.getbbox()
    if box is None:
        raise SystemExit("nothing left after background removal")
    art = cut.crop(box)
    scale = height / art.height
    return art.resize((max(round(art.width * scale), 1), height), Image.LANCZOS)


def bottom_profile(img: Image.Image, rows: int = 14) -> str:
    """Print the bottom rows of the alpha profile, to read `FootFrac` off.

    A critter's ground contact is NOT the bottom of its bounding box: a rat's
    tail hangs below its paws, so planting the bbox on the pavement stands the
    animal on tiptoe. `FootFrac` in decor.json is where the contact line
    really is, as a fraction of sprite height.

    This is deliberately not auto-detected. The obvious rule — lowest row
    carrying a decent slab of pixels — reads the rat's tail as feet, because
    the tail sweeps sideways across the bottom and is every bit as wide as the
    paws are. So print the shape and let a human see where the solid body ends
    and the thin trailing bits begin; on the shipped rat that is row 82 of 96,
    hence FootFrac 0.85.
    """
    alpha = img.split()[3]
    w, h = img.size
    counts = [sum(1 for x in range(w) if alpha.getpixel((x, y)) > 40)
              for y in range(h)]
    widest = max(counts) or 1
    out = ["  row  frac   width", "  --------------------"]
    for y in range(max(h - rows, 0), h):
        out.append("  %3d  %.2f  %s%d" % (
            y + 1, (y + 1) / h, "#" * round(24.0 * counts[y] / widest),
            counts[y]))
    return "\n".join(out)


def main() -> None:
    ap = argparse.ArgumentParser(description="Normalize a street-decor sprite.")
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--height", type=int, default=DEFAULT_HEIGHT,
                    help="source height in px (default %d)" % DEFAULT_HEIGHT)
    a = ap.parse_args()
    out = normalize(cut_out(Image.open(a.src)), a.height)
    out.save(a.dst)
    print("%s -> %s  size=%s" % (a.src, a.dst, out.size))
    print(bottom_profile(out))


if __name__ == "__main__":
    main()
