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
      created_at     TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE INDEX IF NOT EXISTS idx_board ON plays (game_id, character_name)`,
    `CREATE INDEX IF NOT EXISTS idx_uuid  ON plays (player_uuid, id)`,
    `CREATE TABLE IF NOT EXISTS beatdowns (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      game_id        TEXT NOT NULL,
      character_name TEXT NOT NULL,
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
      created_at     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY idx_board (game_id, character_name),
      KEY idx_uuid (player_uuid, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    `CREATE TABLE IF NOT EXISTS beatdowns (
      id             INT         NOT NULL AUTO_INCREMENT,
      game_id        VARCHAR(32) NOT NULL,
      character_name VARCHAR(64) NOT NULL,
      player_uuid    CHAR(36)    NOT NULL,
      count          INT         NOT NULL,
      created_at     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY idx_beat_board (game_id, character_name),
      KEY idx_beat_uuid (player_uuid, id)
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
  ],
};

// Age of a row in seconds. The one place the dialects genuinely differ.
const AGE_SEC = {
  sqlite: "(strftime('%s','now') - strftime('%s', created_at))",
  mysql: "TIMESTAMPDIFF(SECOND, created_at, NOW())",
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

async function recordPlay({ gameId, characterName, playerUuid }) {
  await run(
    "INSERT INTO plays (game_id, character_name, player_uuid) VALUES (?, ?, ?)",
    [gameId, characterName, playerUuid]
  );
}

// ---------------------------------------------------------------- beatdowns
// Who this run's player knocked out, one row per beaten character (with a
// count, since one run KOs the same comedian many times). Same shape as
// plays for the same reason: attributable to a player_uuid, so a cheater's
// rows can be deleted and the SUMs below simply heal.
async function recordBeatdowns({ gameId, playerUuid, counts }) {
  for (const [name, count] of Object.entries(counts)) {
    await run(
      "INSERT INTO beatdowns (game_id, character_name, player_uuid, count) VALUES (?, ?, ?, ?)",
      [gameId, name, playerUuid, count]
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

// ---------------------------------------------------------------- board
// One page of the character-popularity board, most-played first. Ties break
// on name so paging is stable (an unstable sort can drop or repeat a row
// across pages). Rank is not in the SQL — MySQL 5.5 has no window
// functions — so server.js derives it from the offset.
async function boardPage(gameId, offset, limit) {
  return all(
    `SELECT character_name, COUNT(*) AS plays
       FROM plays
      WHERE game_id = ?
      GROUP BY character_name
      ORDER BY plays DESC, character_name ASC
      LIMIT ${Number(limit)} OFFSET ${Number(offset)}`,
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

module.exports = {
  init,
  createPlayer,
  playerExists,
  secondsSinceLastPlay,
  recordPlay,
  recordBeatdowns,
  recordVenueVisits,
  boardPage,
  boardSize,
  beatPage,
  beatSize,
  venuePage,
  venueSize,
};
