# Games — how the multi-game engine is organized

This project is **one Godot engine** that ships **many standalone games**. Everything
game-specific lives in `games/<id>/`; the engine code (`scenes/`, `scripts/`,
`autoload/`) and the assets every game reuses (`shared/`) are the same for all games.

```
games/
├── tight5/            # a shipping game
│   ├── game.json       # the manifest — names + points at this game's assets
│   ├── characters.json # roster (sprite paths are relative to this folder)
│   ├── venues.json     # venues (sprite paths relative to this folder)
│   ├── deploy.json     # this game's server destination
│   └── assets/         # heads, venues, backgrounds, misc, audio
├── _template/         # copy this to start a new game (a minimal game that runs)
data/active_game.json  # names the game this build/run uses  ({ "active": "tight5" })
shared/assets/         # fonts, bodies, ui buttons, sfx, window icon (all games)
shared/assets/weapons/ # the shared weapon rack: weapons.json + its art (all games)
```

**Golden rule:** every asset path inside a game's JSON is **relative to that game's
own folder** (the engine prefixes `res://games/<id>/`). Engine code never hardcodes a
`res://games/...` or game-specific `res://assets/...` path — it asks `GameState`.

---

## Add a new game (no code changes, no project copy, no Git)

1. **Copy the template:** `cp -r games/_template games/<newid>`
2. **Edit `games/<newid>/game.json`:** set `id` (must equal the folder name),
   `title`, and `menuTitle`. Point `backgrounds` at your art. Add optional
   `boss.headSprite`, `projectileSprite`, `audio.musicMain/musicVenue`, or
   `overrides.bodyMale/bodyFemale` only if you want to differ from the shared defaults.
3. **Drop in art** under `games/<newid>/assets/…` (heads, venues, backgrounds,
   optional boss/prop/audio). Keep paths matching what your JSON references.
4. **Fill in `characters.json` and `venues.json`** — sprite paths relative to the
   game folder (e.g. `assets/heads/foo.png`). Give every entry a `CharacterId` /
   `VenueId` (see below) — those, not the names, are what the leaderboard will key on.
5. **Set the destination** in `games/<newid>/deploy.json`.
6. **Test locally:** set `data/active_game.json` to `{ "active": "<newid>" }`, open the
   project in Godot (this imports your new art) and press Play.
7. **Ship it:** `./deployScriptPROD.sh <newid> go`

### Manifest field reference (`game.json`)

| Field | Required | Falls back to |
|-------|----------|---------------|
| `id` (must equal folder name) | ✅ | — |
| `title`, `menuTitle` | ✅ | — |
| `publicFolder` (URL segment under `/tight5fight/`) | only if ≠ `id` | `id` |
| `characters`, `venues` | ✅ | `characters.json` / `venues.json` |
| `backgrounds.splash` / `.menu` / `.streetTile` | ✅ | `assets/backgrounds/{splash,menu_bg,street_tile}.png` |
| `boss.headSprite` | optional | placeholder head (a colored square) |
| `projectileSprite` | optional | invisible projectile |
| `audio.musicMain` / `.musicVenue` | optional | no music (paths are **extensionless**) |
| `overrides.bodyMale` / `.bodyFemale` | optional | `shared/assets/bodies/body_{male,female}.png` |
| `weapons` | optional | `weapons.json` in the game folder if present, else the shared rack (`shared/assets/weapons/weapons.json`) |
| `planeBanners` (array of sentences) | optional | no banner-plane flybys on the street |

### `CharacterId` / `VenueId` — the permanent handle

Every entry carries a machine-readable id alongside its display name:

```json
{ "CharacterId": "marcus-crespo", "CharacterName": "Marcus Crespo", ... }
```

**The id never changes. The name is free to.** That's the entire point: when a
comedian asks you to fix the spelling of their name or start going by something
else, you edit `CharacterName` and every leaderboard row they own follows along,
because the database is keyed on the id.

Rules:

- **Lowercase, digits, hyphens.** Seeded from the name (`Marcus Crespo` →
  `marcus-crespo`), but that's a starting convention, not a rule the code enforces.
- **Unique within one game's file.** Ids only have to be unique inside
  `games/<id>/characters.json` — every leaderboard row is already scoped by game,
  so JAX and DAYTONA can both have a `marcus-crespo`. Characters and venues are
  separate namespaces too; they can't collide with each other.
- **Same person across two cities → same id.** Not required, but do it anyway.
  It costs nothing now and it's the only thing that makes a combined
  career-across-all-editions view possible later.
- **Never recycle an id** for a different person. The old rows would silently
  merge into the new one.

Note the id is currently **inert** — the client still reports names to the
leaderboard and the server still validates against names. Adding the field
breaks nothing; switching the pipeline over to it is a separate step.

### Sharing a comedian (`?fighter=`)

The roster's SHARE button (square, next to FIGHT!) hands the OS a link to the
highlighted comedian, built from their `CharacterId`:

```
https://games.imstandup.com/tight5fight/jax/?fighter=marcus-crespo
```

Opening that link shows the splash, and the **first tap goes straight into the
fight** as that comedian — no menu, no roster. (The tap stays because it is
also what unlocks audio in the browser.)

- **The URL is read from the page itself on web**, never composed, so a LAN
  playtest shares a LAN link. `publicFolder` above only feeds the desktop and
  editor fallback — but keep it correct anyway. Note `/tight5/` would 404;
  JAX ships at `/jax/`.
- **A dead link still opens a game.** An id matching no comedian, or matching a
  benched (`isDisabled`) one, silently rolls a random comedian instead.
- **SHARE is disabled on the "?" card** — a random pick has no comedian to share.
- **A shared comedian is borrowed, not adopted.** The run does not overwrite
  the recipient's own saved favorite; opening the roster hands it straight back.

### Benching a comedian or a venue (`characters.json` / `venues.json`)

Add `"isDisabled": true` to a character entry and they vanish from the roster
grid, the "?" random roll, heckler spawns and plane pilots — but stay in the
file, so every leaderboard row they already own keeps its name **and** its head
sprite. Leave the field out (or set it `false`) and they're playable as usual.
That's how a seasonal character works: ship Santa with `isDisabled: true` all
year, flip it off in December, redeploy. No database edit either way. A player
whose saved favorite gets disabled simply opens on the first playable comedian.

The same flag works on a `venues.json` entry: a disabled venue stops spawning
on the street, but stays in the file so the public stats pages keep finding its
name and exterior art, and every row it already owns on the VENUES boards
survives untouched. No database edit, no re-run of `sync-rosters` needed —
though running it anyway is harmless (disabled names stay whitelisted, which
only matters to in-flight runs on an older build).

### Weapons (`shared/assets/weapons/weapons.json`)

The melee weapon rack in SETTINGS is data too, but unlike characters and venues
it is **shared across every game** — one file, one art folder, all editions.
Weapons are purely cosmetic: everything swings with the mic stand's damage,
reach and cooldown, so the rack never touches leaderboard fairness.

Adding a weapon:

1. Normalize the art onto the mic stand's canvas (302x900, striking end up,
   centred): `helper-tools/normalize_weapon.py` (use `--rotate180` for art
   drawn handle-up, e.g. the guitars, which are swung by the neck).
2. Drop the PNG in `shared/assets/weapons/`.
3. Add a row to `weapons.json`:

```json
{ "WeaponId": "crowbar", "WeaponName": "CROWBAR", "GripY": 760, "GripUp": true, "SpritePath": "weapon_crowbar.png" }
```

- **`WeaponId`** — permanent handle, exactly like `CharacterId`: saved picks are
  keyed on it, so never recycle one. **Keep the mic stand as the first row** —
  row 0 is the default and the fallback for any pick that can't be honoured.
- **`GripY`** — texture-space y the hand closes on (sword: under the crossguard
  ~730; bat: down by the knob ~790).
- **`GripUp`** — `true` to wear it handle-up on the back (swords, shovels…);
  `false` for things really carried head-up (mic stand, chain).
- **`SpritePath`** — relative to the JSON's own folder; a leading `shared/`
  resolves from the project root, and full `res://` paths pass through.
- **`isDisabled: true`** benches a weapon (same flag as characters/venues);
  anyone carrying it falls back to the mic stand, and their save is untouched.

A row whose PNG hasn't been imported yet simply doesn't show on the rack —
safe to commit data ahead of art. A game can also ship its own
`games/<id>/weapons.json` (or name one via the `weapons` manifest key) to
replace the shared rack for that edition only.

---

## Parallax street background (optional, per game)

By default the street scrolls **one** `street_tile.png` with the sky, the stars
and the road all baked into it. That is still the default and nothing about it
has changed — an edition that never opts in renders exactly as it always has.

An edition can instead scroll **three** layers at different speeds by setting
one manifest flag:

```jsonc
"advancedParallax": true,
"parallax": {
  "stars":    { "sprite": "assets/backgrounds/parallax_stars.png",     "factor": 0.1 },
  "twinkleA": { "sprite": "assets/backgrounds/parallax_twinkle_a.png", "factor": 0.1, "twinkle": 2.7 },
  "twinkleB": { "sprite": "assets/backgrounds/parallax_twinkle_b.png", "factor": 0.1, "twinkle": 4.1 },
  "skyline":  { "sprite": "assets/backgrounds/parallax_skyline.png",   "factor": 0.5 },
  "street":   { "sprite": "assets/backgrounds/parallax_street.png",    "factor": 1.0 }
}
```

The whole `parallax` block is optional — those paths and factors are the
defaults, so `"advancedParallax": true` plus the three PNGs in the standard spot
is enough. Override just the field you're tuning.

- **`factor`** is the fraction of the player's walking speed the layer drifts
  at. `1.0` is the ground the player walks on; smaller reads as further away.
  The layer nearest the camera moves **fastest** — stars belong near `0.1`.
- **Layer width is never configured.** Each strip repeats at its own texture's
  width, so a wider skyline simply repeats less often: at 960px and factor 0.5
  it comes back every 1920 world px, about 14 seconds of walking.
- **`twinkle`** is the seconds for one full fade-down-and-back; omit it (or use
  `0`) for a steady layer. `twinkleMin` sets how far down it fades, default
  `0.15` — never `0`, because stars that vanish outright read as a glitch.
  **The two twinkle strips are optional**: an edition that ships only the three
  core PNGs gets a steady sky, not a fallback. They carry *only* the blinking
  stars — the sky and the steady stars are on the opaque layer underneath, which
  is what stops a fade from dimming the whole night sky. Give them **different
  periods**; a single strip fades all its stars in unison and reads as the sky
  pulsing rather than shimmering.
- **The three CORE layers must all resolve, or the game falls back to `streetTile`** and
  logs a warning. This is deliberate — the cut-out street layer is transparent
  above its rooftops, so a partial stack shows a black band rather than the old
  background. Missing art degrades to "plain", never to "broken".
- Author every layer **360 tall, top-aligned**. The sizes don't have to match,
  but sharing the height means the three PNGs drop straight on top of each other
  with no per-layer offset to keep in sync.
- The **stars layer must be opaque** (it's the backstop that paints the sky);
  the other two need transparent skies.

### Making the art

`helper-tools/make_parallax_layers.py` builds all three from the edition's
existing tile plus one wide skyline image:

```sh
python3 helper-tools/make_parallax_layers.py street  <game>
python3 helper-tools/make_parallax_layers.py stars   <game>
python3 helper-tools/make_parallax_layers.py skyline <game> path/to/generated.png
```

It reads the sky, star, building and window colours **out of that game's own
`street_tile.png`**, so a new city keeps its own palette automatically. Only the
skyline source's *roofline* is used — the silhouette is redrawn from scratch in
the game's colours, so the source's own palette, texture and background never
reach the game. Both ends of the skyline strip are flattened to a common roof
height so it wraps without a visible step.

The skyline source can be generated; this prompt produced the Panhandle one on
`z_image` (0.15 credits), and the flat-silhouette-on-plain-background shape is
what the converter wants:

> Flat 2D vector game art of a distant city skyline silhouette seen straight on
> from the side. Simple geometric rectangular skyscrapers and towers of varying
> heights, a few antenna spires and a water tower, all filled with ONE single
> solid flat dark purple color, absolutely no shading, no gradients, no texture,
> no windows, no perspective, sharp clean straight edges. The buildings sit
> along the bottom edge of the frame and occupy only the lower third. Everything
> else is empty solid bright magenta. Minimalist retro pixel art night scene, no
> text, no people, no ground, no clouds, no stars.

---

## Building / deploying

`./deployScriptPROD.sh <id>` builds **only that game's** assets (every other
`games/<other>/` folder is excluded from the export) and dry-runs the rsync.
Add `go` to actually deploy. The build script owns `active_game.json` and the
export's `exclude_filter` — don't hand-edit those.

Requires `godot` on `PATH` (or `GODOT=/path/to/godot`), plus `python3`, `rsync`, `ssh`.
