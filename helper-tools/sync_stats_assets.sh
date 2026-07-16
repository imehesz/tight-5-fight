#!/usr/bin/env bash
# Sync game assets into the public stats pages (website-for-all/stats/).
#
# Run this whenever a comedian or venue is added, renamed, or re-skinned:
#     ./helper-tools/sync_stats_assets.sh
# then deploy the website as usual (./deployScriptPRODWEB.sh).
#
# What it does, per game:
#   stats/<folder>/characters/  <- games/<id>/assets/heads/*.png + characters.json
#   stats/<folder>/venues/      <- games/<id>/assets/venues/*.png + venues.json
#   stats/assets/               <- shared body sheets (palette-swapped by stats.js)
#   stats/<folder>/index.html   <- created from stats/_template.html ONLY if
#                                  missing (hand edits are never overwritten)
#
# Target .png files are wiped before copying so renamed/removed art doesn't
# linger. Only *.png is touched — Godot's .import sidecars never match.
#
# NEW GAME: add a "folder=gameId" pair to GAMES below (folder is the public
# URL segment, gameId is what the leaderboard DB uses — JAX's is "tight5").

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATS="$ROOT/website-for-all/stats"

GAMES=(
  "jax=tight5"
  "daytona=daytona"
  "celebs=celebs"
  "killers=killers"
)

copy_pngs() { # src_dir dst_dir
  rm -f "$2"/*.png
  cp "$1"/*.png "$2"/
}

mkdir -p "$STATS/assets"
cp "$ROOT/shared/assets/bodies/body_male.png" \
   "$ROOT/shared/assets/bodies/body_female.png" \
   "$ROOT/shared/assets/bodies/wheelie_1.png" \
   "$ROOT/shared/assets/bodies/wheelie_2.png" "$STATS/assets/"

for pair in "${GAMES[@]}"; do
  folder="${pair%%=*}"
  gid="${pair##*=}"
  src="$ROOT/games/$gid"
  dst="$STATS/$folder"

  if [[ ! -d "$src" ]]; then
    echo "SKIP $folder: no game folder at games/$gid" >&2
    continue
  fi

  mkdir -p "$dst/characters" "$dst/venues"
  copy_pngs "$src/assets/heads"  "$dst/characters"
  copy_pngs "$src/assets/venues" "$dst/venues"
  cp "$src/characters.json" "$dst/characters/characters.json"
  cp "$src/venues.json"     "$dst/venues/venues.json"

  if [[ ! -f "$dst/index.html" ]]; then
    label="$(echo "$folder" | tr '[:lower:]' '[:upper:]')"
    sed -e "s/__GAME_ID__/$gid/g" -e "s/__LABEL__/$label/g" \
        "$STATS/_template.html" > "$dst/index.html"
    echo "created $folder/index.html (label $label — edit if it should differ)"
  fi

  heads=$(ls "$dst/characters"/*.png 2>/dev/null | wc -l)
  venues=$(ls "$dst/venues"/*.png 2>/dev/null | wc -l)
  echo "synced $folder (game id: $gid): $heads head pngs, $venues venue pngs"
done

echo "done — deploy website-for-all/ to publish"
