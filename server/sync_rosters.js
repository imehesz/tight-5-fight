"use strict";
// Regenerates server/rosters/<gameId>.json from each game's characters.json.
// The server is deployed without the game's asset tree, so it can't read the
// rosters directly — these extracts are committed alongside it.
//
// Run this whenever you add or rename a comedian:
//   cd server && npm run sync-rosters
// Skipping it isn't fatal: an unlisted name is simply rejected by /play (and
// a game with no roster file at all falls back to shape-only validation).

const fs = require("node:fs");
const path = require("node:path");
const config = require("./config");

const gamesDir = path.join(__dirname, "..", "games");
const outDir = path.join(__dirname, "rosters");
fs.mkdirSync(outDir, { recursive: true });

for (const gameId of config.games) {
  const manifest = JSON.parse(fs.readFileSync(path.join(gamesDir, gameId, "game.json"), "utf8"));
  const charsFile = path.join(gamesDir, gameId, manifest.characters || "characters.json");
  const names = JSON.parse(fs.readFileSync(charsFile, "utf8"))
    .characters.map((c) => c.CharacterName)
    .filter(Boolean)
    .sort();

  const out = path.join(outDir, `${gameId}.json`);
  fs.writeFileSync(out, JSON.stringify(names, null, 2) + "\n");
  console.log(`${gameId}: ${names.length} characters -> ${path.relative(process.cwd(), out)}`);
}
