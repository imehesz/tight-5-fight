"use strict";
// Regenerates server/rosters/<gameId>.json from each game's characters.json
// and venues.json. The server is deployed without the game's asset tree, so
// it can't read the rosters directly — these extracts are committed
// alongside it.
//
// Run this whenever you add or rename a comedian or a venue:
//   cd server && npm run sync-rosters
// Skipping it isn't fatal: an unlisted name is simply rejected by /play (and
// a game with no roster file at all falls back to shape-only validation).
//
// This is also the roster LINTER — the last place a bad roster can be caught
// before it reaches a deploy. Every game is checked before ANY file is
// written, so a failure leaves rosters/ exactly as it was rather than
// half-updated. See games/README.md for the CharacterId/VenueId contract.

const fs = require("node:fs");
const path = require("node:path");
const config = require("./config");

const gamesDir = path.join(__dirname, "..", "games");
const outDir = path.join(__dirname, "rosters");

// The seeding convention: lowercase, digits, hyphen-separated. Only a warning
// — an odd-looking id still works, as long as it is present and unique.
const SLUG_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

// Optional, characters.json only: the slug(s) a comedian's SHARE link may use,
// newest first. It lets a rename move the visible link without moving the
// permanent CharacterId, and keeps every previously shared slug resolving.
// Not part of the extract that ships to the server — share links never reach
// the backend — but linted here because this is where roster mistakes are
// caught before they go out.
const LINK_KEY = "playerLink";

const errors = [];
const warnings = [];

// Pull the names out of one roster file, validating as we go. Returns the
// sorted name list that ships to the server (ids are checked here but are
// NOT yet part of the output — /play still validates against names).
function extract(gameId, file, listKey, nameKey, idKey) {
  const label = `${gameId}/${path.basename(file)}`;
  let entries;
  try {
    entries = JSON.parse(fs.readFileSync(file, "utf8"))[listKey];
  } catch (e) {
    errors.push(`${label}: unreadable — ${e.message}`);
    return [];
  }
  if (!Array.isArray(entries)) {
    errors.push(`${label}: no "${listKey}" array`);
    return [];
  }

  const names = [];
  const idAt = new Map(); // id -> first entry that used it
  const nameAt = new Map();
  const linkAt = new Map(); // share-link slug -> the entry that claimed it

  entries.forEach((entry, i) => {
    const name = entry[nameKey];
    const id = entry[idKey];
    // Identify the entry by whatever it does have — a nameless entry still
    // needs to be findable in the file.
    const who = `${label} [${i}]${typeof name === "string" && name ? ` "${name}"` : ""}`;

    if (typeof name !== "string" || name.trim() === "") {
      errors.push(`${who}: missing ${nameKey}`);
    } else {
      if (name !== name.trim()) {
        errors.push(`${who}: ${nameKey} has leading/trailing whitespace`);
      }
      // Names are still the live leaderboard key, so a duplicate name today
      // silently merges two comedians' rows.
      if (nameAt.has(name)) {
        errors.push(`${who}: duplicate ${nameKey}, already used by [${nameAt.get(name)}]`);
      } else {
        nameAt.set(name, i);
        names.push(name);
      }
    }

    if (typeof id !== "string" || id.trim() === "") {
      errors.push(`${who}: missing ${idKey}`);
      return;
    }
    if (idAt.has(id)) {
      errors.push(`${who}: duplicate ${idKey} "${id}", already used by [${idAt.get(id)}]`);
      return;
    }
    idAt.set(id, i);
    if (!SLUG_RE.test(id)) {
      warnings.push(`${who}: ${idKey} "${id}" is not lowercase-hyphenated`);
    }

    // playerLink is optional — absent for anyone who has never been renamed.
    // A bare string is allowed, matching what game_state.player_links() reads.
    if (LINK_KEY in entry) {
      const list = typeof entry[LINK_KEY] === "string" ? [entry[LINK_KEY]] : entry[LINK_KEY];
      if (!Array.isArray(list) || list.length === 0) {
        errors.push(`${who}: ${LINK_KEY} must be a slug, or a non-empty list of slugs newest-first`);
        return;
      }
      for (const slug of list) {
        if (typeof slug !== "string" || slug.trim() === "") {
          errors.push(`${who}: ${LINK_KEY} has an empty entry`);
          continue;
        }
        // Two comedians claiming one slug means one of them silently never
        // gets their link back.
        if (linkAt.has(slug) && linkAt.get(slug) !== i) {
          errors.push(`${who}: ${LINK_KEY} "${slug}" already claimed by [${linkAt.get(slug)}]`);
          continue;
        }
        linkAt.set(slug, i);
        if (!SLUG_RE.test(slug)) {
          warnings.push(`${who}: ${LINK_KEY} "${slug}" is not lowercase-hyphenated`);
        }
      }
    }
  });

  // Cross-namespace check, once every id in the file is known: the deeplink
  // resolver matches CharacterId across the whole roster BEFORE it looks at
  // any alias, so a slug that collides with somebody else's id would never
  // win and its owner's link would quietly open the wrong comedian.
  for (const [slug, i] of linkAt) {
    if (idAt.has(slug) && idAt.get(slug) !== i) {
      errors.push(
        `${label} [${i}]: ${LINK_KEY} "${slug}" collides with the ${idKey} of [${idAt.get(slug)}]`
      );
    }
  }

  return names.sort();
}

// ---- pass 1: read + validate every game, writing nothing yet
const pending = [];
for (const gameId of config.games) {
  const gameDir = path.join(gamesDir, gameId);
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(path.join(gameDir, "game.json"), "utf8"));
  } catch (e) {
    errors.push(`${gameId}/game.json: unreadable — ${e.message}`);
    continue;
  }
  pending.push({
    gameId,
    characters: extract(
      gameId,
      path.join(gameDir, manifest.characters || "characters.json"),
      "characters", "CharacterName", "CharacterId"
    ),
    venues: extract(
      gameId,
      path.join(gameDir, manifest.venues || "venues.json"),
      "venues", "VenueName", "VenueId"
    ),
  });
}

for (const w of warnings) console.warn(`warning: ${w}`);

if (errors.length) {
  console.error(`\n${errors.length} roster problem(s) — nothing was written:\n`);
  for (const e of errors) console.error(`  ${e}`);
  console.error("\nFix games/<id>/characters.json or venues.json and re-run.");
  process.exit(1);
}

// ---- pass 2: everything checks out, write the extracts
fs.mkdirSync(outDir, { recursive: true });
for (const { gameId, characters, venues } of pending) {
  const out = path.join(outDir, `${gameId}.json`);
  fs.writeFileSync(out, JSON.stringify({ characters, venues }, null, 2) + "\n");
  console.log(`${gameId}: ${characters.length} characters, ${venues.length} venues -> ${path.relative(process.cwd(), out)}`);
}
