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

  // JOKE CRAFTER — the payout formula and the upgrade shop. Server-side for
  // the same reason as jokeBook above: these numbers decide a currency that
  // buys weapon damage, so the client is never asked what anything is worth.
  jokeCrafter: {
    // Points for one joke (one setup + one punchline + one tag).
    pointsPerJoke: 100,
    // Batches of this size and up also earn bonusPerJoke for every joke from
    // the threshold on, so:  points = 100n + 100 * max(0, n - 4).
    // 5-5-5 pays 600, 10-10-10 pays 1600. Deliberately NOT a flat bonus: a
    // flat one would make exactly 5 the permanent optimum and kill any reason
    // to save up further.
    bonusFrom: 5,
    bonusPerJoke: 100,
    // Ceilings matching the panel's digit widths in scenes/scoreboard.gd —
    // 4 digits of inventory, 3 of loaded slots. Enforced here too, so a
    // hand-rolled request can't overflow what the display can render.
    maxInventory: 9999,
    maxCraft: 999,
    // Weapon upgrades: cost of the 1st, 2nd and 3rd star, in order. Doubling
    // rather than flat, so the third star costs as much as the first two
    // together and maxing ONE weapon (3,500) is a real commitment instead of
    // three identical purchases. All twelve weapons fully starred is 42,000.
    //
    // The length of this array IS the level cap — server.js derives
    // maxUpgrades from it, so the two can never drift apart.
    //
    // The damage those levels buy (+3%/+6%/+9%) lives in scripts/weapons.gd:
    // the client has to apply it mid-run with no server round trip available.
    upgradeCosts: [500, 1000, 2000],
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
    // JOKE CRAFTER. Collects are bounded by how fast a run can actually end,
    // so this only stops a scripted flood; crafts and upgrades are bounded by
    // inventory and balance anyway, and the caps are just belt and braces.
    collectsPerHourPerIp: 30,
    craftsPerHourPerIp: 60,
    upgradesPerHourPerIp: 40,
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
  jokeCrafter: { ...base.jokeCrafter, ...(overrides.jokeCrafter || {}) },
  db: { ...base.db, ...(overrides.db || {}) },
};
