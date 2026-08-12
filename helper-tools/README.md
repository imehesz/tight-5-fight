# helper-tools/

Helpers for generating new games. Not bundled into the game build. Run from the
repo root with system `python3`.

(Note: the older `tools/` folder is gitignored — put anything meant to be
committed here in `helper-tools/` instead.)

## normalize_weapon.py

Turns a generated weapon picture into a game-ready melee weapon sprite for
`shared/assets/weapons/`. Every weapon shares the original mic stand's canvas —
**302x900, art inside y 22..872, striking end up, centred** — because the swing
and carry code sizes them all from the canvas rather than from the art.

```bash
python3 helper-tools/normalize_weapon.py raw.png shared/assets/weapons/weapon_sword.png
python3 helper-tools/normalize_weapon.py raw.png shared/assets/weapons/weapon_acoustic.png --rotate180
```

It flood-fills the background in from the four corners (not a "white is
transparent" threshold — these sprites have white highlights and pale steel of
their own), then scales the cut-out to fill the canvas height. `--rotate180` is
for anything swung by the end that a normal picture puts at the *bottom*: the
guitars are held by the neck, so their body has to end up at the top. Generators
draw those subjects far better the right way up, so the turn happens here
instead of in the prompt. Needs Pillow.

Then add a row to `WEAPONS` in `scripts/weapons.gd` — see the "Melee weapons"
section of the top-level `README.md` for what `grip` and `grip_up` mean.

### Prompt recipe

The shipped set was made with the Higgsfield CLI on `nano_banana_flash`
("Nano Banana 2"), about 1.5 credits each. Note the params take **underscores** —
`--aspect-ratio` is rejected.

```bash
higgsfield generate create nano_banana_flash --aspect_ratio 9:16 --resolution 1k \
  --prompt "A single <object>, isolated on a pure flat white background. Vertical
  orientation: <striking end> pointing straight up, <grip> at the bottom.
  Straight-on side view, the entire object visible end to end, centered, filling
  the full height of the frame. Clean crisp edges, soft even studio lighting,
  subtle realistic shading, slightly stylized high-detail video game item icon
  art. No shadow, no glow, no halo, no background elements, no text, no
  watermark, no hands, no other objects." --wait --json
```

Keep the whole tail — dropping the "no shadow / no halo" part produces a soft
glow around the object that the corner flood fill can't key out, and the cut-out
comes back with a white blob attached. Regenerate rather than loosening the
fill's tolerance. Raw job dumps land in the gitignored `tools/higgsfield_jobs/`
alongside every other generated asset's; this recipe is the part worth keeping.

## normalize_icon.py

Turns a generated logo picture into a game-ready square UI badge for
`shared/assets/ui/` — the social buttons on the main menu. Same idea as
`normalize_weapon.py`: flood-fill the background in from the four corners,
square the cut-out up, then box-sample it down to a small pixel grid (64x64
by default) and re-threshold the alpha so the outline stays crisp.

```bash
python3 helper-tools/normalize_icon.py raw.png shared/assets/ui/social_facebook.png
```

Adding a social button is then one entry in `SOCIALS` in `scenes/main_menu.gd`
(`icon`, `url`, `tip`) — `MenuBase.add_link_row()` builds the row and skips any
badge whose art hasn't been imported yet, so a half-added icon can't leave an
empty box on the menu.

### Prompt recipe

Same model as the weapons (`nano_banana_flash`, ~1.5 credits), 1:1:

```bash
higgsfield generate create nano_banana_flash --aspect_ratio 1:1 --resolution 1k \
  --prompt "A single retro 1980s arcade video-game icon: <logo description>.
  Rendered as chunky blocky 16-bit pixel art sprite, <colours>, thick dark pixel
  outline, subtle neon arcade sheen, visible large square pixels, limited retro
  palette. Perfectly square, centered, filling the frame, isolated on a pure flat
  white background. No shadow, no glow, no halo, no gradient background, no
  background elements, no text, no watermark, no other objects." --wait --json
```

Describe the logo by its *shapes* as well as its name ("a rounded-square camera
outline with a circle in the middle and a dot in the top-right corner") — naming
the brand alone gets a mangled glyph about half the time. The "no glow, no halo"
tail matters for the same reason it does on weapons: a soft glow keys out as a
white blob stuck to the badge.

## classify_heads.py

Populates a game's `characters.json` from the head PNGs in its
`assets/heads/` folder. Each filename is treated as a comedian's name; the tool
looks the person up on Wikipedia/Wikidata (free, no API key) and fills in:

- `BodyType`  — `M` / `F` (Wikidata sex-or-gender)
- `SkinColor` — light `#e9c098` / dark `#a0683c` (Wikipedia race/ethnicity categories)

Existing entries are kept (including any hand-tuned `HeadScale` / `HeadOffsetY`);
`hero1` / `hero2` template placeholders are skipped.

```bash
python3 helper-tools/classify_heads.py --game celebs --dry-run   # preview, writes nothing
python3 helper-tools/classify_heads.py --game celebs             # write characters.json
python3 helper-tools/classify_heads.py --game celebs --force     # re-resolve existing too
```

Requires only `requests`. Resolutions are cached in `helper-tools/.cache/` so
re-runs are instant and offline.

### Filename tips (fewer overrides)

Concatenated filenames (`davechappelle.png`) work, but the tool has to *guess*
the word boundaries. You get the most reliable results with two habits:

- **Separate the words** with `-`, `_`, or a space (`dave-chappelle.png`) — the
  tool then searches the exact words instead of brute-forcing splits.
- **Spell the name correctly** — `taylor-tomlinson`, not `taylortomlison`.

With both, correctly-spelled comedians who have a Wikipedia page resolve
automatically; overrides are only needed for people with no Wikipedia page.

### Overrides

Concatenated filenames mostly resolve automatically (`davechappelle` → Dave
Chappelle), but misspellings and obscure names can't. The tool prints those as
`UNRESOLVED`; fix them in `games/<game>/head_overrides.json` (auto-loaded):

```json
{
  "jerreysignfeld": {"query": "Jerry Seinfeld"},
  "rychardpryor":   {"query": "Richard Pryor"},
  "kylekanine":     {"name": "Kyle Kanine", "gender": "M", "skin": "light"}
}
```

- `query` — force the Wikipedia search string, but still auto-detect gender/skin.
- `name` / `gender` / `skin` — hard-code a field, skipping lookup for it.
