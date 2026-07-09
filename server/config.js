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
  games: ["tight5", "celebs"],

  // Rows per leaderboard page. Must match PAGE_SIZE in scenes/scoreboard.gd.
  pageSize: 10,

  limits: {
    // A player may bank at most one play per this many seconds. Enforced
    // against the DB (not memory), so a server restart doesn't reset it.
    playCooldownSec: 60,
    // Per-IP ceilings, enforced in memory. The IP is the one identifier a
    // client can't rotate for free, so these are what actually bound a
    // scripted attack — the UUID cooldown above only stops double-taps.
    playsPerHourPerIp: 10,
    mintsPerHourPerIp: 20,
  },

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
  db: { ...base.db, ...(overrides.db || {}) },
};
