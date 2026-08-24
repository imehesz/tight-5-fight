#!/usr/bin/env python3
"""Cut the PUNCH (fist) and KICK (boot) touch-button glyphs.

The action buttons are 40x40 and strictly TWO colours -- white
rgba(255,255,255,128) for the frame and the glyph, navy rgba(25,25,38,150)
for the fill -- so this draws at 4x and hard-thresholds back down rather
than letting anything anti-alias into a third colour.

The frame is not redrawn: it is lifted pixel-for-pixel out of an existing
button (the white region connected to the icon's border), so a new glyph can
never drift from the set. Only the interior changes.

    python3 helper-tools/gen_action_icons.py [--outdir DIR]

Needs Pillow.
"""

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw

UI = Path("shared/assets/ui")
RAW = Path("tools/higgsfield_jobs")  # the generated silhouettes these are cut from
WHITE = (255, 255, 255, 128)
NAVY = (25, 25, 38, 150)
SIZE = 40
SS = 4  # supersample factor


def blank_button(src: Path) -> Image.Image:
    """An existing button with its glyph erased -- frame + navy fill only.

    The frame is the white region reachable from the image border; anything
    white that is NOT reachable is the old glyph, and gets filled with navy.
    """
    im = Image.open(src).convert("RGBA")
    px = im.load()
    w, h = im.size
    is_white = [[px[x, y][3] > 0 and px[x, y][:3] == WHITE[:3]
                 for y in range(h)] for x in range(w)]
    seen = [[False] * h for _ in range(w)]
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            q.append((x, y))
    # Walk inward through transparent pixels, marking every white pixel the
    # outside can touch. That is the frame.
    while q:
        x, y = q.popleft()
        if not (0 <= x < w and 0 <= y < h) or seen[x][y]:
            continue
        seen[x][y] = True
        if px[x, y][3] == 0 or is_white[x][y]:
            for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q.append((x + d[0], y + d[1]))
    out = im.copy()
    op = out.load()
    for x in range(w):
        for y in range(h):
            if is_white[x][y] and not seen[x][y]:
                op[x, y] = NAVY
    return out


def stamp(base: Image.Image, draw_fn) -> Image.Image:
    """Render a glyph at 4x, threshold it to 1-bit, paint it white on base."""
    big = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    draw_fn(ImageDraw.Draw(big))
    small = big.resize((SIZE, SIZE), Image.BOX)
    out = base.copy()
    op = out.load()
    sp = small.load()
    bp = base.load()
    for x in range(SIZE):
        for y in range(SIZE):
            # Only ever paint inside the navy well, so a glyph can't bleed
            # over the frame or outside the button's silhouette.
            if sp[x, y] >= 128 and bp[x, y][:3] == NAVY[:3]:
                op[x, y] = WHITE
    return out


def s(*vals):
    return [v * SS for v in vals]


def from_silhouette(raw: Path, box: int = 22, thresh: int = 110):
    """Turn a big flat black-on-white silhouette into a 40x40 glyph drawer.

    This is the half that makes a generated image usable at icon size. The
    generator is asked for a STENCIL -- flat black shape, white ground, no
    shading -- because that is the only thing that survives being crushed to
    a 20px 1-bit mask; a rendered, shaded illustration turns to mud.

    Area-average down (BOX) and then threshold BELOW the midpoint: a straight
    50% cut eats thin features like an ankle or a wrist, and the shape falls
    apart into disconnected islands.
    """
    im = Image.open(raw).convert("L")
    mask = im.point(lambda v: 255 if v < 128 else 0)
    bbox = mask.getbbox()
    if bbox is None:
        raise SystemExit(f"{raw}: no dark shape found")
    mask = mask.crop(bbox)
    w, h = mask.size
    scale = box / float(max(w, h))
    tw, th = max(1, round(w * scale)), max(1, round(h * scale))
    small = mask.resize((tw * SS, th * SS), Image.LANCZOS).resize((tw, th), Image.BOX)
    ox, oy = (SIZE - tw) // 2, (SIZE - th) // 2

    def draw_fn(d: ImageDraw.ImageDraw) -> None:
        sp = small.load()
        for x in range(tw):
            for y in range(th):
                if sp[x, y] >= thresh:
                    d.rectangle(s(ox + x, oy + y, ox + x + 1, oy + y + 1), fill=255)
    return draw_fn


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default=str(UI))
    ap.add_argument("--box", type=int, default=30,
                    help="glyph size inside the 40px button. 30 is what the "
                         "shipped icons use: at 20 the fist's knuckles break "
                         "into disconnected crumbs.")
    a = ap.parse_args()
    out = Path(a.outdir)
    out.mkdir(parents=True, exist_ok=True)
    # The frame is lifted from a live button so a re-cut can never drift from
    # the rest of the set.
    base = blank_button(UI / "btn_beer.png")
    for name, raw in (("btn_punch", "btn_punch_raw.png"),
                      ("btn_kick", "btn_kick_boot_raw.png")):
        img = stamp(base, from_silhouette(RAW / raw, box=a.box))
        img.save(out / f"{name}.png")
        print(f"  wrote {out / name}.png  (from {raw}, box={a.box})")


if __name__ == "__main__":
    main()
