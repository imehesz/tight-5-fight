"use strict";
// Regenerates server/rosters/<gameId>.json from each game's characters.json,
// venues.json and decorators.json. The server is deployed without the game's asset tree, so
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

// Chest decorations (games/<id>/decorators.json, optional). Only the PRICES
// ship to the server — it never draws one, it only has to know what to charge,
// and a price the client could name is a price the client could set to 0.
// Same slug rules as a CharacterId, and the same linting: a bad row here is
// caught before a deploy, not after somebody buys it.
const DECOR_FILE = "decorators.json";

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

// Pull { id: price } out of one game's decorators.json. A game with no such
// file simply has no decorations — that is the common case, so a missing file
// is silent, while an unreadable one is an error like any other roster.
function extractDecor(gameId, file) {
  if (!fs.existsSync(file)) return null;
  const label = `${gameId}/${DECOR_FILE}`;
  let entries;
  try {
    entries = JSON.parse(fs.readFileSync(file, "utf8")).decorators;
  } catch (e) {
    errors.push(`${label}: unreadable — ${e.message}`);
    return null;
  }
  if (!Array.isArray(entries)) {
    errors.push(`${label}: no "decorators" array`);
    return null;
  }

  const out = {};
  entries.forEach((entry, i) => {
    const who = `${label} [${i}]`;
    const id = entry.id;
    if (typeof id !== "string" || id.trim() === "") {
      errors.push(`${who}: missing id`);
      return;
    }
    // A duplicate id means one of the two can never be bought separately:
    // purchases key on the id alone.
    if (id in out) {
      errors.push(`${who}: duplicate id "${id}"`);
      return;
    }
    if (!SLUG_RE.test(id)) {
      warnings.push(`${who}: id "${id}" is not lowercase-hyphenated`);
    }
    // 32 chars is the decor_id column in server/db.js.
    if (id.length > 32) {
      errors.push(`${who}: id "${id}" is longer than 32 characters`);
      return;
    }
    const price = entry.price;
    if (!Number.isInteger(price) || price < 0) {
      errors.push(`${who}: price must be a whole number of joke points (0 = free)`);
      return;
    }
    // Free rows are listed too, with price 0: the server then knows the id is
    // real and simply refuses to sell it, rather than 404-ing on something the
    // client legitimately shipped.
    out[id] = price;
    const rel = entry.path;
    if (typeof rel !== "string" || rel.trim() === "") {
      errors.push(`${who} "${id}": missing path`);
      return;
    }
    // The art never reaches the server, but a decoration whose PNG is missing
    // is an empty card in the shelf — and this is the one place that can see
    // both the JSON and the asset tree.
    if (!fs.existsSync(path.join(path.dirname(file), rel))) {
      errors.push(`${who} "${id}": path "${rel}" does not exist`);
    }
  });
  return out;
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
    decorators: extractDecor(
      gameId,
      path.join(gameDir, manifest.decorators || DECOR_FILE)
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
for (const { gameId, characters, venues, decorators } of pending) {
  const out = path.join(outDir, `${gameId}.json`);
  // `decorators` is left out entirely for a game that ships none, so the
  // extract of an edition without them is byte-for-byte what it always was.
  const payload = decorators ? { characters, venues, decorators } : { characters, venues };
  fs.writeFileSync(out, JSON.stringify(payload, null, 2) + "\n");
  const decorNote = decorators ? `, ${Object.keys(decorators).length} decorations` : "";
  console.log(`${gameId}: ${characters.length} characters, ${venues.length} venues${decorNote} -> ${path.relative(process.cwd(), out)}`);
}
