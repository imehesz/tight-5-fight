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
// Which character names each game is allowed to report. Generated from the
// game's characters.json by `npm run sync-rosters` (see sync_rosters.js) and
// committed, because the server is deployed without the game's asset tree.
// A game with no roster file falls back to shape-only validation, so adding
// a comedian mid-season degrades to "slightly laxer", never to "broken".
const rosters = new Map();

function loadRosters() {
  const dir = path.join(__dirname, "rosters");
  for (const gameId of config.games) {
    const file = path.join(dir, `${gameId}.json`);
    try {
      const names = JSON.parse(fs.readFileSync(file, "utf8"));
      rosters.set(gameId, new Set(names));
      console.log(`roster ${gameId}: ${names.length} characters`);
    } catch (e) {
      if (e.code !== "ENOENT") throw e;
      console.warn(`roster ${gameId}: MISSING (${file}) — names validated by shape only`);
    }
  }
}

// A name is acceptable if the roster knows it; with no roster, fall back to
// a conservative shape check so nothing wild reaches the database.
function validCharacter(gameId, name) {
  if (typeof name !== "string" || name.length === 0 || name.length > 64) return false;
  const roster = rosters.get(gameId);
  if (roster) return roster.has(name);
  return /^[\p{L}\p{N} .'’_-]+$/u.test(name);
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

  const { gameId, character, uuid } = body;
  if (!config.games.includes(gameId)) return json(res, 400, { error: "unknown gameId" });
  if (typeof uuid !== "string" || !/^[0-9a-f-]{36}$/i.test(uuid)) {
    return json(res, 400, { error: "bad uuid" });
  }
  if (!validCharacter(gameId, character)) return json(res, 400, { error: "unknown character" });

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
  chargeHit("play", ip);
  json(res, 200, { ok: true });
}

// GET /leaderboard?gameId=tight5&page=0
//   -> { page, pageCount, total, rows: [{ rank, character, plays }] }
// Rank is derived from the offset because MySQL 5.5 has no window functions.
// Ties therefore get distinct consecutive ranks, which is what the mock-up
// in the game shows anyway.
async function getLeaderboard(req, res, url) {
  const gameId = url.searchParams.get("gameId") || "";
  if (!config.games.includes(gameId)) return json(res, 400, { error: "unknown gameId" });

  const pageSize = config.pageSize;
  const total = await db.boardSize(gameId);
  const pageCount = Math.max(Math.ceil(total / pageSize), 1);
  const page = Math.min(Math.max(Number(url.searchParams.get("page")) || 0, 0), pageCount - 1);

  const offset = page * pageSize;
  const rows = (await db.boardPage(gameId, offset, pageSize)).map((r, i) => ({
    rank: offset + i + 1,
    character: r.character_name,
    plays: Number(r.plays),
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
