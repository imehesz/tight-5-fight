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
   game folder (e.g. `assets/heads/foo.png`).
5. **Set the destination** in `games/<newid>/deploy.json`.
6. **Test locally:** set `data/active_game.json` to `{ "active": "<newid>" }`, open the
   project in Godot (this imports your new art) and press Play.
7. **Ship it:** `./deployScriptPROD.sh <newid> go`

### Manifest field reference (`game.json`)

| Field | Required | Falls back to |
|-------|----------|---------------|
| `id` (must equal folder name) | ✅ | — |
| `title`, `menuTitle` | ✅ | — |
| `characters`, `venues` | ✅ | `characters.json` / `venues.json` |
| `backgrounds.splash` / `.menu` / `.streetTile` | ✅ | `assets/backgrounds/{splash,menu_bg,street_tile}.png` |
| `boss.headSprite` | optional | placeholder head (a colored square) |
| `projectileSprite` | optional | invisible projectile |
| `audio.musicMain` / `.musicVenue` | optional | no music (paths are **extensionless**) |
| `overrides.bodyMale` / `.bodyFemale` | optional | `shared/assets/bodies/body_{male,female}.png` |
| `planeBanners` (array of sentences) | optional | no banner-plane flybys on the street |

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

---

## Building / deploying

`./deployScriptPROD.sh <id>` builds **only that game's** assets (every other
`games/<other>/` folder is excluded from the export) and dry-runs the rsync.
Add `go` to actually deploy. The build script owns `active_game.json` and the
export's `exclude_filter` — don't hand-edit those.

Requires `godot` on `PATH` (or `GODOT=/path/to/godot`), plus `python3`, `rsync`, `ssh`.
