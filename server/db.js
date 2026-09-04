"use strict";
// All database access lives in this file. Two drivers, same async API:
// - "sqlite" (dev): built-in node:sqlite, zero setup, file in db.dataDir.
// - "mysql" (prod): mysql2/promise pool, credentials from config.prod.js
//   (never source control). Same pattern as i-know-flags-godot/server.
// The exported functions are the whole contract — server.js never learns
// which driver is underneath.
//
// One row per play, never a bare counter: counts are re-derivable with a
// GROUP BY, and a bad actor's rows can be deleted after the fact. A column
// that only goes up would make abuse permanent and unattributable.

const path = require("node:path");
const fs = require("node:fs");
const config = require("./config");

const DRIVER = config.db.driver;
let sqlite; // DatabaseSync
let pool;   // mysql2 pool

// SQLite keeps TEXT timestamps + AUTOINCREMENT; MySQL uses AUTO_INCREMENT
// and needs explicit lengths/engine. Kept side by side so the dialects
// can't drift apart unnoticed.
const SCHEMA = {
  sqlite: [
    `CREATE TABLE IF NOT EXISTS players (
      uuid       TEXT PRIMARY KEY,
      created_ip TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE TABLE IF NOT EXISTS plays (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      game_id        TEXT NOT NULL,
      character_name TEXT NOT NULL,
      player_uuid    TEXT NOT NULL,
      score          INTEGER NOT NULL DEFAULT 0,
      seconds        INTEGER NOT NULL DEFAULT 0,
      weapon         TEXT NOT NULL DEFAULT '',
      created_at     TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE INDEX IF NOT EXISTS idx_board ON plays (game_id, character_name)`,
    `CREATE INDEX IF NOT EXISTS idx_uuid  ON plays (player_uuid, id)`,
    `CREATE TABLE IF NOT EXISTS beatdowns (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      game_id        TEXT NOT NULL,
      character_name TEXT NOT NULL,
      attacker_name  TEXT NOT NULL DEFAULT '',
      player_uuid    TEXT NOT NULL,
      count          INTEGER NOT NULL,
      created_at     TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE INDEX IF NOT EXISTS idx_beat_board ON beatdowns (game_id, character_name)`,
    `CREATE INDEX IF NOT EXISTS idx_beat_uuid  ON beatdowns (player_uuid, id)`,
    `CREATE TABLE IF NOT EXISTS venue_visits (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      game_id     TEXT NOT NULL,
      venue_name  TEXT NOT NULL,
      player_uuid TEXT NOT NULL,
      count       INTEGER NOT NULL,
      created_at  TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE INDEX IF NOT EXISTS idx_venue_board ON venue_visits (game_id, venue_name)`,
    `CREATE INDEX IF NOT EXISTS idx_venue_uuid  ON venue_visits (player_uuid, id)`,
    `CREATE TABLE IF NOT EXISTS venue_fights (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      game_id     TEXT NOT NULL,
      venue_name  TEXT NOT NULL,
      player_uuid TEXT NOT NULL,
      count       INTEGER NOT NULL,
      created_at  TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE INDEX IF NOT EXISTS idx_fight_board ON venue_fights (game_id, venue_name)`,
    `CREATE INDEX IF NOT EXISTS idx_fight_uuid  ON venue_fights (player_uuid, id)`,
    `CREATE TABLE IF NOT EXISTS sponsor_impressions (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      game_id     TEXT NOT NULL,
      sponsor_id  TEXT NOT NULL,
      player_uuid TEXT NOT NULL,
      count       INTEGER NOT NULL,
      created_at  TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE INDEX IF NOT EXISTS idx_sponsor_report ON sponsor_impressions (game_id, sponsor_id)`,
    `CREATE INDEX IF NOT EXISTS idx_sponsor_uuid   ON sponsor_impressions (player_uuid, id)`,
    // One row per session that DIED — the browser tab went down mid-play and
    // came back on its own (see web/shell.html). Written at most once per
    // crash, per device, and pruned by both age and row count, so this table
    // has a hard ceiling instead of growing with the player base.
    `CREATE TABLE IF NOT EXISTS crashes (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      game_id      TEXT    NOT NULL,
      player_uuid  TEXT    NOT NULL DEFAULT '',
      reason       TEXT    NOT NULL DEFAULT '',
      scene        TEXT    NOT NULL DEFAULT '',
      nav_type     TEXT    NOT NULL DEFAULT '',
      uptime_sec   INTEGER NOT NULL DEFAULT 0,
      heap_bytes   INTEGER NOT NULL DEFAULT 0,
      mem_static   INTEGER NOT NULL DEFAULT 0,
      tex_bytes    INTEGER NOT NULL DEFAULT 0,
      nodes        INTEGER NOT NULL DEFAULT 0,
      objects      INTEGER NOT NULL DEFAULT 0,
      orphans      INTEGER NOT NULL DEFAULT 0,
      resources    INTEGER NOT NULL DEFAULT 0,
      fps          INTEGER NOT NULL DEFAULT 0,
      venues       INTEGER NOT NULL DEFAULT 0,
      boots        INTEGER NOT NULL DEFAULT 0,
      hidden_count INTEGER NOT NULL DEFAULT 0,
      dpr          REAL    NOT NULL DEFAULT 0,
      screen_w     INTEGER NOT NULL DEFAULT 0,
      screen_h     INTEGER NOT NULL DEFAULT 0,
      cores        INTEGER NOT NULL DEFAULT 0,
      user_agent   TEXT    NOT NULL DEFAULT '',
      events       TEXT    NOT NULL DEFAULT '',
      created_at   TEXT    NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE INDEX IF NOT EXISTS idx_crash_game ON crashes (game_id, id)`,
    // JOKE BOOK: one row per player per day they opened the game. `day` is a
    // calendar date in US Eastern (see easternDay() in server.js), NOT a
    // timestamp and NOT UTC — under UTC the day would roll over at ~7-8pm ET
    // and split a single evening's play across two dates.
    //
    // The composite PRIMARY KEY is the whole idempotency story: the client
    // pings this on every boot, and a second ping on the same day is an
    // INSERT OR IGNORE that changes nothing.
    `CREATE TABLE IF NOT EXISTS logins (
      player_uuid TEXT NOT NULL,
      day         TEXT NOT NULL,
      created_at  TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (player_uuid, day)
    )`,
    // JOKE CRAFTER — three tables, all EVENT rows, never a balance column.
    // Inventory and joke points are both derived (see jokeCrafterState), for
    // the reason at the top of this file: a stored balance that only goes up
    // would make an inflated one permanent and unattributable, and this one
    // buys weapon upgrades.
    //
    // One row per BANKED RUN, not per pickup: the client tallies what it
    // walked over and posts once when the run ends (GameState.finish_run).
    // The UNIQUE is the whole idempotency story — a retry after a lost
    // response is an INSERT OR IGNORE that changes nothing, so a flaky
    // network can never double-credit a currency.
    `CREATE TABLE IF NOT EXISTS component_drops (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      game_id     TEXT NOT NULL,
      player_uuid TEXT NOT NULL,
      run_nonce   TEXT NOT NULL,
      setups      INTEGER NOT NULL DEFAULT 0,
      punchlines  INTEGER NOT NULL DEFAULT 0,
      tags        INTEGER NOT NULL DEFAULT 0,
      created_at  TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (player_uuid, run_nonce)
    )`,
    `CREATE INDEX IF NOT EXISTS idx_drops_uuid ON component_drops (player_uuid, id)`,
    // One row per craft. `n` is the batch size (equal setups/punchlines/tags
    // consumed); `points` is what the server decided it was worth, stored so
    // a later change to the payout formula never silently restates history.
    `CREATE TABLE IF NOT EXISTS joke_crafts (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      player_uuid TEXT NOT NULL,
      n           INTEGER NOT NULL,
      points      INTEGER NOT NULL,
      created_at  TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE INDEX IF NOT EXISTS idx_crafts_uuid ON joke_crafts (player_uuid, id)`,
    // One row per upgrade PURCHASED, so a weapon at 3 stars has three rows.
    // The UNIQUE on (player, weapon, level) means the same level can never be
    // bought twice even if two taps race — the second insert just fails.
    `CREATE TABLE IF NOT EXISTS weapon_upgrades (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      player_uuid TEXT NOT NULL,
      weapon_id   TEXT NOT NULL,
      level       INTEGER NOT NULL,
      cost        INTEGER NOT NULL,
      created_at  TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (player_uuid, weapon_id, level)
    )`,
    `CREATE INDEX IF NOT EXISTS idx_upg_uuid ON weapon_upgrades (player_uuid, id)`,
  ],
  // NB: written to run on the prod VPS's MySQL 5.5 as well as 8.x.
  // - 5.5 permits only ONE TIMESTAMP column per table with a
  //   CURRENT_TIMESTAMP default, so there is no updated_at anywhere.
  // - utf8mb4 is 4 bytes/char and InnoDB's index limit on 5.5 is 767
  //   bytes, so every indexed column stays well under 191 chars.
  // - No window functions on 5.5: rank is computed in server.js from the
  //   page offset, not with RANK() OVER ().
  mysql: [
    `CREATE TABLE IF NOT EXISTS players (
      uuid       CHAR(36)    NOT NULL,
      created_ip VARCHAR(45) NOT NULL DEFAULT '',
      created_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (uuid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS plays (
      id             INT         NOT NULL AUTO_INCREMENT,
      game_id        VARCHAR(32) NOT NULL,
      character_name VARCHAR(64) NOT NULL,
      player_uuid    CHAR(36)    NOT NULL,
      score          INT         NOT NULL DEFAULT 0,
      seconds        INT         NOT NULL DEFAULT 0,
      weapon         VARCHAR(24) NOT NULL DEFAULT '',
      created_at     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY idx_board (game_id, character_name),
      KEY idx_uuid (player_uuid, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS beatdowns (
      id             INT         NOT NULL AUTO_INCREMENT,
      game_id        VARCHAR(32) NOT NULL,
      character_name VARCHAR(64) NOT NULL,
      attacker_name  VARCHAR(64) NOT NULL DEFAULT '',
      player_uuid    CHAR(36)    NOT NULL,
      count          INT         NOT NULL,
      created_at     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY idx_beat_board (game_id, character_name),
      KEY idx_beat_uuid (player_uuid, id),
      KEY idx_beef (game_id, attacker_name, character_name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS venue_visits (
      id          INT         NOT NULL AUTO_INCREMENT,
      game_id     VARCHAR(32) NOT NULL,
      venue_name  VARCHAR(64) NOT NULL,
      player_uuid CHAR(36)    NOT NULL,
      count       INT         NOT NULL,
      created_at  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY idx_venue_board (game_id, venue_name),
      KEY idx_venue_uuid (player_uuid, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS venue_fights (
      id          INT         NOT NULL AUTO_INCREMENT,
      game_id     VARCHAR(32) NOT NULL,
      venue_name  VARCHAR(64) NOT NULL,
      player_uuid CHAR(36)    NOT NULL,
      count       INT         NOT NULL,
      created_at  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY idx_fight_board (game_id, venue_name),
      KEY idx_fight_uuid (player_uuid, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS sponsor_impressions (
      id          INT         NOT NULL AUTO_INCREMENT,
      game_id     VARCHAR(32) NOT NULL,
      sponsor_id  VARCHAR(40) NOT NULL,
      player_uuid CHAR(36)    NOT NULL,
      count       INT         NOT NULL,
      created_at  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY idx_sponsor_report (game_id, sponsor_id),
      KEY idx_sponsor_uuid (player_uuid, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    // See the SQLite copy above. user_agent is the one long column and it is
    // never indexed, so 5.5's 767-byte index limit is not in play.
    `CREATE TABLE IF NOT EXISTS crashes (
      id           INT          NOT NULL AUTO_INCREMENT,
      game_id      VARCHAR(32)  NOT NULL,
      player_uuid  VARCHAR(36)  NOT NULL DEFAULT '',
      reason       VARCHAR(32)  NOT NULL DEFAULT '',
      scene        VARCHAR(32)  NOT NULL DEFAULT '',
      nav_type     VARCHAR(16)  NOT NULL DEFAULT '',
      uptime_sec   INT          NOT NULL DEFAULT 0,
      heap_bytes   BIGINT       NOT NULL DEFAULT 0,
      mem_static   BIGINT       NOT NULL DEFAULT 0,
      tex_bytes    BIGINT       NOT NULL DEFAULT 0,
      nodes        INT          NOT NULL DEFAULT 0,
      objects      INT          NOT NULL DEFAULT 0,
      orphans      INT          NOT NULL DEFAULT 0,
      resources    INT          NOT NULL DEFAULT 0,
      fps          INT          NOT NULL DEFAULT 0,
      venues       INT          NOT NULL DEFAULT 0,
      boots        INT          NOT NULL DEFAULT 0,
      hidden_count INT          NOT NULL DEFAULT 0,
      dpr          FLOAT        NOT NULL DEFAULT 0,
      screen_w     INT          NOT NULL DEFAULT 0,
      screen_h     INT          NOT NULL DEFAULT 0,
      cores        INT          NOT NULL DEFAULT 0,
      user_agent   VARCHAR(255) NOT NULL DEFAULT '',
      events       TEXT,
      created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY idx_crash_game (game_id, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    // See the sqlite copy above for what `day` means. DATE, not DATETIME:
    // the value is a calendar day the server already resolved, so there is
    // no time part to get reinterpreted by a session timezone.
    `CREATE TABLE IF NOT EXISTS logins (
      player_uuid CHAR(36) NOT NULL,
      day         DATE     NOT NULL,
      created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (player_uuid, day)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    // JOKE CRAFTER. See the sqlite block above for why these are event rows
    // and not balance columns. weapon_id is VARCHAR(24) to match plays.weapon,
    // and every indexed column here stays far under the 191-char ceiling 5.5
    // imposes on utf8mb4 index keys.
    `CREATE TABLE IF NOT EXISTS component_drops (
      id          INT         NOT NULL AUTO_INCREMENT,
      game_id     VARCHAR(32) NOT NULL,
      player_uuid CHAR(36)    NOT NULL,
      run_nonce   VARCHAR(36) NOT NULL,
      setups      INT         NOT NULL DEFAULT 0,
      punchlines  INT         NOT NULL DEFAULT 0,
      tags        INT         NOT NULL DEFAULT 0,
      created_at  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uniq_drop (player_uuid, run_nonce),
      KEY idx_drops_uuid (player_uuid, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS joke_crafts (
      id          INT       NOT NULL AUTO_INCREMENT,
      player_uuid CHAR(36)  NOT NULL,
      n           INT       NOT NULL,
      points      INT       NOT NULL,
      created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY idx_crafts_uuid (player_uuid, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS weapon_upgrades (
      id          INT         NOT NULL AUTO_INCREMENT,
      player_uuid CHAR(36)    NOT NULL,
      weapon_id   VARCHAR(24) NOT NULL,
      level       INT         NOT NULL,
      cost        INT         NOT NULL,
      created_at  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uniq_upg (player_uuid, weapon_id, level),
      KEY idx_upg_uuid (player_uuid, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  ],
};

// Indexes over a column that migrate() may only just have added. These CANNOT
// live in SCHEMA above: those statements run BEFORE migrate(), so on a database
// created back when the column didn't exist, CREATE INDEX would name a column
// that isn't there yet and take the whole boot down with it.
//
// MySQL needs no equivalent — its indexes ride inside CREATE TABLE, which is a
// no-op on an existing table, so a live prod table simply doesn't get idx_beef
// (see the note in migrate(); the beatdowns table is small enough not to care).
const POST_MIGRATE = {
  sqlite: [
    `CREATE INDEX IF NOT EXISTS idx_beef ON beatdowns (game_id, attacker_name, character_name)`,
  ],
  mysql: [],
};

// Age of a row in seconds. The one place the dialects genuinely differ.
const AGE_SEC = {
  sqlite: "(strftime('%s','now') - strftime('%s', created_at))",
  mysql: "TIMESTAMPDIFF(SECOND, created_at, NOW())",
};

// "created_at is older than N days", for the retention sweeps. N is always an
// integer this module coerced itself, never a caller's string.
const OLDER_THAN_DAYS = {
  sqlite: (days) => `created_at < datetime('now', '-${Number(days)} days')`,
  mysql: (days) => `created_at < DATE_SUB(NOW(), INTERVAL ${Number(days)} DAY)`,
};

async function init() {
  if (DRIVER === "sqlite") {
    const { DatabaseSync } = require("node:sqlite");
    fs.mkdirSync(config.db.dataDir, { recursive: true });
    sqlite = new DatabaseSync(path.join(config.db.dataDir, "tight5fight.db"));
    for (const ddl of SCHEMA.sqlite) sqlite.exec(ddl);
  } else if (DRIVER === "mysql") {
    const mysql = require("mysql2/promise");
    pool = mysql.createPool({
      host: config.db.host,
      port: config.db.port,
      user: config.db.user,
      password: config.db.password,
      database: config.db.database,
      waitForConnections: true,
      connectionLimit: 10,
    });
    for (const ddl of SCHEMA.mysql) await pool.query(ddl);
  } else {
    throw new Error(`unknown db driver "${DRIVER}"`);
  }
  await migrate();
  for (const ddl of POST_MIGRATE[DRIVER]) {
    if (DRIVER === "sqlite") sqlite.exec(ddl);
    else await pool.query(ddl);
  }
}

// Idempotent column additions for databases created before the column
// existed (CREATE TABLE IF NOT EXISTS never touches an existing table).
// Neither MySQL 5.5 nor SQLite has ADD COLUMN IF NOT EXISTS, so the
// duplicate-column error on re-runs is the expected no-op signal.
async function migrate() {
  const alters = [
    "ALTER TABLE plays ADD COLUMN score INT NOT NULL DEFAULT 0",
    // How long the run lasted. 0 on every row banked before this column
    // existed (and by any client too old to send it), which is why the
    // averages below ignore zeros rather than counting them as instant deaths.
    "ALTER TABLE plays ADD COLUMN seconds INT NOT NULL DEFAULT 0",
    // The WeaponId carried that run (see shared/assets/weapons/weapons.json).
    // '' on rows banked before the column existed or by clients too old to
    // send it — the popularity report skips those rather than inventing a
    // "mic" that was never actually reported.
    "ALTER TABLE plays ADD COLUMN weapon VARCHAR(24) NOT NULL DEFAULT ''",
    // Who did the beating — the comedian the run was PLAYED as. '' on every
    // row banked before this column existed; backfill_beef.js stamps what it
    // can reconstruct, and the BEEF board excludes whatever stays ''.
    // NB: the matching idx_beef index is NOT added here. The catch below only
    // swallows "duplicate column", not "duplicate key", and broadening it is
    // more invasive than it is worth on a table this small — fresh installs
    // get the index from the CREATE, and an existing prod table can have it
    // added by hand (see requirements/beef-meter-implementation.md).
    "ALTER TABLE beatdowns ADD COLUMN attacker_name VARCHAR(64) NOT NULL DEFAULT ''",
  ];
  for (const sql of alters) {
    try {
      if (DRIVER === "sqlite") sqlite.exec(sql);
      else await pool.query(sql);
    } catch (e) {
      if (!/duplicate column/i.test(e.message)) throw e;
    }
  }
}

// Tiny helpers so every query reads the same regardless of driver. Note
// pool.query (not .execute): mysql2 interpolates client-side, which keeps
// LIMIT/OFFSET working on MySQL 5.5, where they can't be bound parameters.
// Every value reaching these is either a "?" placeholder or an integer
// this module coerced itself.
async function run(sql, params = []) {
  if (DRIVER === "sqlite") return sqlite.prepare(sql).run(...params);
  await pool.query(sql, params);
}

async function get(sql, params = []) {
  if (DRIVER === "sqlite") return sqlite.prepare(sql).get(...params);
  const [rows] = await pool.query(sql, params);
  return rows[0];
}

async function all(sql, params = []) {
  if (DRIVER === "sqlite") return sqlite.prepare(sql).all(...params);
  const [rows] = await pool.query(sql, params);
  return rows;
}

// ---------------------------------------------------------------- players
async function createPlayer(uuid, ip) {
  await run("INSERT INTO players (uuid, created_ip) VALUES (?, ?)", [uuid, ip]);
}

async function playerExists(uuid) {
  const row = await get("SELECT uuid FROM players WHERE uuid = ?", [uuid]);
  return !!row;
}

// ---------------------------------------------------------------- joke book
// Mark this player present for `day` (a YYYY-MM-DD the caller resolved).
// Idempotent: the PK makes a repeat ping on the same day a no-op, so the
// client can ping on every single boot without thinking about it.
async function recordLogin(uuid, day) {
  const verb = DRIVER === "sqlite" ? "INSERT OR IGNORE" : "INSERT IGNORE";
  await run(`${verb} INTO logins (player_uuid, day) VALUES (?, ?)`, [uuid, day]);
}

// The days this player was present, from `fromDay` to `toDay` inclusive, as
// an array of YYYY-MM-DD strings. Deliberately returns the raw days rather
// than a streak: MySQL 5.5 has no window functions, so the run-length walk
// happens in JS (see jokeBook() in server.js) where it is testable anyway.
async function loginDays(uuid, fromDay, toDay) {
  const rows = await all(
    `SELECT day FROM logins
      WHERE player_uuid = ? AND day >= ? AND day <= ?
      ORDER BY day DESC`,
    [uuid, fromDay, toDay]
  );
  // MySQL hands back a JS Date for a DATE column; sqlite hands back the
  // string it stored. Normalise to YYYY-MM-DD so callers never have to care.
  return rows.map((r) =>
    r.day instanceof Date ? r.day.toISOString().slice(0, 10) : String(r.day)
  );
}

// ------------------------------------------------------------ joke crafter
// Everything the JOKE CRAFTER pane needs, derived from the event rows in one
// pass each. No balance is ever stored: inventory is what was collected minus
// what was crafted, and points are what crafts paid minus what upgrades cost.
//
// Three small aggregates rather than one join: a player has a handful of rows
// per table, the queries stay readable, and MySQL 5.5 has no CTEs to make a
// single query any tidier.
async function jokeCrafterState(uuid) {
  const drops = await get(
    `SELECT COALESCE(SUM(setups), 0)     AS setups,
            COALESCE(SUM(punchlines), 0) AS punchlines,
            COALESCE(SUM(tags), 0)       AS tags
       FROM component_drops WHERE player_uuid = ?`,
    [uuid]
  );
  const crafted = await get(
    `SELECT COALESCE(SUM(n), 0)      AS used,
            COALESCE(SUM(points), 0) AS earned
       FROM joke_crafts WHERE player_uuid = ?`,
    [uuid]
  );
  const spent = await get(
    "SELECT COALESCE(SUM(cost), 0) AS spent FROM weapon_upgrades WHERE player_uuid = ?",
    [uuid]
  );
  // A craft consumes n of EACH kind, which is what makes one `used` figure
  // enough to net all three off.
  const used = Number(crafted.used);
  return {
    setups: Number(drops.setups) - used,
    punchlines: Number(drops.punchlines) - used,
    tags: Number(drops.tags) - used,
    points: Number(crafted.earned) - Number(spent.spent),
  };
}

// This player's upgrade level per weapon, as { weaponId: level }. Weapons with
// no rows are simply absent — the client treats a missing key as 0 rather than
// the server sending a row per weapon it may not even ship any more.
async function weaponUpgrades(uuid) {
  const rows = await all(
    `SELECT weapon_id, MAX(level) AS level
       FROM weapon_upgrades WHERE player_uuid = ? GROUP BY weapon_id`,
    [uuid]
  );
  const out = {};
  for (const r of rows) out[String(r.weapon_id)] = Number(r.level);
  return out;
}

// Bank one run's collected components. Idempotent on (player, run_nonce): a
// client retrying after a lost response inserts nothing the second time, which
// is what stops a dropped reply from minting free currency.
// Returns true if this call actually wrote a row.
async function recordComponentDrop({ gameId, playerUuid, runNonce, setups, punchlines, tags }) {
  const verb = DRIVER === "sqlite" ? "INSERT OR IGNORE" : "INSERT IGNORE";
  const res = await run(
    `${verb} INTO component_drops
       (game_id, player_uuid, run_nonce, setups, punchlines, tags)
       VALUES (?, ?, ?, ?, ?, ?)`,
    [gameId, playerUuid, runNonce, setups, punchlines, tags]
  );
  // sqlite's run() hands back {changes}; the mysql helper returns undefined,
  // so fall back to re-reading. Only used for logging, never for the payout.
  if (res && typeof res.changes === "number") return res.changes > 0;
  return true;
}

async function recordCraft({ playerUuid, n, points }) {
  await run(
    "INSERT INTO joke_crafts (player_uuid, n, points) VALUES (?, ?, ?)",
    [playerUuid, n, points]
  );
}

// Buy one level. Returns false if the row already existed — the UNIQUE on
// (player, weapon, level) is what makes two racing taps cost 500 points once
// rather than twice.
async function recordUpgrade({ playerUuid, weaponId, level, cost }) {
  const verb = DRIVER === "sqlite" ? "INSERT OR IGNORE" : "INSERT IGNORE";
  const res = await run(
    `${verb} INTO weapon_upgrades (player_uuid, weapon_id, level, cost)
       VALUES (?, ?, ?, ?)`,
    [playerUuid, weaponId, level, cost]
  );
  if (res && typeof res.changes === "number") return res.changes > 0;
  return true;
}


// ---------------------------------------------------------------- plays
// Seconds since this player's last recorded play, or null if they have none.
// Durable by construction: a server restart can't hand anyone a fresh window.
async function secondsSinceLastPlay(uuid) {
  const row = await get(
    `SELECT ${AGE_SEC[DRIVER]} AS age FROM plays
      WHERE player_uuid = ? ORDER BY id DESC LIMIT 1`,
    [uuid]
  );
  return row ? Number(row.age) : null;
}

async function recordPlay({ gameId, characterName, playerUuid, score, seconds, weapon }) {
  await run(
    `INSERT INTO plays (game_id, character_name, player_uuid, score, seconds, weapon)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [gameId, characterName, playerUuid, score || 0, seconds || 0, weapon || ""]
  );
}

// ---------------------------------------------------------------- beatdowns
// Who this run's player knocked out, one row per beaten character (with a
// count, since one run KOs the same comedian many times). Same shape as
// plays for the same reason: attributable to a player_uuid, so a cheater's
// rows can be deleted and the SUMs below simply heal.
//
// attackerName is the comedian the run was PLAYED as, so the row carries the
// whole beef pair (attacker_name -> character_name) for the BEEF board. It is
// roster-validated for free: postPlay only reaches here after the same string
// passed validCharacter().
async function recordBeatdowns({ gameId, attackerName, playerUuid, counts }) {
  for (const [name, count] of Object.entries(counts)) {
    await run(
      "INSERT INTO beatdowns (game_id, character_name, attacker_name, player_uuid, count) VALUES (?, ?, ?, ?, ?)",
      [gameId, name, attackerName || "", playerUuid, count]
    );
  }
}

// ---------------------------------------------------------------- venues
// Which doors this run's player walked through, one row per venue name (with
// a count — the street cycles the venue list, so a deep run re-enters the
// same name). Same attributable shape as beatdowns, for the same reason.
async function recordVenueVisits({ gameId, playerUuid, counts }) {
  for (const [name, count] of Object.entries(counts)) {
    await run(
      "INSERT INTO venue_visits (game_id, venue_name, player_uuid, count) VALUES (?, ?, ?, ?)",
      [gameId, name, playerUuid, count]
    );
  }
}

// KOs this run's player landed inside each venue, one row per venue name
// (with a count) — the "fights" tally under TOP VENUES. Same attributable
// shape as venue_visits, for the same reason.
async function recordVenueFights({ gameId, playerUuid, counts }) {
  for (const [name, count] of Object.entries(counts)) {
    await run(
      "INSERT INTO venue_fights (game_id, venue_name, player_uuid, count) VALUES (?, ?, ?, ?)",
      [gameId, name, playerUuid, count]
    );
  }
}

// Total KOs per venue for one game — merged onto the entries-ranked podium
// rows in server.js. Whole-game GROUP BY, no paging: the venue roster is a
// handful of names.
async function venueFightTotals(gameId) {
  return all(
    `SELECT venue_name, SUM(count) AS kos
       FROM venue_fights
      WHERE game_id = ?
      GROUP BY venue_name`,
    [gameId]
  );
}

// ---------------------------------------------------------------- sponsors
// Billboard impressions a run's player actually saw, one row per sponsor id
// (with a count). Attributable like beatdowns: an inflated report heals when
// the offending player_uuid's rows are deleted.
async function recordSponsorImpressions({ gameId, playerUuid, counts }) {
  for (const [sponsorId, count] of Object.entries(counts)) {
    await run(
      "INSERT INTO sponsor_impressions (game_id, sponsor_id, player_uuid, count) VALUES (?, ?, ?, ?)",
      [gameId, sponsorId, playerUuid, count]
    );
  }
}

// The billing view: impressions per (sponsor, game), last 30 days + all
// time. Whole table, no paging — the sponsor roster is a handful of rows.
// CASE instead of FILTER keeps it MySQL 5.5-safe; the window expression is
// the dialect constant below, never user input.
async function sponsorReport() {
  return all(
    `SELECT sponsor_id, game_id,
            SUM(CASE WHEN created_at >= ${SINCE[DRIVER].month} THEN count ELSE 0 END) AS month_total,
            SUM(count) AS all_time
       FROM sponsor_impressions
      GROUP BY sponsor_id, game_id
      ORDER BY sponsor_id ASC, game_id ASC`
  );
}

// One page of the most-entered-venues board. Same stable ordering contract
// as boardPage.
async function venuePage(gameId, offset, limit) {
  return all(
    `SELECT venue_name, SUM(count) AS entries
       FROM venue_visits
      WHERE game_id = ?
      GROUP BY venue_name
      ORDER BY entries DESC, venue_name ASC
      LIMIT ${Number(limit)} OFFSET ${Number(offset)}`,
    [gameId]
  );
}

async function venueSize(gameId) {
  const row = await get(
    "SELECT COUNT(DISTINCT venue_name) AS n FROM venue_visits WHERE game_id = ?",
    [gameId]
  );
  return Number(row ? row.n : 0);
}

// ---------------------------------------------------------------- weapons
// Weapon popularity for admin.html: plays per WeaponId for one game, last 30
// days riding along with all time (same CASE-window trick as sponsorReport,
// for the same MySQL 5.5 reason). Rows with weapon = '' predate the column or
// came from old clients, so they are excluded rather than shown as a fake
// blank weapon. Whole-game GROUP BY, no paging: the rack is a dozen ids.
async function weaponReport(gameId) {
  return all(
    `SELECT weapon,
            SUM(CASE WHEN created_at >= ${SINCE[DRIVER].month} THEN 1 ELSE 0 END) AS month_total,
            COUNT(*) AS all_time
       FROM plays
      WHERE game_id = ? AND weapon <> ''
      GROUP BY weapon
      ORDER BY all_time DESC, weapon ASC`,
    [gameId]
  );
}

// ---------------------------------------------------------------- stats
// Play volume for admin.html: total plays and distinct players, per recency
// window and all-time. The window expressions are inlined per dialect and
// contain no user input. "today" is since local midnight on MySQL (CURDATE)
// but since UTC midnight on SQLite — dev-only, so the drift doesn't matter.
const SINCE = {
  sqlite: {
    today: "datetime('now','start of day')",
    week: "datetime('now','-7 days')",
    month: "datetime('now','-30 days')",
  },
  mysql: {
    today: "CURDATE()",
    week: "NOW() - INTERVAL 7 DAY",
    month: "NOW() - INTERVAL 30 DAY",
  },
};

// Bucket a row into its calendar day as a 'YYYY-MM-DD' STRING (not a date
// object) — formatted in SQL so both drivers return the exact same shape and
// the trend client can key on it directly. mysql2 would otherwise hand back a
// JS Date for a bare DATE(), serializing to an ISO timestamp the client can't
// match. Same UTC-vs-local caveat as SINCE; the 30-day trend charts are
// cosmetic, so a boundary row landing a day off is harmless.
const DAY = {
  sqlite: "strftime('%Y-%m-%d', created_at)",
  mysql: "DATE_FORMAT(created_at, '%Y-%m-%d')",
};

// A run at or past this many seconds lasted the full five minutes. NOT the
// same as "timed out": clearing a venue or catching a good set box adds
// seconds back (GameState.VENUE_TIME_BONUS / BOX_TIME_BONUS), so a run can
// run long and still end in a death. The game's base limit is 300s
// (GameState.RUN_TIME); the slack absorbs rounding and any future trim.
const FULL_RUN_SEC = 295;

// Run-length columns for one window's WHERE clause. Zeros are EXCLUDED from
// the average on purpose: they are rows banked before the client sent a
// duration, not five-second runs. `timed` is how many of the rows that DO
// carry a duration ran the clock all the way out.
const RUN_LEN_COLS = `
  AVG(NULLIF(seconds, 0))                                     AS avg_sec,
  SUM(CASE WHEN seconds > 0 THEN 1 ELSE 0 END)                AS timed_rows,
  SUM(CASE WHEN seconds >= ${FULL_RUN_SEC} THEN 1 ELSE 0 END) AS full_runs`;

function volumeRow(row) {
  return {
    plays: Number(row.plays),
    players: Number(row.players),
    // null (not 0) when no row in the window carries a duration yet, so the
    // admin page can say "no data" instead of "0s".
    avgSeconds: row.avg_sec == null ? null : Math.round(Number(row.avg_sec)),
    timedRuns: Number(row.timed_rows || 0),
    fullRuns: Number(row.full_runs || 0),
  };
}

async function playVolume(gameId) {
  const out = {};
  for (const window of ["today", "week", "month"]) {
    const row = await get(
      `SELECT COUNT(*) AS plays, COUNT(DISTINCT player_uuid) AS players,
              ${RUN_LEN_COLS}
         FROM plays
        WHERE game_id = ? AND created_at >= ${SINCE[DRIVER][window]}`,
      [gameId]
    );
    out[window] = volumeRow(row);
  }
  const row = await get(
    `SELECT COUNT(*) AS plays, COUNT(DISTINCT player_uuid) AS players,
            ${RUN_LEN_COLS}
       FROM plays WHERE game_id = ?`,
    [gameId]
  );
  out.allTime = volumeRow(row);
  return out;
}

// Whole-ecosystem headline numbers, every game combined. plays counts rows
// (one per FINISHED run); beatdowns/venue_visits carry per-run counts, so
// their totals are SUM(count), not row counts. Scalar subqueries keep it one
// round-trip and MySQL 5.5-safe.
async function ecosystemTotals() {
  const row = await get(
    `SELECT
       (SELECT COUNT(*)                FROM plays)        AS runs,
       (SELECT COALESCE(SUM(count),0)  FROM beatdowns)    AS npcs,
       (SELECT COALESCE(SUM(count),0)  FROM venue_visits) AS venues`
  );
  return {
    runs: Number(row.runs),
    npcsBeaten: Number(row.npcs),
    venueFights: Number(row.venues),
  };
}

// ---------------------------------------------------------------- board
// One page of the character board, ranked by the highest score anyone has
// posted with that comedian (the play count still rides along — the admin
// stats page and older clients read it). Ties break on plays then name so
// paging is stable (an unstable sort can drop or repeat a row across
// pages). Rank is not in the SQL — MySQL 5.5 has no window functions — so
// server.js derives it from the offset.
async function boardPage(gameId, offset, limit) {
  return all(
    `SELECT character_name, COUNT(*) AS plays, MAX(score) AS best
       FROM plays
      WHERE game_id = ?
      GROUP BY character_name
      ORDER BY best DESC, plays DESC, character_name ASC
      LIMIT ${Number(limit)} OFFSET ${Number(offset)}`,
    [gameId]
  );
}

// Top of the MOST PLAYED board: ranked by play count (popularity), with the
// character's total banked score riding along — the public stats podium
// shows "most played" but displays the summed score. Distinct from
// boardPage, which ranks by best single score.
async function mostPlayedTop(gameId, limit) {
  return all(
    `SELECT character_name, COUNT(*) AS plays, COALESCE(SUM(score), 0) AS total
       FROM plays
      WHERE game_id = ?
      GROUP BY character_name
      ORDER BY plays DESC, total DESC, character_name ASC
      LIMIT ${Number(limit)}`,
    [gameId]
  );
}

// Distinct characters with at least one play — the row count of the board.
async function boardSize(gameId) {
  const row = await get(
    "SELECT COUNT(DISTINCT character_name) AS n FROM plays WHERE game_id = ?",
    [gameId]
  );
  return Number(row ? row.n : 0);
}

// One page of the most-beat-up board: total KOs suffered per character,
// worst-beaten first. Same stable ordering contract as boardPage.
async function beatPage(gameId, offset, limit) {
  return all(
    `SELECT character_name, SUM(count) AS kos
       FROM beatdowns
      WHERE game_id = ?
      GROUP BY character_name
      ORDER BY kos DESC, character_name ASC
      LIMIT ${Number(limit)} OFFSET ${Number(offset)}`,
    [gameId]
  );
}

async function beatSize(gameId) {
  const row = await get(
    "SELECT COUNT(DISTINCT character_name) AS n FROM beatdowns WHERE game_id = ?",
    [gameId]
  );
  return Number(row ? row.n : 0);
}

// ---------------------------------------------------------------- beef
// The BEEF METER reads the same beatdowns rows from the OTHER end: not "who
// got beaten" but "who beat them". Every query below therefore excludes
// attacker_name = '' — legacy rows the backfill could not match, which know
// their victim but not their aggressor and would otherwise show up as a
// nameless comedian with an enormous grudge.

// One page of the left-hand list: comedians ranked by how many KOs players
// have landed while playing AS them. Same stable ordering contract as
// boardPage (ties break on name so paging can't drop or repeat a row).
async function beefAttackerPage(gameId, offset, limit) {
  return all(
    `SELECT attacker_name AS attacker, SUM(count) AS kos
       FROM beatdowns
      WHERE game_id = ? AND attacker_name <> ''
      GROUP BY attacker_name
      ORDER BY kos DESC, attacker_name ASC
      LIMIT ${Number(limit)} OFFSET ${Number(offset)}`,
    [gameId]
  );
}

// Distinct comedians with at least one KO to their name — the row count of
// the attacker list, i.e. how many pages the pager spans.
async function beefAttackerSize(gameId) {
  const row = await get(
    "SELECT COUNT(DISTINCT attacker_name) AS n FROM beatdowns WHERE game_id = ? AND attacker_name <> ''",
    [gameId]
  );
  return Number(row ? row.n : 0);
}

// One comedian's grudge list: who they have KO'd the most, worst beef first.
// This is the only place attacker_name is compared to a caller-supplied name,
// and it arrives as a bound parameter that server.js already roster-checked.
async function beefVictims(gameId, attacker, limit) {
  return all(
    `SELECT character_name, SUM(count) AS kos
       FROM beatdowns
      WHERE game_id = ? AND attacker_name = ?
      GROUP BY character_name
      ORDER BY kos DESC, character_name ASC
      LIMIT ${Number(limit)}`,
    [gameId, attacker]
  );
}

// Both sides of one comedian's ledger: KOs they have DEALT (as the comedian a
// run was played as) and KOs they have TAKEN (as an NPC someone else flattened).
// Two scalar subqueries rather than two round trips; MySQL 5.5-safe, since a
// SELECT of bare scalar subqueries needs no FROM.
async function beefTotals(gameId, name) {
  const row = await get(
    `SELECT
       (SELECT COALESCE(SUM(count), 0) FROM beatdowns
         WHERE game_id = ? AND attacker_name  = ?) AS dealt,
       (SELECT COALESCE(SUM(count), 0) FROM beatdowns
         WHERE game_id = ? AND character_name = ?) AS taken`,
    [gameId, name, gameId, name]
  );
  return { dealt: Number(row.dealt), taken: Number(row.taken) };
}

// ONE-TIME backfill: stamp each legacy beatdown with the comedian its run was
// played as, matched on (player_uuid, game_id, created_at) — the columns the
// same /play request wrote together. Exact in production, where the 60s play
// cooldown spaces each player's runs far enough apart that a KO can only
// belong to one run. A beatdown with no same-second play keeps '' and simply
// never feeds the beef board. Idempotent: only attacker_name = '' is touched,
// so a repeated or half-finished run cannot disturb captured rows.
//
// The UPDATE is a correlated subquery that runs on both drivers: the target
// table is not in the subquery's own FROM, so MySQL's error 1093 doesn't apply.
async function backfillBeef() {
  const sql = `
    UPDATE beatdowns
       SET attacker_name = COALESCE((
             SELECT p.character_name
               FROM plays p
              WHERE p.player_uuid = beatdowns.player_uuid
                AND p.game_id     = beatdowns.game_id
                AND p.created_at  = beatdowns.created_at
              LIMIT 1
           ), attacker_name)
     WHERE attacker_name = ''`;
  if (DRIVER === "sqlite") sqlite.exec(sql);
  else await pool.query(sql);

  const total = Number((await get("SELECT COUNT(*) AS n FROM beatdowns")).n);
  const remaining = Number(
    (await get("SELECT COUNT(*) AS n FROM beatdowns WHERE attacker_name = ''")).n
  );
  return { total, filled: total - remaining, remaining };
}

// ---------------------------------------------------------------- daily trends
// Per-day counts over the last 30 days for a FIXED set of names — the all-time
// top 5 the caller already picked (mostPlayedTop / beatPage / venuePage), so
// the trend lines track the same comedians/venues the podiums above show. One
// row per (name, day) that had activity; days with none are simply absent and
// the client fills 0. The IN list is the only bound value — its names came
// from this module's own top-N queries, never from the request — so building
// the placeholders by count is safe (same trust model as the inlined LIMIT).
//
// Kept as three explicit functions (not one table-name-parameterized helper)
// to match the rest of this file: the value expression genuinely differs
// (plays counts rows; beatdowns/venue_visits SUM a per-run count), and an
// interpolated table name is exactly the kind of thing worth not having.
function placeholders(names) {
  return names.map(() => "?").join(",");
}

async function dailyPlays(gameId, names) {
  if (!names.length) return [];
  return all(
    `SELECT character_name AS name, ${DAY[DRIVER]} AS day, COUNT(*) AS value
       FROM plays
      WHERE game_id = ? AND character_name IN (${placeholders(names)})
        AND created_at >= ${SINCE[DRIVER].month}
      GROUP BY character_name, ${DAY[DRIVER]}`,
    [gameId, ...names]
  );
}

async function dailyBeatdowns(gameId, names) {
  if (!names.length) return [];
  return all(
    `SELECT character_name AS name, ${DAY[DRIVER]} AS day, SUM(count) AS value
       FROM beatdowns
      WHERE game_id = ? AND character_name IN (${placeholders(names)})
        AND created_at >= ${SINCE[DRIVER].month}
      GROUP BY character_name, ${DAY[DRIVER]}`,
    [gameId, ...names]
  );
}

async function dailyVenueVisits(gameId, names) {
  if (!names.length) return [];
  return all(
    `SELECT venue_name AS name, ${DAY[DRIVER]} AS day, SUM(count) AS value
       FROM venue_visits
      WHERE game_id = ? AND venue_name IN (${placeholders(names)})
        AND created_at >= ${SINCE[DRIVER].month}
      GROUP BY venue_name, ${DAY[DRIVER]}`,
    [gameId, ...names]
  );
}

// ---------------------------------------------------------------- crashes
// The columns, in one place, so the INSERT and its parameter list can't drift
// apart silently.
const CRASH_COLUMNS = [
  "game_id", "player_uuid", "reason", "scene", "nav_type",
  "uptime_sec", "heap_bytes", "mem_static", "tex_bytes",
  "nodes", "objects", "orphans", "resources",
  "fps", "venues", "boots", "hidden_count",
  "dpr", "screen_w", "screen_h", "cores",
  "user_agent", "events",
];

async function recordCrash(row) {
  await run(
    `INSERT INTO crashes (${CRASH_COLUMNS.join(", ")})
     VALUES (${CRASH_COLUMNS.map(() => "?").join(", ")})`,
    CRASH_COLUMNS.map((c) => row[c])
  );
}

// Keep this table's size bounded from both ends: nothing older than
// retentionDays, and never more than maxRows in total. The row cap is the one
// that actually guarantees a ceiling — a bad week can't outrun it.
//
// The derived-table wrapper around the LIMIT subquery is not decoration:
// MySQL 5.5 refuses a subquery that reads the same table a DELETE is writing
// unless it goes through a temporary table like this. With fewer than maxRows
// rows the subquery is NULL and `id < NULL` matches nothing, which is exactly
// the no-op we want.
async function pruneCrashes({ retentionDays, maxRows }) {
  if (retentionDays > 0) {
    await run(`DELETE FROM crashes WHERE ${OLDER_THAN_DAYS[DRIVER](retentionDays)}`);
  }
  if (maxRows > 0) {
    await run(
      `DELETE FROM crashes WHERE id < (
         SELECT cut FROM (
           SELECT id AS cut FROM crashes ORDER BY id DESC LIMIT 1 OFFSET ${Number(maxRows) - 1}
         ) keep
       )`
    );
  }
}

// Headline counts for the admin page: how many crashes are on file, and how
// many arrived in the last 7 days (i.e. is this still happening?).
async function crashTotals() {
  const row = await get(
    `SELECT COUNT(*) AS total,
            SUM(CASE WHEN ${AGE_SEC[DRIVER]} < 604800 THEN 1 ELSE 0 END) AS week
       FROM crashes`
  );
  return {
    total: Number(row ? row.total : 0),
    week: Number(row && row.week ? row.week : 0),
  };
}

async function recentCrashes(limit) {
  return all(
    `SELECT * FROM crashes ORDER BY id DESC LIMIT ${Number(limit)}`
  );
}

module.exports = {
  init,
  recordCrash,
  pruneCrashes,
  crashTotals,
  recentCrashes,
  createPlayer,
  playerExists,
  recordLogin,
  loginDays,
  jokeCrafterState,
  weaponUpgrades,
  recordComponentDrop,
  recordCraft,
  recordUpgrade,
  secondsSinceLastPlay,
  recordPlay,
  recordBeatdowns,
  recordVenueVisits,
  recordVenueFights,
  venueFightTotals,
  recordSponsorImpressions,
  sponsorReport,
  weaponReport,
  boardPage,
  boardSize,
  mostPlayedTop,
  beatPage,
  beatSize,
  beefAttackerPage,
  beefAttackerSize,
  beefVictims,
  beefTotals,
  backfillBeef,
  venuePage,
  venueSize,
  playVolume,
  ecosystemTotals,
  dailyPlays,
  dailyBeatdowns,
  dailyVenueVisits,
};
