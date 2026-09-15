#!/usr/bin/env python3
"""Drop an advertiser's artwork onto the green billboard in the promo clip.

What goes out to a potential advertiser is a capture of the game with one
in-world billboard left neon green, so their art can be dropped into it. This
is the tool that does the dropping — no AI anywhere, it is a chroma key:

  python3 helper-tools/promo-generator.py path/to/their-logo.png

and you get `promo_their-logo.gif` (animated) plus `promo_their-logo.png`
(the still) next to the image you passed in.

The billboard is a flat, axis-aligned rectangle that scrolls horizontally with
the parallax skyline, so every frame is found and filled independently — no
frame numbers, sizes or coordinates are baked in here, which is what lets the
capture be re-recorded without touching this file. It has already survived two
such swaps (1920x1080/90 frames -> 720x480/108 -> 720x480/122), the last of
which also added a title card, a zoom transition and a new HUD.

Four things make this more than "paste a rectangle over the green":

  * THE HUD IS DRAWN ON TOP OF THE BILLBOARD. The round timer box clips the
    top-left corner and another bar crosses the bottom edge. Painting the whole
    rectangle would bury them and the HUD would appear to vanish behind a
    building. So the rectangle is filled and then the real occluders are put
    back from the original frame.
  * THE HUD IS ALSO GREEN IN PLACES. The health bar is a 115x10 slab of the
    same neon, and the player's portrait has a green frame — which is why the
    billboard is the largest green BLOB rather than the bounding box of
    everything green. See BLOB_SCALE.
  * NOT EVERY FRAME HAS A BILLBOARD. The clip opens on a title card, and the
    frames that follow zoom in, so the rectangle changes size as well as
    position. Both fall out of measuring every frame on its own; a title frame
    is passed through untouched. See do_gif() for the pixel-format trap that
    lurks in "untouched".
  * THE GREEN IS HEAVILY DITHERED. The source is a 256-colour GIF, so the
    billboard alternates between two greens every single pixel (201 colour
    changes across its 202-pixel width). Nothing here may test for an exact
    colour; the mask asks whether green leads both other channels instead.

An earlier capture also caught the MOUSE POINTER, once inside the green and
once sitting on the billboard's own frame just outside it. Both are handled —
see occluders() and clean_pointer() — and both are no-ops on a clean recording,
so the handling is left in against the next one.

Filling the whole rectangle and restoring occluders, rather than compositing
through the green mask itself, is deliberate: it gives a hard, clean edge with
no surviving green fringe where the billboard's dark frame blends into the key.

Run `--help` for the options. The three that matter:

  --fit    contain (default) letterboxes so an advertiser's logo is NEVER
           cropped; cover fills the billboard edge to edge and crops the
           overflow; stretch distorts to fit exactly.
  --out    where the results go (default: next to the image you passed in).
  --scale  shrink the animation to fit an email. Swapping flat green for a
           photograph costs about half again in file size and there is no way
           round that: measured on this clip, dropping to a 64-colour palette
           saves 17% and wrecks the artwork, and resampling to 75% comes out
           BIGGER than full size because lanczos invents colours between the
           pixel-art's flat ones. 0.5 is the one setting that genuinely halves
           it.

Needs Pillow and ffmpeg, both of which the other helper-tools already assume.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from collections import deque

from PIL import Image, ImageChops, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_GIF = os.path.join(ROOT, "requirements", "promo-generator", "green-promo2.gif")
DEFAULT_STILL = os.path.join(ROOT, "requirements", "promo-generator", "green-promo2_static.png")

# --- keying -----------------------------------------------------------------
# A pixel is "green" when the green channel both clears a floor and leads the
# other two by a margin. Written this way rather than as a distance to one RGB
# value because GIF quantisation splits the billboard across at least five
# greens ((0,255,36), (36,255,36), (0,255,0), (0,219,0), (0,219,36)) and
# dithers between them every pixel.
GREEN_FLOOR = 110
GREEN_LEAD = 60

# Erosion used to find the billboard: anything thinner than this in either
# axis is not the billboard. The HUD carries small green elements of its own
# (the pickup counters top-left), and this is what keeps them out of it.
ERODE = 7

# Erosion alone is not enough to isolate the billboard, so the largest
# surviving BLOB is taken rather than the bounding box of everything green.
# The health bar added in the second capture is about 115x10 and sails through
# a 7px erosion; taking the bounding box of all of it stretched the billboard
# from the bar on the far left to the billboard on the right, which is a
# rectangle covering most of the screen. Blob against blob there is no contest
# — 24,000 pixels against 435 — so this is decided by a wide margin rather
# than by a threshold that would need retuning per capture.
# The search runs on a mask shrunk by this factor, purely for speed; the box it
# finds is then re-measured against the full-resolution mask.
BLOB_SCALE = 4

# A non-green blob inside the billboard is a real occluder — HUD drawn over the
# top — and gets restored from the source frame. Below this it is the mouse
# pointer or dither speckle and gets painted over. The pointer is ~90px; the
# timer box is ~1200. Two orders of magnitude of daylight between them.
OCCLUDER_MIN_PX = 250


def green_mask(im):
    """0/255 mask of the keyable green in `im`. All C-speed channel ops."""
    r, g, b = im.convert("RGB").split()
    lead = ImageChops.subtract(g, ImageChops.lighter(r, b))
    return ImageChops.multiply(
        lead.point(lambda v: 255 if v > GREEN_LEAD else 0),
        g.point(lambda v: 255 if v > GREEN_FLOOR else 0),
    )


def _largest_blob(small):
    """Bounding box of the biggest connected run of white in `small`."""
    w, h = small.size
    px = small.load()
    seen = bytearray(w * h)
    best = None
    for sy in range(h):
        for sx in range(w):
            if not px[sx, sy] or seen[sy * w + sx]:
                continue
            q = deque([(sx, sy)])
            seen[sy * w + sx] = 1
            n = 0
            x0 = x1 = sx
            y0 = y1 = sy
            while q:
                cx, cy = q.popleft()
                n += 1
                x0, x1 = min(x0, cx), max(x1, cx)
                y0, y1 = min(y0, cy), max(y1, cy)
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h and px[nx, ny] and not seen[ny * w + nx]:
                        seen[ny * w + nx] = 1
                        q.append((nx, ny))
            if best is None or n > best[0]:
                best = (n, (x0, y0, x1 + 1, y1 + 1))
    return best[1] if best else None


def billboard_rect(mask):
    """(x0, y0, x1, y1) of the billboard, or None if this frame has no green.

    Eroding first deletes the small green things in the HUD, then the largest
    surviving blob is the billboard — see BLOB_SCALE for why the blob search is
    needed and not just the bounding box of what survives.

    The blob is located on a shrunken mask for speed and then re-measured
    against the full-resolution one, so the coordinates are exact rather than
    rounded to BLOB_SCALE. The erosion is undone on the box, not the pixels.
    """
    pad = ERODE // 2
    eroded = mask.filter(ImageFilter.MinFilter(ERODE))
    small = eroded.resize((max(eroded.width // BLOB_SCALE, 1),
                           max(eroded.height // BLOB_SCALE, 1)), Image.NEAREST)
    box = _largest_blob(small)
    if box is None:
        # Too small to survive the shrink, but there may still be a billboard.
        box_full = eroded.getbbox()
        if box_full is None:
            return None
    else:
        s = BLOB_SCALE
        region = (max(box[0] * s - s, 0), max(box[1] * s - s, 0),
                  min(box[2] * s + s, eroded.width),
                  min(box[3] * s + s, eroded.height))
        inner = eroded.crop(region).getbbox()
        if inner is None:
            return None
        box_full = (inner[0] + region[0], inner[1] + region[1],
                    inner[2] + region[0], inner[3] + region[1])
    x0, y0, x1, y1 = box_full
    return (max(x0 - pad, 0), max(y0 - pad, 0),
            min(x1 + pad, mask.width), min(y1 + pad, mask.height))


def occluders(mask, rect):
    """Mask of pixels inside `rect` to restore from the source frame.

    Everything in the rectangle that is not green is a candidate. The ones we
    keep are those big enough to be HUD; small islands are the mouse pointer
    and dither noise and are left for the artwork to cover. Blobs touching the
    rectangle's edge are kept whatever their size — that is the timer box
    biting into the corner, and half-covering it looks worse than either
    extreme.
    """
    w, h = rect[2] - rect[0], rect[3] - rect[1]
    holes = ImageChops.invert(mask.crop(rect))
    px = holes.load()
    keep = Image.new("L", (w, h), 0)
    kpx = keep.load()
    seen = bytearray(w * h)
    for sy in range(h):
        for sx in range(w):
            if not px[sx, sy] or seen[sy * w + sx]:
                continue
            q = deque([(sx, sy)])
            seen[sy * w + sx] = 1
            blob = []
            edge = False
            while q:
                cx, cy = q.popleft()
                blob.append((cx, cy))
                if cx == 0 or cy == 0 or cx == w - 1 or cy == h - 1:
                    edge = True
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h and px[nx, ny] and not seen[ny * w + nx]:
                        seen[ny * w + nx] = 1
                        q.append((nx, ny))
            if edge or len(blob) >= OCCLUDER_MIN_PX:
                for cx, cy in blob:
                    kpx[cx, cy] = 255
    return keep


# --- pointer on the frame ---------------------------------------------------
# How far out from the billboard to look for the frame, as a fraction of its
# width. Only ever used as a ceiling: the walk stops at the first column that
# is not frame, so the band sizes itself to whatever the art actually has.
FRAME_SEARCH = 0.06
# 1-norm colour distance at which a pixel stops being "this column's frame".
# The frame bands are flat to within about 10; the pointer's dark pixels are
# 385 away. Anywhere in between would do.
FRAME_TOL = 60
# A pointer is small and COMPACT, and that shape test is what does the work
# here rather than any pixel count. The frame bands carry a dark inner edge
# line running their whole height, which is every bit as much of a colour
# outlier as the pointer is and is real art — sizing by area alone flattens it.
# A blob only gets repaired if it fits inside a box this share of the
# billboard, in BOTH axes: the pointer is about 3% x 8%, the edge line is 100%
# tall and is thrown out on the second test.
POINTER_MAX_W = 0.10
POINTER_MAX_H = 0.20


# How deep inside the billboard an occluder has to reach before a blob on the
# frame counts as part of it, and how far in to bother looking, both as a share
# of the billboard's width. The first number must clear the dark border that
# hugs the inside of the rectangle; the second keeps the search local so a HUD
# element elsewhere on the same rows is not mistaken for this blob's body.
PROBE_SKIN = 0.025
PROBE_DEPTH = 0.09


def _reaches_inside(keep, rect, by0, by1, direction):
    """True if an occluder sits well inside the billboard on these rows."""
    w = rect[2] - rect[0]
    skin = max(int(w * PROBE_SKIN), 3)
    depth = max(int(w * PROBE_DEPTH), skin + 4)
    for y in range(max(by0 - 2, rect[1]), min(by1 + 3, rect[3])):
        for d in range(skin, min(depth, w)):
            x = d if direction < 0 else w - 1 - d
            if keep.getpixel((x, y - rect[1])):
                return True
    return False


def _column_mode(px, x, y0, y1):
    counts = {}
    for y in range(y0, y1):
        c = px[x, y]
        counts[c] = counts.get(c, 0) + 1
    return max(counts.items(), key=lambda kv: kv[1])[0]


def clean_pointer(out, rect, keep):
    """Erase small artefacts sitting on the billboard's vertical side frames.

    The recording's mouse pointer is on the right-hand frame in the still, just
    outside the key, so the compositing never sees it. What makes it safe to
    repair rather than inpaint is that those side frames are flat vertical
    bands: the whole column is one colour, so the colour a pointer pixel should
    have had is simply that column's most common one.

    The band is found by walking outward from the billboard until a column is
    no longer the frame colour, which is what keeps this off the night sky —
    step into it and the lit windows would read as artefacts and be erased.

    `keep` is the occluder mask from occluders(), and blobs whose object
    carries on inside the billboard are spared: the HUD's beer mug sits on the
    bottom-right corner and spills a few pixels onto the frame, which is
    SMALLER than the pointer and so cannot be told from it by size. What
    separates them is that the mug continues inside and the pointer does not.

    "Continues inside" has to mean reaching past PROBE_SKIN, not merely
    touching: the billboard's own dark border runs the full height just within
    the rectangle and is itself an occluder, so plain adjacency calls every
    blob on either band attached and nothing is ever repaired.
    """
    px = out.load()
    x0, y0, x1, y1 = rect
    reach = max(int((x1 - x0) * FRAME_SEARCH), 3)
    for direction, start in ((-1, x0 - 1), (1, x1)):
        frame = _column_mode(px, start, y0, y1)
        cols = []
        for step in range(reach):
            x = start + direction * step
            if not (0 <= x < out.width):
                break
            mode = _column_mode(px, x, y0, y1)
            if sum(abs(a - b) for a, b in zip(mode, frame)) > FRAME_TOL:
                break
            cols.append((x, mode))
        if not cols:
            continue
        fixes = dict(cols)
        odd = {(x, y) for x, mode in cols for y in range(y0, y1)
               if sum(abs(a - b) for a, b in zip(px[x, y], mode)) > FRAME_TOL}
        max_w = max((x1 - x0) * POINTER_MAX_W, 3)
        max_h = max((y1 - y0) * POINTER_MAX_H, 3)
        seen = set()
        for seed in odd:
            if seed in seen:
                continue
            q = deque([seed])
            seen.add(seed)
            blob = []
            bx0 = bx1 = seed[0]
            by0 = by1 = seed[1]
            while q:
                cx, cy = q.popleft()
                blob.append((cx, cy))
                bx0, bx1 = min(bx0, cx), max(bx1, cx)
                by0, by1 = min(by0, cy), max(by1, cy)
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        n = (cx + dx, cy + dy)
                        if n in odd and n not in seen:
                            seen.add(n)
                            q.append(n)
            if _reaches_inside(keep, rect, by0, by1, direction):
                continue
            if bx1 - bx0 + 1 <= max_w and by1 - by0 + 1 <= max_h:
                for cx, cy in blob:
                    px[cx, cy] = fixes[cx]


def fit(art, size, mode, bg):
    """`art` resized to exactly `size` under the chosen fit policy."""
    tw, th = size
    if mode == "stretch":
        return art.resize((tw, th), Image.LANCZOS).convert("RGB")
    scale = max(tw / art.width, th / art.height) if mode == "cover" \
        else min(tw / art.width, th / art.height)
    w, h = max(round(art.width * scale), 1), max(round(art.height * scale), 1)
    small = art.resize((w, h), Image.LANCZOS)
    out = Image.new("RGB", (tw, th), bg)
    box = ((tw - w) // 2, (th - h) // 2)
    out.paste(small, box, small if small.mode == "RGBA" else None)
    return out


def place(frame, art, mode, bg, pointer=True):
    """`frame` with the billboard replaced by `art`. Returns None if no green."""
    frame = frame.convert("RGB")
    mask = green_mask(frame)
    rect = billboard_rect(mask)
    if rect is None:
        return None
    w, h = rect[2] - rect[0], rect[3] - rect[1]
    out = frame.copy()
    out.paste(fit(art, (w, h), mode, bg), (rect[0], rect[1]))
    keep = occluders(mask, rect)
    if keep.getbbox() is not None:
        out.paste(frame.crop(rect), (rect[0], rect[1]), keep)
    if pointer:
        clean_pointer(out, rect, keep)
    return out


def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit("ffmpeg failed:\n" + (p.stderr or "")[-2000:])
    return p


def gif_rate(path):
    """Frames per second of `path`, as ffmpeg's own fraction, so the output
    keeps the source's timing rather than being re-timed to a round number."""
    p = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=avg_frame_rate", "-of", "csv=p=0", path],
        capture_output=True, text=True)
    rate = (p.stdout or "").strip()
    return rate if rate and rate not in ("0/0", "N/A") else "25"


def do_gif(src, art, dst, mode, bg, pointer, scale):
    tmp = tempfile.mkdtemp(prefix="promo-")
    try:
        rate = gif_rate(src)
        run(["ffmpeg", "-v", "error", "-i", src, "-vsync", "0",
             os.path.join(tmp, "f%05d.png"), "-y"])
        frames = sorted(f for f in os.listdir(tmp) if f.startswith("f"))
        if not frames:
            sys.exit("no frames decoded from " + src)
        missed = 0
        for i, name in enumerate(frames):
            p = os.path.join(tmp, name)
            done = place(Image.open(p), art, mode, bg, pointer)
            if done is None:
                # No billboard on this one — the clip opens on a title card.
                # It still gets rewritten rather than left as ffmpeg wrote it:
                # ffmpeg decodes GIF frames to RGBA and Pillow saves RGB, and a
                # sequence that changes pixel format part way through loses the
                # odd ones out at encode WITHOUT WARNING. Leaving these alone
                # silently dropped all 15 title frames from the result.
                missed += 1
                Image.open(p).convert("RGB").save(p)
                continue
            done.save(p)
            if (i + 1) % 20 == 0 or i + 1 == len(frames):
                print("    frame %d/%d" % (i + 1, len(frames)))
        # One palette built across the whole clip from the composited frames,
        # so the advertiser's colours get a say in the 256 available rather
        # than inheriting a palette chosen when the billboard was flat green.
        pre = "" if scale == 1.0 else \
            "scale=iw*%g:ih*%g:flags=lanczos," % (scale, scale)
        run(["ffmpeg", "-v", "error", "-framerate", rate,
             "-i", os.path.join(tmp, "f%05d.png"),
             "-filter_complex",
             "[0:v]" + pre + "split[a][b];[a]palettegen=stats_mode=diff[p];"
             "[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle",
             "-loop", "0", dst, "-y"])
        return len(frames), missed
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(
        description="Put an advertiser's image on the promo clip's green billboard.")
    ap.add_argument("image", help="the artwork to drop in")
    ap.add_argument("--out", help="output directory (default: next to the image)")
    ap.add_argument("--fit", choices=("contain", "cover", "stretch"), default="contain",
                    help="contain (default) never crops; cover fills and crops; "
                         "stretch distorts")
    ap.add_argument("--bg", default="#000000",
                    help="letterbox colour behind a 'contain' fit (default black)")
    ap.add_argument("--gif", default=DEFAULT_GIF, help="source animation")
    ap.add_argument("--still", default=DEFAULT_STILL, help="source still")
    ap.add_argument("--no-gif", action="store_true", help="skip the animation")
    ap.add_argument("--no-still", action="store_true", help="skip the still")
    ap.add_argument("--scale", type=float, default=1.0, metavar="F",
                    help="shrink the animation by this factor to hit an email "
                         "size limit (0.5 roughly halves the file). The only "
                         "lever that moves the needle much: palette size and "
                         "dither barely change it, and 0.75 comes out LARGER "
                         "than 1.0 because the resampling invents colours")
    ap.add_argument("--keep-pointer", action="store_true",
                    help="leave the recording's mouse pointer where it sits on "
                         "the billboard frame instead of repairing it")
    a = ap.parse_args()

    if not os.path.exists(a.image):
        sys.exit("no such image: " + a.image)
    art = Image.open(a.image)
    if art.mode not in ("RGB", "RGBA"):
        art = art.convert("RGBA")

    stem = os.path.splitext(os.path.basename(a.image))[0]
    out_dir = a.out or os.path.dirname(os.path.abspath(a.image))
    os.makedirs(out_dir, exist_ok=True)

    if not a.no_still:
        if not os.path.exists(a.still):
            sys.exit("no such still: " + a.still)
        dst = os.path.join(out_dir, "promo_%s.png" % stem)
        done = place(Image.open(a.still), art, a.fit, a.bg, not a.keep_pointer)
        if done is None:
            sys.exit("no green billboard found in " + a.still)
        done.save(dst)
        print("still -> %s  (%.0f KB)" % (dst, os.path.getsize(dst) / 1024))

    if not a.no_gif:
        if not os.path.exists(a.gif):
            sys.exit("no such gif: " + a.gif)
        dst = os.path.join(out_dir, "promo_%s.gif" % stem)
        n, missed = do_gif(a.gif, art, dst, a.fit, a.bg, not a.keep_pointer, a.scale)
        note = "  (%d frames had no billboard and were left alone)" % missed if missed else ""
        print("gif   -> %s  (%d frames, %.1f MB)%s"
              % (dst, n, os.path.getsize(dst) / 1048576, note))


if __name__ == "__main__":
    main()
