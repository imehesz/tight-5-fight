#!/usr/bin/env python3
"""Generate placeholder pixel-art assets for Open Mic Night!

Writes PNGs into assets/gen/. All art is deliberately crude placeholder
pixel art meant to be replaced by real sprites later (same paths/sizes).

Run:  python3 tools/gen_assets.py
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "assets", "gen")

# --- body sheet layout (must match scripts/character_factory.gd) ---
FRAME_W, FRAME_H = 32, 48
SHEET_COLS = 4
ANIM_ROWS = ["idle", "walk", "punch", "kick", "duck", "hit", "defeated"]
FRAME_COUNTS = {"idle": 2, "walk": 4, "punch": 3, "kick": 3, "duck": 1, "hit": 1, "defeated": 1}

SKIN = (233, 192, 152, 255)
SHOE = (38, 32, 44, 255)
MALE = {"top": (66, 98, 200, 255), "bottom": (46, 46, 72, 255)}
FEMALE = {"top": (202, 64, 128, 255), "bottom": (122, 42, 92, 255)}


def canvas(w, h, color=(0, 0, 0, 0)):
    return Image.new("RGBA", (w, h), color)


def rect(d, x0, y0, x1, y1, c):
    d.rectangle([x0, y0, x1, y1], fill=c)


# ---------------------------------------------------------------- bodies
def draw_neck(d, dy=0, dx=0):
    rect(d, 14 + dx, 9 + dy, 17 + dx, 12 + dy, SKIN)


def draw_torso(d, p, female, dy=0, dx=0):
    if female:
        rect(d, 10 + dx, 12 + dy, 21 + dx, 24 + dy, p["top"])
        rect(d, 9 + dx, 24 + dy, 22 + dx, 32 + dy, p["top"])  # dress skirt
    else:
        rect(d, 10 + dx, 12 + dy, 21 + dx, 28 + dy, p["top"])
        rect(d, 10 + dx, 28 + dy, 21 + dx, 29 + dy, SHOE)  # belt


def draw_arms_side(d, p, dy=0, dx=0):
    for ax in (7, 22):
        rect(d, ax + dx, 13 + dy, ax + 2 + dx, 18 + dy, p["top"])   # sleeve
        rect(d, ax + dx, 18 + dy, ax + 2 + dx, 26 + dy, SKIN)       # forearm


def draw_legs_stand(d, p, female, dy=0, dx=0):
    top = 32 if female else 29
    leg = SKIN if female else p["bottom"]
    rect(d, 11 + dx, top + dy, 14 + dx, 44, leg)
    rect(d, 17 + dx, top + dy, 20 + dx, 44, leg)
    rect(d, 10 + dx, 44, 15 + dx, 47, SHOE)
    rect(d, 16 + dx, 44, 21 + dx, 47, SHOE)


def draw_base(d, p, female, dy=0, dx=0):
    draw_neck(d, dy, dx)
    draw_torso(d, p, female, dy, dx)
    draw_arms_side(d, p, dy, dx)
    draw_legs_stand(d, p, female, dy, dx)


def frame_idle(d, p, female, i):
    draw_base(d, p, female, dy=(0 if i == 0 else 1))


def frame_walk(d, p, female, i):
    leg = SKIN if female else p["bottom"]
    top = 32 if female else 29
    if i in (1, 3):
        draw_base(d, p, female, dy=1)
        return
    draw_neck(d)
    draw_torso(d, p, female)
    fwd = 1 if i == 0 else -1
    # swinging arms
    for ax, s in ((7, -fwd), (22, fwd)):
        rect(d, ax, 13, ax + 2, 18, p["top"])
        rect(d, ax + 2 * s, 18, ax + 2 + 2 * s, 26, SKIN)
    # scissored legs
    d.line([13, top, 9 + 4 * fwd, 45], fill=leg, width=4)
    d.line([19, top, 23 - 4 * fwd, 45], fill=leg, width=4)
    rect(d, 7 + 4 * fwd, 44, 12 + 4 * fwd, 47, SHOE)
    rect(d, 21 - 4 * fwd, 44, 26 - 4 * fwd, 47, SHOE)


def frame_punch(d, p, female, i):
    draw_neck(d)
    draw_torso(d, p, female)
    draw_legs_stand(d, p, female)
    if i == 1:  # extended jab toward +x (facing right)
        rect(d, 20, 15, 29, 19, SKIN)
        rect(d, 29, 14, 31, 20, SKIN)          # fist
        rect(d, 8, 16, 12, 22, SKIN)           # guard arm
        rect(d, 7, 13, 10, 17, p["top"])
    else:  # guard / windup
        for ax in (8, 21):
            rect(d, ax, 14, ax + 2, 18, p["top"])
            rect(d, ax, 17, ax + 3, 22, SKIN)


def frame_kick(d, p, female, i):
    leg = SKIN if female else p["bottom"]
    top = 32 if female else 29
    draw_neck(d)
    draw_torso(d, p, female)
    draw_arms_side(d, p)
    # standing leg
    rect(d, 11, top, 14, 44, leg)
    rect(d, 10, 44, 15, 47, SHOE)
    if i == 1:  # leg extended
        rect(d, 17, 26, 28, 31, leg)
        rect(d, 27, 24, 31, 32, SHOE)
    else:  # knee raised
        rect(d, 17, top, 21, 38, leg)
        rect(d, 17, 36, 22, 40, SHOE)


def frame_duck(d, p, female, i):
    rect(d, 14, 21, 17, 24, SKIN)              # neck, lowered
    rect(d, 10, 24, 21, 34, p["top"])
    rect(d, 8, 26, 10, 34, SKIN)               # arm front
    rect(d, 22, 26, 24, 34, SKIN)
    rect(d, 10, 34, 21, 44, p["bottom"] if not female else p["top"])
    rect(d, 9, 44, 21, 47, SHOE)


def frame_hit(d, p, female, i):
    draw_neck(d, dy=1, dx=-2)
    draw_torso(d, p, female, dy=1, dx=-2)
    draw_legs_stand(d, p, female)
    # arms flung up
    d.line([7, 20, 3, 12], fill=SKIN, width=3)
    d.line([22, 20, 26, 12], fill=SKIN, width=3)


def frame_defeated(d, p, female, i):
    rect(d, 10, 40, 12, 44, SKIN)              # neck (head lies at left)
    rect(d, 12, 39, 22, 44, p["top"])          # torso horizontal
    leg = SKIN if female else p["bottom"]
    rect(d, 22, 40, 28, 44, leg)
    rect(d, 28, 39, 31, 44, SHOE)
    rect(d, 14, 36, 17, 39, SKIN)              # arm sticking up


FRAME_FUNCS = {
    "idle": frame_idle, "walk": frame_walk, "punch": frame_punch,
    "kick": frame_kick, "duck": frame_duck, "hit": frame_hit,
    "defeated": frame_defeated,
}


def gen_body(female, path):
    sheet = canvas(SHEET_COLS * FRAME_W, len(ANIM_ROWS) * FRAME_H)
    p = FEMALE if female else MALE
    for row, anim in enumerate(ANIM_ROWS):
        for i in range(FRAME_COUNTS[anim]):
            frame = canvas(FRAME_W, FRAME_H)
            FRAME_FUNCS[anim](ImageDraw.Draw(frame), p, female, i)
            sheet.paste(frame, (i * FRAME_W, row * FRAME_H))
    sheet.save(path)


# ---------------------------------------------------------------- heads
def gen_head(path, skin, hair, style, extra=None):
    img = canvas(16, 16)
    d = ImageDraw.Draw(img)
    rect(d, 3, 4, 12, 13, skin)                    # face
    rect(d, 2, 6, 3, 11, skin)
    rect(d, 12, 6, 13, 11, skin)
    if style == "afro":
        d.ellipse([0, 0, 15, 9], fill=hair)
        rect(d, 3, 4, 12, 5, hair)
    elif style == "bald":
        rect(d, 4, 3, 11, 4, skin)
        rect(d, 5, 3, 7, 3, (255, 255, 255, 160))  # shine
    elif style == "bob":
        rect(d, 2, 2, 13, 5, hair)
        rect(d, 1, 4, 3, 12, hair)
        rect(d, 12, 4, 14, 12, hair)
    elif style == "long":
        rect(d, 2, 2, 13, 4, hair)
        rect(d, 1, 3, 3, 15, hair)
        rect(d, 12, 3, 14, 15, hair)
    elif style == "short":
        rect(d, 2, 2, 13, 5, hair)
    elif style == "bun":
        rect(d, 3, 3, 12, 4, hair)
        rect(d, 6, 0, 9, 3, hair)
    elif style == "slick":
        rect(d, 2, 2, 13, 4, hair)
        rect(d, 11, 3, 13, 6, hair)
    # eyes
    rect(d, 5, 7, 6, 8, (20, 20, 25, 255))
    rect(d, 9, 7, 10, 8, (20, 20, 25, 255))
    if extra == "glasses":
        rect(d, 4, 6, 7, 9, (10, 10, 10, 255))
        rect(d, 8, 6, 11, 9, (10, 10, 10, 255))
        rect(d, 7, 7, 8, 7, (10, 10, 10, 255))
    if extra == "beard":
        rect(d, 4, 10, 11, 13, (94, 66, 40, 255))
        rect(d, 6, 10, 9, 11, skin)
    # mouth
    if extra == "frown":
        rect(d, 6, 12, 9, 12, (120, 40, 40, 255))
        rect(d, 5, 11, 5, 11, (120, 40, 40, 255))
        rect(d, 10, 11, 10, 11, (120, 40, 40, 255))
    elif extra == "lipstick":
        rect(d, 6, 11, 9, 12, (220, 40, 80, 255))
    elif extra == "cigar":
        rect(d, 6, 11, 9, 11, (60, 20, 20, 255))
        rect(d, 10, 10, 13, 12, (110, 70, 40, 255))
        rect(d, 13, 10, 14, 11, (255, 120, 0, 255))
    elif extra != "beard":
        rect(d, 6, 11, 9, 11, (150, 70, 60, 255))
    img.save(path)


# ---------------------------------------------------------------- venues
def upscale(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def gen_venue_exterior(path, name, wall, sign_bg):
    img = canvas(80, 60, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rect(d, 2, 8, 77, 59, wall)                          # facade
    rect(d, 0, 4, 79, 10, (50, 40, 45, 255))             # roof band
    rect(d, 6, 14, 73, 24, sign_bg)                      # sign
    for wx in (8, 56):                                   # windows
        rect(d, wx, 30, wx + 14, 44, (255, 230, 140, 255))
        rect(d, wx + 1, 31, wx + 13, 43, (90, 70, 50, 255))
        rect(d, wx + 2, 32, wx + 12, 42, (255, 230, 140, 255))
    rect(d, 33, 40, 47, 59, (96, 58, 34, 255))           # door, bottom center
    rect(d, 34, 41, 46, 59, (120, 76, 44, 255))
    rect(d, 43, 49, 44, 51, (240, 220, 120, 255))        # handle
    big = upscale(img, 2)                                # -> 160x120
    bd = ImageDraw.Draw(big)
    bd.text((17, 32), name.upper()[:16], fill=(20, 15, 20, 255))
    big.save(path)


def gen_venue_interior(path, wall, floor):
    img = canvas(160, 90)
    d = ImageDraw.Draw(img)
    rect(d, 0, 0, 159, 64, wall)                          # wall
    rect(d, 0, 64, 159, 89, floor)                        # floor
    for y in range(64, 90, 6):
        d.line([0, y, 159, y], fill=tuple(max(0, c - 25) for c in floor[:3]) + (255,), width=1)
    rect(d, 55, 44, 105, 52, (70, 45, 30, 255))           # stage platform
    rect(d, 55, 52, 105, 64, (90, 58, 38, 255))
    rect(d, 78, 30, 79, 52, (160, 160, 170, 255))         # mic stand
    rect(d, 76, 27, 81, 31, (60, 60, 70, 255))            # mic
    glow = canvas(160, 90)
    ImageDraw.Draw(glow).polygon([(70, 0), (90, 0), (100, 46), (60, 46)],
                                 fill=(255, 255, 210, 40))  # spotlight
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img)
    rect(d, 126, 46, 158, 64, (70, 40, 26, 255))          # bar counter
    rect(d, 126, 44, 158, 47, (110, 70, 40, 255))
    for sx in (6, 24, 42):                                # stools
        rect(d, sx, 56, sx + 8, 59, (140, 40, 40, 255))
        rect(d, sx + 3, 59, sx + 5, 66, (60, 40, 30, 255))
    rect(d, 10, 10, 58, 24, (25, 20, 30, 255))            # wall sign
    big = upscale(img, 4)                                 # -> 640x360
    bd = ImageDraw.Draw(big)
    bd.text((58, 62), "OPEN MIC NIGHT", fill=(255, 220, 120, 255))
    big.save(path)


def gen_street_tile(path):
    img = canvas(160, 180)
    d = ImageDraw.Draw(img)
    rect(d, 0, 0, 159, 129, (24, 22, 48, 255))            # night sky
    for sx, sy in ((14, 12), (48, 28), (90, 8), (130, 20), (70, 40), (150, 45)):
        rect(d, sx, sy, sx, sy, (230, 230, 255, 255))     # stars
    # building silhouettes
    for bx, bw, bh, c in ((0, 34, 70, (38, 34, 66)), (36, 30, 88, (46, 40, 74)),
                          (68, 40, 60, (34, 30, 60)), (110, 48, 80, (44, 38, 70))):
        rect(d, bx, 130 - bh, bx + bw - 1, 130, c + (255,))
        for wy in range(134 - bh, 126, 12):
            for wx in range(bx + 4, bx + bw - 5, 9):
                lit = (wx * 7 + wy * 13) % 3 != 0
                wc = (255, 226, 130, 255) if lit else (28, 26, 50, 255)
                rect(d, wx, wy, wx + 3, wy + 4, wc)
    rect(d, 0, 130, 159, 132, (90, 88, 100, 255))         # curb top
    rect(d, 0, 132, 159, 164, (120, 116, 128, 255))       # sidewalk
    for lx in range(0, 160, 32):
        d.line([lx, 132, lx, 164], fill=(96, 92, 104, 255), width=1)
    rect(d, 0, 164, 159, 166, (70, 68, 78, 255))          # curb face
    rect(d, 0, 166, 159, 179, (48, 46, 54, 255))          # road
    rect(d, 8, 172, 40, 174, (210, 200, 90, 255))         # road stripe
    rect(d, 88, 172, 120, 174, (210, 200, 90, 255))
    upscale(img, 2).save(path)                            # -> 320x360


# ---------------------------------------------------------------- ui / props
def gen_button(path, glyph):
    img = canvas(40, 40)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, 38, 38], radius=8, fill=(25, 25, 38, 150),
                        outline=(240, 240, 250, 200), width=2)
    w = (245, 245, 250, 230)
    if glyph == "left":
        d.polygon([(26, 10), (26, 30), (12, 20)], fill=w)
    elif glyph == "right":
        d.polygon([(14, 10), (14, 30), (28, 20)], fill=w)
    elif glyph == "up":
        d.polygon([(10, 26), (30, 26), (20, 12)], fill=w)
    elif glyph == "down":
        d.polygon([(10, 14), (30, 14), (20, 28)], fill=w)
    elif glyph == "punch":
        d.ellipse([11, 11, 29, 29], fill=w)
        rect(d, 13, 19, 27, 21, (25, 25, 38, 255))
    elif glyph == "kick":
        rect(d, 12, 10, 18, 28, w)
        rect(d, 12, 24, 30, 30, w)
    img.save(path)


def gen_bottle(path):
    img = canvas(8, 16)
    d = ImageDraw.Draw(img)
    rect(d, 3, 0, 4, 4, (70, 140, 60, 255))               # neck
    rect(d, 1, 4, 6, 14, (60, 130, 50, 255))              # body
    rect(d, 2, 5, 3, 10, (140, 210, 120, 255))            # shine
    rect(d, 3, 0, 4, 1, (180, 160, 90, 255))              # cap
    img.save(path)


# ---------------------------------------------------------------- main
def main():
    dirs = {k: os.path.join(OUT, k) for k in ("bodies", "heads", "venues", "street", "ui", "props")}
    for p in dirs.values():
        os.makedirs(p, exist_ok=True)

    gen_body(False, os.path.join(dirs["bodies"], "body_male.png"))
    gen_body(True, os.path.join(dirs["bodies"], "body_female.png"))

    heads = [
        ("chuckles", (233, 192, 152, 255), (230, 120, 30, 255), "afro", None),
        ("dave", (200, 160, 120, 255), None, "bald", "glasses"),
        ("sue", (240, 200, 165, 255), (240, 210, 90, 255), "bob", "lipstick"),
        ("linda", (190, 140, 100, 255), (150, 70, 200, 255), "long", None),
        ("pete", (225, 180, 140, 255), (110, 75, 45, 255), "short", "beard"),
        ("greta", (235, 200, 170, 255), (180, 180, 190, 255), "bun", "frown"),
        ("boss_lou", (215, 170, 130, 255), (35, 30, 30, 255), "slick", "cigar"),
    ]
    for name, skin, hair, style, extra in heads:
        gen_head(os.path.join(dirs["heads"], name + ".png"), skin, hair, style, extra)

    venues = [
        ("venue1", "The Giggle Shack", (140, 60, 60, 255), (255, 210, 90, 255),
         (70, 30, 40, 255), (110, 74, 48, 255)),
        ("venue2", "Laff Lounge", (60, 90, 140, 255), (120, 230, 200, 255),
         (30, 40, 70, 255), (96, 84, 70, 255)),
        ("venue3", "The Snort Cellar", (90, 70, 120, 255), (240, 140, 220, 255),
         (45, 30, 60, 255), (86, 64, 78, 255)),
    ]
    for vid, name, wall, sign, iwall, ifloor in venues:
        gen_venue_exterior(os.path.join(dirs["venues"], vid + "_ext.png"), name, wall, sign)
        gen_venue_interior(os.path.join(dirs["venues"], vid + "_int.png"), iwall, ifloor)

    gen_street_tile(os.path.join(dirs["street"], "street_tile.png"))

    for g in ("left", "right", "up", "down", "punch", "kick"):
        gen_button(os.path.join(dirs["ui"], "btn_%s.png" % g), g)
    gen_bottle(os.path.join(dirs["props"], "bottle.png"))
    print("assets written to", OUT)


if __name__ == "__main__":
    main()
