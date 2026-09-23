#!/usr/bin/env python3
"""Knock the night sky out of a generated venue EXTERIOR.

Venue exteriors ship as 640x360 RGBA with the building cut out on
transparency, because scenes/street.gd draws them as a Sprite2D at z_index -5
straight onto the street -- an opaque rectangle paints a black box over the
background. The generator, though, returns a full opaque scene. This is the
step in between.

    python3 helper-tools/skycut.py raw.png cut.png [--step 15]
    python3 helper-tools/skycut.py raw.png cut.png --compose 640x360

`--compose` also lays the cut-out onto the game canvas: trimmed to its alpha,
cropped SYMMETRICALLY about the original centre (street.gd centres the sprite
on the venue's x and the prompt puts the door at the frame's bottom centre, so
an off-centre crop walks the player into a wall), scaled to fit, and bottom
aligned so the building's base lands on the ground line.

HOW IT CUTS, and why it is not a flood fill
-------------------------------------------
One strictly vertical walk per column: go down from the top and stop at the
first hard colour step, which is the silhouette edge. That absorbs a graded
sky (these skies run dark at the top to light at the horizon) while being
structurally unable to wander sideways into the building.

Two earlier approaches are recorded here because both look reasonable and both
failed on real art:

* **Flood fill with a neighbour-drift rule** (a pixel joins the sky if it is
  close to the neighbour it spread from). Handles a gradient, but drift lets
  it creep through masonry one small step at a time -- it ate the graveyard
  wall and Purgatory's facade, leaving only fragments.
* **Flood fill referenced to each column's top pixel.** No drift, but a fixed
  tolerance cannot span a smooth gradient: tight leaves a grey band behind the
  building, loose starts eating the building.

WHEN THIS TOOL IS THE WRONG ANSWER
----------------------------------
* **Full-bleed art.** If the generator returned a wall that runs edge to edge
  with no sky (prompts containing words like "endless facade" reliably do
  this), there is nothing to cut. Regenerate, insisting the whole structure is
  visible with empty night sky above and beyond BOTH side edges.
* **Fog/mist.** Mist makes the sky/building boundary soft and there is no hard
  step to stop at. Regenerate with "ABSOLUTELY NO fog, NO mist, NO haze".

Higgsfield's `image_background_remover` (1 credit) is the other option and is
excellent when the building is unambiguously the subject -- but it is
SALIENCE based, so on a facade it may decide the subject is the neon sign or
the parked hearses and delete the building behind them. It also ghosted a
glowing neon sign into near-transparency. Check what comes back.

Needs Pillow.
"""

import argparse

from PIL import Image


def sky_cut(src: Image.Image, step: int = 15, work: int = 1024) -> Image.Image:
    """RGBA copy of `src` with the sky above the silhouette made clear."""
    im = src.convert("RGBA")
    w0, h0 = im.size
    im = im.resize((work, max(1, int(h0 * work / w0))), Image.LANCZOS)
    w, h = im.size
    px = im.load()
    a = Image.new("L", (w, h), 255)
    ap = a.load()
    s2 = step * step
    for x in range(w):
        prev = px[x, 0][:3]
        for y in range(h):
            c = px[x, y][:3]
            if ((c[0] - prev[0]) ** 2 + (c[1] - prev[1]) ** 2
                    + (c[2] - prev[2]) ** 2) > s2:
                break                      # hard edge: silhouette starts here
            ap[x, y] = 0
            prev = c
    im.putalpha(a)
    return im.resize((w0, h0), Image.LANCZOS)


def compose(cut: Image.Image, size=(640, 360)) -> Image.Image:
    """Lay a cut-out onto the venue canvas: centred on the door, base on the ground."""
    W, H = cut.size
    bb = cut.getchannel("A").getbbox()
    if bb is None:
        raise SystemExit("nothing opaque left after the cut")
    cx = W / 2.0
    half = max(cx - bb[0], bb[2] - cx)      # symmetric about the ORIGINAL centre
    art = cut.crop((int(max(0, cx - half)), bb[1], int(min(W, cx + half)), bb[3]))
    s = min(size[0] / art.width, size[1] / art.height)
    art = art.resize((max(1, int(art.width * s)), max(1, int(art.height * s))),
                     Image.LANCZOS)
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    out.alpha_composite(art, ((size[0] - art.width) // 2, size[1] - art.height))
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("dest")
    ap.add_argument("--step", type=int, default=15,
                    help="colour step that counts as the silhouette edge (default 15)")
    ap.add_argument("--compose", metavar="WxH", default=None,
                    help="also lay it on the venue canvas, e.g. 640x360")
    args = ap.parse_args()

    out = sky_cut(Image.open(args.src), args.step)
    if args.compose:
        w, h = (int(v) for v in args.compose.lower().split("x"))
        out = compose(out, (w, h))
    out.save(args.dest)

    ch = out.getchannel("A")
    total = out.size[0] * out.size[1]
    clear = sum(1 for v in ch.get_flattened_data() if v < 10)
    print(f"{args.src} -> {args.dest}  {out.size}  "
          f"transparent {100 * clear / total:.1f}%  bbox={ch.getbbox()}")


if __name__ == "__main__":
    main()
