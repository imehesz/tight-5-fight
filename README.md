# Open Mic Night!

2D pixel-art side-scrolling beat-'em-up for mobile landscape, built in **Godot 4.4+**.
Walk the street, beat up hecklers, storm comedy venues, and survive the club
owner's bottle barrage every 5th venue. See `requirements.md` for the full design.

## Running it

1. Open the project folder in Godot 4.4 or newer (`project.godot`).
2. Press Play. Main scene is `scenes/main_menu.tscn`.
3. The `GameState` singleton is registered under Project Settings > Globals.

**Desktop test controls:** A/D or arrows to move, W/Up to enter doors, S/Down to
duck, J or Z to punch, K or X to kick. On-screen touch controls are always
visible and drive the same input actions (mouse clicks work on them too, via
`emulate_touch_from_mouse`).

## Gameplay summary

- **Street:** infinite scroll. Passive hecklers wander and yell insults (fight
  back if provoked); aggressive ones attack. Defeating anyone awards score.
- **Venues:** press up at a door. Venue N spawns N rival comedians (max 3 at
  once), pulled from `characters.json` excluding your pick. Clearing awards a bonus.
- **Boss (every 5th venue):** Big Lou can't be damaged — duck the head-high
  bottles and sidestep the lobbed ones until the SURVIVE timer runs out.
- 3 lives, health bar, local top-10 scoreboard (`user://highscores.json`).

## Adding content (no code needed)

- **New comedian:** drop a head PNG into `assets/heads/` (any square size —
  200x200 photos work; they're auto-scaled to the standard bobblehead size)
  and add an entry to `data/characters.json`. It appears in character select
  and the enemy pool. Keys:
  - `CharacterName`, `HeadSpritePath`, `BodyType` ("M" or "F") — required
  - `HeadOffsetY` — optional, body pixels; positive moves the head DOWN.
    Use for long hair/tall hairdos where the chin sits well above the image
    bottom (typical values 2–6; negative raises the head).
  - `HeadOffsetX` — optional; positive moves the head toward the facing
    direction (auto-mirrors when the character turns).
  - `HeadScale` — optional zoom multiplier (default 1.0). Big hair filling
    the crop makes the face render smaller than everyone else's — bump to
    1.2–1.5 to compensate (often paired with a `HeadOffsetY` tweak).
  Tip: faces should look to the right in the source image; a chin near the
  bottom edge sockets best onto the neck.
- **New venue:** add an entry to `data/venues.json` (`VenueName`,
  `ExteriorSpritePath` 160x120 with the door at bottom center,
  `InteriorSpritePath` 640x360).

## Placeholder art

All sprites in `assets/gen/` are generated placeholders. Regenerate with:

```sh
python3 tools/gen_assets.py   # needs Pillow
```

To replace with real art, keep the same paths/sizes (or point the JSONs at new
paths). Body sprite sheets are 32x48 frames, 4 columns, rows = idle(2), walk(4),
punch(3), kick(3), duck(1), hit(1), defeated(1) — layout is mirrored in
`scripts/character_factory.gd`, which also holds the per-animation head socket
offsets.

## Audio

`Music` and `SFX` buses are created at startup and wired to the Settings
sliders. There are no sound assets yet — when adding them, set each
AudioStreamPlayer's bus to `Music` or `SFX` and the volume controls will apply.
