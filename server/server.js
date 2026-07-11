"use strict";
// Global leaderboard for the open-mic-night engine: a popularity board
// counting how many times each character has been played, per game.
//
// Threat model, stated plainly: nobody's name is on this board, so the only
// prize for cheating is pushing a favourite comedian up a popularity chart.
// The defences are sized for that, and none of them pretend to be more than
// they are:
//   - The UUID is minted HERE, not by the client, and a play must reference
//     one that exists. A `curl` with a made-up UUID is rejected outright.
//   - Minting is capped per IP, so the obvious bypass (mint a fresh UUID per
//     request) costs the one identifier a client can't rotate for free.
//   - Plays are capped per UUID (durably, in the DB) and per IP (in memory).
//   - Character names are checked against the game's roster, so the board
//     can never fill with strings the game never shipped.
// A determined person on a phone hotspot can still inflate a counter. That
// is an acceptable outcome for a counter.

const http = require("node:http");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const config = require("./config");
const db = require("./db");

const PORT = Number(process.env.PORT) || config.port;
const HOST = process.env.HOST || config.host;

// The game page (imstandup.com) and this server (games.mehesz.net) are
// always different origins, so every response needs CORS headers. Nothing
// sensitive is exposed: the endpoints only mint an anonymous id and count
// plays.
const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "content-type",
};

function json(res, status, body) {
  res.writeHead(status, { "content-type": "application/json", ...CORS });
  res.end(JSON.stringify(body));
}

// ---------------------------------------------------------------- rosters
// Which character and venue names each game is allowed to report. Generated
// from the game's characters.json / venues.json by `npm run sync-rosters`
// (see sync_rosters.js) and committed, because the server is deployed
// without the game's asset tree. A game with no roster file falls back to
// shape-only validation, so adding a comedian mid-season degrades to
// "slightly laxer", never to "broken".
//
// File format is { characters: [...], venues: [...] }; a bare array (the
// pre-venues format) still loads as characters-only, so a stale roster on
// the VPS costs the venue board its validation, not the server its boot.
const rosters = new Map(); // gameId -> { characters: Set|null, venues: Set|null }

function loadRosters() {
  const dir = path.join(__dirname, "rosters");
  for (const gameId of config.games) {
    const file = path.join(dir, `${gameId}.json`);
    try {
      const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
      const characters = Array.isArray(parsed) ? parsed : parsed.characters || [];
      const venues = Array.isArray(parsed) ? null : parsed.venues || null;
      rosters.set(gameId, {
        characters: new Set(characters),
        venues: venues ? new Set(venues) : null,
      });
      console.log(`roster ${gameId}: ${characters.length} characters, ${venues ? venues.length : "?"} venues`);
    } catch (e) {
      if (e.code !== "ENOENT") throw e;
      console.warn(`roster ${gameId}: MISSING (${file}) — names validated by shape only`);
    }
  }
}

// A conservative shape check for when no roster list exists, so nothing
// wild reaches the database.
function plausibleName(name) {
  if (typeof name !== "string" || name.length === 0 || name.length > 64) return false;
  return /^[\p{L}\p{N} .'’_-]+$/u.test(name);
}

// A name is acceptable if the roster knows it; with no roster, fall back to
// the shape check.
function validCharacter(gameId, name) {
  if (typeof name !== "string" || name.length === 0 || name.length > 64) return false;
  const roster = rosters.get(gameId);
  if (roster) return roster.characters.has(name);
  return plausibleName(name);
}

function validVenue(gameId, name) {
  const roster = rosters.get(gameId);
  if (roster && roster.venues) return roster.venues.has(name);
  return plausibleName(name);
}

// The per-run KO tally that feeds the "most beat up" board. A run can KO the
// same comedian many times, but 500 of one name in one run is beyond any
// human playthrough — the cap bounds what a single (cooldown-priced) request
// can add, same spirit as the play limits.
const MAX_KOS_PER_CHARACTER = 500;

// Validate the optional `kos` payload: {characterName: count}. Returns the
// clean map, or null when the shape is hostile (wrong types, absurd counts,
// too many keys) — the caller rejects those outright. Names the roster does
// not know are DROPPED rather than fatal, mirroring how a mid-season roster
// gap degrades plays: a stale roster should cost one comedian's tally, not
// the whole run's.
function cleanKos(gameId, kos) {
  if (kos === undefined || kos === null) return {};
  if (typeof kos !== "object" || Array.isArray(kos)) return null;
  const entries = Object.entries(kos);
  if (entries.length > 64) return null;
  const clean = {};
  for (const [name, count] of entries) {
    if (!Number.isInteger(count) || count < 1 || count > MAX_KOS_PER_CHARACTER) return null;
    if (validCharacter(gameId, name)) clean[name] = count;
  }
  return clean;
}

// The per-run venue-entry tally that feeds the VENUES board. The street
// cycles ~9 venues, so even a marathon run re-enters a name a handful of
// times — 100 is far beyond any human playthrough.
const MAX_ENTRIES_PER_VENUE = 100;

// Validate the optional `venues` payload: {venueName: count}. Same contract
// as cleanKos — hostile shape is null (fatal), unknown names are dropped.
function cleanVenues(gameId, venues) {
  if (venues === undefined || venues === null) return {};
  if (typeof venues !== "object" || Array.isArray(venues)) return null;
  const entries = Object.entries(venues);
  if (entries.length > 64) return null;
  const clean = {};
  for (const [name, count] of entries) {
    if (!Number.isInteger(count) || count < 1 || count > MAX_ENTRIES_PER_VENUE) return null;
    if (validVenue(gameId, name)) clean[name] = count;
  }
  return clean;
}

// ---------------------------------------------------------------- rate limits
// Sliding-window counters, keyed by IP. Memory-only and therefore reset by a
// restart — fine, because the durable per-UUID cooldown lives in the DB and
// these only bound the burst rate of a scripted client.
//
// Checking and charging are deliberately separate calls: only a request that
// actually lands is charged. The cap exists to bound how fast the board can
// be inflated, and a refused request inflates nothing — charging for it would
// let a player who double-taps burn an hour of their own budget.
const hits = new Map(); // `${bucket}:${ip}` -> number[] of epoch-ms
const WINDOW_MS = 3600_000;

function recent(bucket, ip) {
  const now = Date.now();
  const fresh = (hits.get(`${bucket}:${ip}`) || []).filter((t) => now - t < WINDOW_MS);
  hits.set(`${bucket}:${ip}`, fresh);
  return fresh;
}

function overLimit(bucket, ip, max) {
  return recent(bucket, ip).length >= max;
}

function chargeHit(bucket, ip) {
  recent(bucket, ip).push(Date.now());
}

// Drop empty windows every 10 minutes so the map can't grow without bound.
setInterval(() => {
  const now = Date.now();
  for (const [key, times] of hits) {
    const fresh = times.filter((t) => now - t < WINDOW_MS);
    if (fresh.length === 0) hits.delete(key);
    else hits.set(key, fresh);
  }
}, 600_000).unref();

// In production Apache is the only way in, so the socket address is always
// 127.0.0.1 and the real client is in X-Forwarded-For. Trust that header
// ONLY from loopback — accepting it from anywhere would let any caller spoof
// its IP and walk straight through the per-IP limits above.
function clientIp(req) {
  const socketIp = req.socket.remoteAddress || "";
  const loopback = socketIp === "127.0.0.1" || socketIp === "::1" || socketIp === "::ffff:127.0.0.1";
  if (loopback) {
    const fwd = String(req.headers["x-forwarded-for"] || "").split(",")[0].trim();
    if (fwd) return fwd;
  }
  return socketIp;
}

function readBody(req, limitBytes = 4096) {
  return new Promise((resolve, reject) => {
    let raw = "";
    req.on("data", (c) => {
      raw += c;
      if (raw.length > limitBytes) reject(new Error("body too large"));
    });
    req.on("end", () => {
      try {
        resolve(raw ? JSON.parse(raw) : {});
      } catch {
        reject(new Error("bad json"));
      }
    });
    req.on("error", reject);
  });
}

// ---------------------------------------------------------------- routes
// POST /player -> { uuid }
// Mints an anonymous player id. The client stores it and sends it back with
// every play. Capped per IP so it can't be used as an infinite UUID faucet.
async function postPlayer(req, res) {
  const ip = clientIp(req);
  if (overLimit("mint", ip, config.limits.mintsPerHourPerIp)) {
    return json(res, 429, { error: "too many players created from this address" });
  }
  const uuid = crypto.randomUUID();
  await db.createPlayer(uuid, ip);
  chargeHit("mint", ip);
  json(res, 200, { uuid });
}

// POST /play { gameId, character, uuid } -> { ok: true }
// Records one play. Called when a run ENDS (see GameState.finish_run), so a
// fake play costs a real run's worth of time.
async function postPlay(req, res) {
  const ip = clientIp(req);
  let body;
  try {
    body = await readBody(req);
  } catch (e) {
    return json(res, 400, { error: e.message });
  }

  const { gameId, character, uuid, kos, venues } = body;
  if (!config.games.includes(gameId)) return json(res, 400, { error: "unknown gameId" });
  if (typeof uuid !== "string" || !/^[0-9a-f-]{36}$/i.test(uuid)) {
    return json(res, 400, { error: "bad uuid" });
  }
  if (!validCharacter(gameId, character)) return json(res, 400, { error: "unknown character" });
  const koCounts = cleanKos(gameId, kos);
  if (koCounts === null) return json(res, 400, { error: "bad kos" });
  const venueCounts = cleanVenues(gameId, venues);
  if (venueCounts === null) return json(res, 400, { error: "bad venues" });

  // An unknown UUID means the caller never went through /player. That's the
  // check that makes the per-IP mint cap the real cost of scripted spam.
  if (!(await db.playerExists(uuid))) return json(res, 403, { error: "unknown player" });

  if (overLimit("play", ip, config.limits.playsPerHourPerIp)) {
    return json(res, 429, { error: "too many plays from this address" });
  }
  const age = await db.secondsSinceLastPlay(uuid);
  if (age !== null && age < config.limits.playCooldownSec) {
    return json(res, 429, { error: "slow down", retryAfterSec: config.limits.playCooldownSec - age });
  }

  await db.recordPlay({ gameId, characterName: character, playerUuid: uuid });
  if (Object.keys(koCounts).length > 0) {
    await db.recordBeatdowns({ gameId, playerUuid: uuid, counts: koCounts });
  }
  if (Object.keys(venueCounts).length > 0) {
    await db.recordVenueVisits({ gameId, playerUuid: uuid, counts: venueCounts });
  }
  chargeHit("play", ip);
  json(res, 200, { ok: true });
}

// GET /leaderboard?gameId=tight5&page=0
//   -> { page, pageCount, total, rows:     [{ rank, character, plays }],
//                          beatTotal, beatRows: [{ rank, character, kos }] }
// Two boards, one pager: rows ranks most-played, beatRows ranks most-beat-up,
// and page/pageCount span whichever board is longer (the short one just runs
// out of rows on the last pages). Rank is derived from the offset because
// MySQL 5.5 has no window functions. Ties therefore get distinct consecutive
// ranks, which is what the mock-up in the game shows anyway.
async function getLeaderboard(req, res, url) {
  const gameId = url.searchParams.get("gameId") || "";
  if (!config.games.includes(gameId)) return json(res, 400, { error: "unknown gameId" });

  const pageSize = config.pageSize;
  const total = await db.boardSize(gameId);
  const beatTotal = await db.beatSize(gameId);
  const pageCount = Math.max(Math.ceil(Math.max(total, beatTotal) / pageSize), 1);
  const page = Math.min(Math.max(Number(url.searchParams.get("page")) || 0, 0), pageCount - 1);

  const offset = page * pageSize;
  const rows = (await db.boardPage(gameId, offset, pageSize)).map((r, i) => ({
    rank: offset + i + 1,
    character: r.character_name,
    plays: Number(r.plays),
  }));
  const beatRows = (await db.beatPage(gameId, offset, pageSize)).map((r, i) => ({
    rank: offset + i + 1,
    character: r.character_name,
    kos: Number(r.kos),
  }));
  json(res, 200, { page, pageCount, total, rows, beatTotal, beatRows });
}

// GET /venues?gameId=tight5&page=0
//   -> { page, pageCount, total, rows: [{ rank, venue, entries }] }
// The most-entered-venues board, its own endpoint so its pager doesn't
// entangle with the character boards'. Same offset-derived rank.
async function getVenues(req, res, url) {
  const gameId = url.searchParams.get("gameId") || "";
  if (!config.games.includes(gameId)) return json(res, 400, { error: "unknown gameId" });

  const pageSize = config.pageSize;
  const total = await db.venueSize(gameId);
  const pageCount = Math.max(Math.ceil(total / pageSize), 1);
  const page = Math.min(Math.max(Number(url.searchParams.get("page")) || 0, 0), pageCount - 1);

  const offset = page * pageSize;
  const rows = (await db.venuePage(gameId, offset, pageSize)).map((r, i) => ({
    rank: offset + i + 1,
    venue: r.venue_name,
    entries: Number(r.entries),
  }));
  json(res, 200, { page, pageCount, total, rows });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const route = url.pathname;

  if (req.method === "OPTIONS") {
    res.writeHead(204, CORS);
    return res.end();
  }

  try {
    if (req.method === "POST" && route === "/player") return await postPlayer(req, res);
    if (req.method === "POST" && route === "/play") return await postPlay(req, res);
    if (req.method === "GET" && route === "/leaderboard") return await getLeaderboard(req, res, url);
    if (req.method === "GET" && route === "/venues") return await getVenues(req, res, url);
    if (req.method === "GET" && route === "/health") return json(res, 200, { ok: true });
  } catch (e) {
    console.error(`${req.method} ${route} failed:`, e);
    return json(res, 500, { error: "server error" });
  }

  res.writeHead(404, { "content-type": "text/plain", ...CORS });
  res.end("tight5fight leaderboard server\n");
});

async function main() {
  loadRosters();
  await db.init();
  server.listen(PORT, HOST, () => {
    console.log(`leaderboard server on ${HOST}:${PORT} (db: ${config.db.driver})`);
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
