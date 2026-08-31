# Tight 5 FIGHT!

(repo folder keeps its original `open-mic-night` name)

2D pixel-art side-scrolling beat-'em-up for mobile landscape, built in **Godot 4.4+**.
Walk the street, beat up hecklers, storm comedy venues, and survive the club
owner's bottle barrage every 3rd venue. See `requirements.md` for the full design.

## Running it

1. Open the project folder in Godot 4.4 or newer (`project.godot`).
2. Press Play. Main scene is `scenes/splash.tscn` (tap through to the menu).
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
- **Boss (every 3rd venue):** Big Lou can't be damaged — duck the head-high
  bottles and sidestep the lobbed ones until the SURVIVE timer runs out.
- Lives are earned: start with 1, first boss grants a 2nd, second boss a 3rd. Health bar, local top-10 scoreboard stored on-device at
  `user://highscores.json` — each entry keeps score, highest venue level
  reached, character and date.

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
  - `SkinColor` — optional hex color (default `"#e9c098"`, the tone baked
    into the generated body sheets). The body's skin pixels are palette-
    swapped to this at load, so match it to the head photo's skin tone.
  Tip: faces should look to the right in the source image; a chin near the
  bottom edge sockets best onto the neck.
- **New venue:** add an entry to `data/venues.json` (`VenueName`,
  `ExteriorSpritePath` 160x120 with the door at bottom center,
  `InteriorSpritePath` 640x360).
- **New sponsor (paid billboard on the street + SPONSORS screen):** hosted,
  not baked into any build — see `website-for-all/sponsors/README.md`.
  Paste the 640x460 artwork into `website-for-all/sponsors/marquee/`, add an
  entry to `sponsors.json`, rsync the website. No game redeploy. **Never put
  "ad", "sponsor", "banner" or "promo" in the file path** — ad blockers kill
  those requests outright, costing the sponsor both their billboard and their
  impression count. The sponsors README opens with the full story.

## Melee weapons

The player's melee weapon (SETTINGS → WEAPONS) is cosmetic — every one of them
swings with the mic stand's damage, reach and cooldown, so nothing on the
global leaderboard turns on which one you picked. The pick is saved by id in
the per-game settings file and carried on the player's back in the run.

Adding one:

1. Generate the art on flat white — vertical, striking end up, grip at the
   bottom, filling the frame. The prompt recipe is in `helper-tools/README.md`.
2. `python3 helper-tools/normalize_weapon.py raw.png shared/assets/weapons/weapon_<id>.png`
   — cuts the background out and lands the art on the shared 302x900 canvas
   that the swing and carry code sizes everything from. Add `--rotate180` for
   anything swung by the end that is normally drawn at the bottom (the guitars
   are held by the neck, so their body has to end up at the top).
3. Add a row to `shared/assets/weapons/weapons.json` — data, not code, so no
   `.gd` file is touched. `WeaponId` (what saves store), `WeaponName` (what the
   picker shows) and `SpritePath` (relative to that JSON's own folder) are the
   obvious three; two more are worth thinking about:
   - `GripY` — the texture-space y where the player's hand closes, which is what
     keeps a sword held under its crossguard and a bat down by its knob. It also
     sets the on-screen size: the swing scales grip-to-tip to a fixed length, so
     a bigger `GripY` draws a smaller weapon. The shipped set runs 690-795.
   - `GripUp` — `true` for anything worn handle-up on the back so it could be
     drawn (swords, bat, chainsaw, shovel, cue). `false` for the mic stand, the
     chain and the keyboard, which have no business end to point away. Affects
     the carried sprite only, never the swing.

The picker lists only weapons whose art actually imported, and the rack
scrolls, so the grid never needs touching as the list grows.

## Street decor

The small stuff dressing the foreground strip below the fighters' feet: litter
lying on the pavement, critters that scurry through. Purely decorative — no
collision, no pickups, nothing that can change a run. Roster lives in
`shared/assets/decor/decor.json`, read by `scripts/street_decor.gd`; a game may
ship its own `games/<id>/decor.json` to replace it (a beach edition wanting
seagulls and soda cups needs no code, just the file).

Two pools, because they have two lifetimes:

* **`litter`** — static, scattered once per venue gap, then streamed in and out
  with the venues and saved with the street, so the trash is where you left it
  when you walk back out of a venue.
* **`critters`** — run in from off-screen, stop to look around, run back out and
  free themselves. Nothing about them is persisted.

Adding one:

1. Generate the art on flat white with a **bold dark outline** — the outline is
   what stops the background cut-out leaking into pale art. Prompt recipe is in
   `helper-tools/README.md`.
2. `python3 helper-tools/normalize_decor.py raw.png shared/assets/decor/decor_<id>.png`
   — cuts the background out, trims, and scales to a source height. It also
   prints the alpha profile you read `FootFrac` off.
3. Add a row to the `litter` or `critters` array in `decor.json`. `Scale` is the
   only size control (design px per source px) — nothing is baked into the art,
   so a prop that lands too big is a JSON edit, not a regeneration. Field
   reference is the header comment of `scripts/street_decor.gd`.

Critters need no sprite sheet: at ~10 design px tall there is nothing legible to
animate, so the scurry is a coded bob (`BobPx`/`BobHz`) and "looking around" is a
horizontal flip, the same trick `BillboardBird` uses. One clean side view facing
LEFT is the whole asset.

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

## Art & audio (AI-generated via Higgsfield)

`assets/art/` holds the splash, menu background and the Laughing Skull /
Comedy Zone / Bonkers venue art (z_image, pixelated down in post).
`assets/audio/` holds the looping chiptune theme (`song.ogg`, sonilo_music)
and the SFX set (mirelo_text_to_audio → WAV): punch, kick, hurt, defeat,
smash, clear, click, throw.

Music plays on the `Music` bus, effects through a pooled `SFX` bus — both
wired to the Settings sliders (persisted to `user://settings.json`). Trigger
effects from code with `GameState.play_sfx("punch")`. Swapping any file for
a new one with the same name is all it takes to replace a sound.

## Web audio & frame pacing (the choppy-audio fix, 2026-08-24)

Three project settings carry the fix. Godot's editor rewrites `project.godot`
through its ConfigFile serializer, which drops every comment — so the reasoning
lives here instead, and the `;` notes in that file will vanish the next time the
editor saves project settings.

- `application/run/max_fps=60` — the web build renders on `requestAnimationFrame`,
  so a 120Hz phone (Pixel 10 Pro, iPhone Pro) draws twice the frames of a 60Hz
  one for zero visual gain on a 640x360 pixel-art game. With
  `variant/thread_support=false` the audio mixer shares the main thread, so every
  wasted frame is stolen from the mixer. 60 halves the render load on both
  platforms. Raise to 0 (uncapped) to A/B it.
- `audio/driver/output_latency.web=120` — Godot sizes the web mix buffer from
  this. The ~15ms default means ANY frame longer than 15ms tears a hole in the
  sound: that is every frame under heavy action and every scene transition, on
  any phone. Confirmed on device 2026-08-24 with `?dpr=1&nosfx=1` (music alone,
  minimal canvas load) still crackling at nav → character select → game start,
  while resting audio was clean. 120ms holds ~8 frames of slack, so the main
  thread can fall behind and catch up inaudibly.
  **Tuning:** the cost is SFX firing up to ~100ms late. If that feels mushy, step
  down to 80. If crackle survives, step up to 200 before touching anything else.
  A single scene load that blocks longer than the buffer will still break
  through — that is a preload problem, not an audio one.
- `audio/general/default_playback_type.web=0` — Stream mode, which is what mixes
  on the main thread above.
