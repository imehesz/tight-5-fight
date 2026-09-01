"use strict";
// Base configuration — safe for source control, so NO credentials in this
// file, ever. Environment-specific settings (DB passwords etc.) live in
// config.dev.js / config.prod.js, which are gitignored; whichever matches
// NODE_ENV is merged over these defaults (NODE_ENV=production -> prod,
// anything else -> dev). Missing override files are fine: the defaults
// below run SQLite out of the box.

const base = {
  port: 8770,
  // Loopback-only by default: in production nothing on the internet can
  // reach node directly — Apache on the same box is the only way in.
  // config.dev.js opens this up so LAN devices can join local playtests.
  host: "127.0.0.1",

  // Games allowed to write to the leaderboard. A gameId outside this list
  // is rejected before it reaches SQL, so a typo can't quietly start a
  // parallel board that nobody ever looks at.
  games: ["tight5", "celebs", "daytona", "killers", "orlando", "panhandle", "miami"],

  // Rows per leaderboard page. Must match PAGE_SIZE in scenes/scoreboard.gd.
  pageSize: 10,

  // JOKE BOOK — the daily-login grid and the streak bonus it pays out.
  // Server-side on purpose: these are the numbers that decide a score, so a
  // client is never asked what its own bonus should be.
  jokeBook: {
    // Calendar days shown in the grid, and the ceiling on the streak. 90 is
    // 10 pages of a 3x3 grid in scenes/scoreboard.gd — change both together.
    windowDays: 90,
    // Points per CONSECUTIVE day beyond the first. A first-ever login is
    // worth 0, the next day 50, and so on; at a full 90-day streak that is
    // 89 * 50 = 4,450, which is the most this can ever pay.
    pointsPerDay: 50,
    // The day boundary. Not UTC: under UTC the date rolls at ~7-8pm Eastern,
    // which would split one evening's play across two days and break streaks
    // for exactly the US evening players this is meant to reward.
    timeZone: "America/New_York",
  },

  // Shared secret for the read-only /stats endpoint behind admin.html. The
  // page forwards its pwd= query param. This file is public, so the real
  // value lives ONLY in the gitignored config.dev.js / config.prod.js;
  // while it is null here, /stats answers 403 to everything.
  adminPwd: null,

  limits: {
    // A player may bank at most one play per this many seconds. Enforced
    // against the DB (not memory), so a server restart doesn't reset it.
    playCooldownSec: 60,
    // Per-IP ceilings, enforced in memory. The IP is the one identifier a
    // client can't rotate for free, so these are what actually bound a
    // scripted attack — the UUID cooldown above only stops double-taps.
    playsPerHourPerIp: 10,
    mintsPerHourPerIp: 20,
    // Crash reports (POST /crash). One is written per session that died, so a
    // player would have to crash 12 times in an hour to hit this — and a
    // scripted flood is bounded by it AND by crashMaxRows below.
    crashesPerHourPerIp: 12,
    // JOKE BOOK pings. The client sends one per boot, and the write is
    // idempotent, so this only exists to bound a scripted flood.
    loginsPerHourPerIp: 60,
  },

  // Disk ceiling for the crash table. A row is ~300 bytes, so the cap below
  // is a couple of MB at worst, forever — the table can never become the
  // reason the VPS runs out of space. Both sweeps run on insert.
  crashRetentionDays: 45,
  crashMaxRows: 5000,

  db: {
    driver: "sqlite", // "sqlite" | "mysql" (prod)
    // sqlite:
    dataDir: `${__dirname}/data`,
    // mysql (set these in config.prod.js):
    host: null,
    port: 3306,
    user: null,
    password: null,
    database: null,
  },
};

// NODE_ENV=production -> config.prod.js (db tight5fight_db)
// anything else       -> config.dev.js  (local SQLite)
const env = process.env.NODE_ENV === "production" ? "prod" : "dev";
let overrides = {};
try {
  overrides = require(`./config.${env}.js`);
} catch (e) {
  if (e.code !== "MODULE_NOT_FOUND") throw e;
}

module.exports = {
  ...base,
  ...overrides,
  limits: { ...base.limits, ...(overrides.limits || {}) },
  jokeBook: { ...base.jokeBook, ...(overrides.jokeBook || {}) },
  db: { ...base.db, ...(overrides.db || {}) },
};
