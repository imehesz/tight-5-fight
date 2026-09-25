#!/usr/bin/env python3
"""Grab today's WANTED bill off each live edition's main menu, as a PNG.

For every game in wanted-scraper.conf.json it opens
https://games.imstandup.com/tight5fight/<gameID>, clicks past the landing page,
waits for the Godot main menu, screenshots it, crops the left WANTED bill out
at the fixed rect in the conf, paints out the in-game "+10% KO" line and burns
<gameName> into that spot, tilted, in a western font.

    python3 helper-tools/wanted-scraper.py            # headless, all games
    python3 helper-tools/wanted-scraper.py --test     # real visible browser
    python3 helper-tools/wanted-scraper.py --only celebs

The crop rect is hardcoded in the conf because the menu pins the bill at a
fixed spot: 18px from the left edge, vertically centred, lifted 16px for the
nav bar, 105x146 design px. At the conf's 1280x720 viewport (2x the 640x360
design) that is x=36 y=182 w=210 h=292. Change the viewport and the rect has
to change with it. --test also saves the full screenshot so the rect can be
re-tuned by eye.

Needs Playwright (+ its Chromium) and Pillow.
"""
import argparse
import json
import sys
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont
from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
DEFAULT_CONF = HERE / "wanted-scraper.conf.json"
FONT_PATH = HERE / "fonts" / "Rye-Regular.ttf"
BASE_URL = "https://games.imstandup.com/tight5fight/"
# Same ink the game prints the reward line in (WantedPoster.INK).
INK = (46, 31, 18)


def load_conf(path: Path) -> dict:
    conf = json.loads(path.read_text())
    conf.setdefault("viewportWidth", 1280)
    conf.setdefault("viewportHeight", 720)
    conf.setdefault("wantedPosterWidth", 210)
    conf.setdefault("wantedPosterHeight", 292)
    conf.setdefault("landingWaitSec", 2)
    conf.setdefault("gameLoadWaitSec", 10)
    # Both boxes are [x0, y0, x1, y1] inside the cropped poster.
    conf.setdefault("rewardEraseBox", [66, 234, 166, 256])
    conf.setdefault("nameBox", [18, 212, 192, 280])
    conf.setdefault("nameTiltDeg", 6)
    conf.setdefault("outputDir", "wanted-scraper-out")
    return conf


def screenshot_game(page, game_id: str, conf: dict, test: bool) -> Image.Image:
    url = BASE_URL + game_id
    print(f"  -> {url}")
    page.goto(url, wait_until="load")
    time.sleep(conf["landingWaitSec"])
    # "Click anywhere" to get past the landing page into the game.
    page.mouse.click(conf["viewportWidth"] // 2, conf["viewportHeight"] // 2)
    # Godot has to download the .pck and boot; there is no DOM signal for
    # "main menu is drawn", so wait for the canvas and then a fixed delay.
    try:
        page.wait_for_selector("canvas", timeout=30000)
    except Exception:
        print("  !! no <canvas> appeared — screenshotting whatever is there")
    time.sleep(conf["gameLoadWaitSec"])
    out_dir = HERE / conf["outputDir"]
    shot = out_dir / f"{game_id}_full.png"
    page.screenshot(path=str(shot))
    img = Image.open(shot).convert("RGB")
    if not test:
        shot.unlink()
    else:
        print(f"  full screenshot: {shot}")
    return img


def crop_poster(full: Image.Image, conf: dict) -> Image.Image:
    x, y = conf["wantedPosterPosX"], conf["wantedPosterPosY"]
    return full.crop((x, y, x + conf["wantedPosterWidth"], y + conf["wantedPosterHeight"]))


def erase_reward(poster: Image.Image, box: list) -> None:
    """Paint out the in-game "+10% KO" line. Only the dark ink pixels are
    replaced, with a median-blurred copy of the paper around them, so the
    bill's own stains and grain survive instead of getting a flat patch."""
    region = poster.crop(tuple(box))
    paper = region.filter(ImageFilter.MedianFilter(15))
    ink = region.convert("L").point(lambda v: 255 if v < 140 else 0)
    ink = ink.filter(ImageFilter.MaxFilter(3))  # catch the anti-aliased rims
    region.paste(paper, (0, 0), ink)
    poster.paste(region, (box[0], box[1]))


def burn_name(poster: Image.Image, name: str, box: list, tilt_deg: float) -> Image.Image:
    """Print the name, tilted, into the blank band under the portrait."""
    x0, y0, x1, y1 = box
    bw, bh = x1 - x0, y1 - y0
    # Fit the size to the box AFTER rotation, so the tilted word never spills.
    size = bh
    while size > 8:
        font = ImageFont.truetype(str(FONT_PATH), size)
        l, t, r, b = font.getbbox(name)
        layer = Image.new("RGBA", (r - l + 8, b - t + 8), (0, 0, 0, 0))
        ImageDraw.Draw(layer).text((4 - l, 4 - t), name, font=font, fill=INK + (235,))
        layer = layer.rotate(tilt_deg, resample=Image.BICUBIC, expand=True)
        if layer.width <= bw and layer.height <= bh:
            break
        size -= 1
    out = poster.convert("RGBA")
    out.alpha_composite(layer, (x0 + (bw - layer.width) // 2, y0 + (bh - layer.height) // 2))
    return out.convert("RGB")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--test", action="store_true",
                    help="open a real visible browser and keep the full screenshots")
    ap.add_argument("--conf", type=Path, default=DEFAULT_CONF)
    ap.add_argument("--only", help="run a single gameID from the conf")
    args = ap.parse_args()

    conf = load_conf(args.conf)
    games = conf["games"]
    if args.only:
        games = [g for g in games if g["gameID"] == args.only]
        if not games:
            print(f"no gameID '{args.only}' in {args.conf}", file=sys.stderr)
            return 1
    out_dir = HERE / conf["outputDir"]
    out_dir.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=not args.test,
            slow_mo=250 if args.test else 0,
            # WebGL for Godot in headless Chromium.
            args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                  "--ignore-gpu-blocklist"],
        )
        ctx = browser.new_context(
            viewport={"width": conf["viewportWidth"], "height": conf["viewportHeight"]},
            device_scale_factor=1,
        )
        page = ctx.new_page()
        for g in games:
            gid, name = g["gameID"], g["gameName"]
            print(f"[{gid}] {name}")
            full = screenshot_game(page, gid, conf, args.test)
            poster = crop_poster(full, conf)
            erase_reward(poster, conf["rewardEraseBox"])
            poster = burn_name(poster, name, conf["nameBox"], conf["nameTiltDeg"])
            dest = out_dir / f"{gid}_wanted.png"
            poster.save(dest)
            print(f"  saved {dest}")
        if args.test:
            input("Done — press Enter to close the browser...")
        browser.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
