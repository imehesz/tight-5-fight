# Tight 5 FIGHT! — global leaderboard server

Small Node.js HTTP service behind Apache. It backs the **GLOBAL** tab on the
game's scoreboard: a popularity board counting how many times each character
has been played. The **LOCAL** tab never touches this server — it stays on the
device in `user://<game>_highscores.json`.

## Run locally

```sh
cd server
npm install
node server.js          # listens on :8770, SQLite in server/data/
```

The Godot client points at `http://127.0.0.1:8770` automatically when the page
isn't served from a production domain (see `autoload/leaderboard.gd`).

## Configuration

`config.js` (in source control, never holds credentials) defines the defaults
and merges in one gitignored override file based on `NODE_ENV`:

| NODE_ENV     | file           | database              | port |
| ------------ | -------------- | --------------------- | ---- |
| (unset)/dev  | config.dev.js  | SQLite file           | 8770 |
| `production` | config.prod.js | `tight5fight_db`      | 8770 |

Create `config.prod.js` by hand on the VPS with the real MySQL credentials.
The copy in this repo is a placeholder and is gitignored.

`config.js` also owns two things worth knowing about:

- **`games`** — the allowlist of game ids that may write to the board. Anything
  else is rejected before it reaches SQL.
- **`pageSize`** — rows per page. Must stay in step with `ROWS_PER_PAGE` in
  `scenes/scoreboard.gd` and `PAGE_SIZE` in `autoload/leaderboard.gd`.

## Endpoints

| Method | Path                             | Purpose                          |
| ------ | -------------------------------- | -------------------------------- |
| POST   | `/player`                        | Mint an anonymous player uuid    |
| POST   | `/play`                          | Bank one play (`{gameId, character, uuid, kos?}`) |
| GET    | `/leaderboard?gameId=&page=`     | One page of both boards          |
| GET    | `/health`                        | Liveness                         |

`/play` optionally carries `kos`, the run's KO tally (`{"Character Name":
count, …}`) — who this run beat up, feeding the MOST BEAT UP board. Counts
are capped per character per run; names the roster doesn't know are dropped,
never fatal (same mid-season-roster grace as plays). `/leaderboard` returns
the most-played board in `rows`/`total` and the most-beat-up board in
`beatRows`/`beatTotal`; `pageCount` spans whichever board is longer, so one
pager drives both panels in the game.

The game page (imstandup.com) and this server (games.mehesz.net) are always
different origins, so every response carries CORS headers. Nothing sensitive is
exposed: the endpoints mint an anonymous id and count plays.

## Abuse resistance, and its honest limits

There is no registration, and the board ranks *characters*, not players. Nobody's
name is on it, so the only prize for cheating is pushing a favourite comedian up
a popularity chart. The defences are sized for exactly that:

- **The server mints the uuid, the client never invents one.** A client that
  generates its own id can mint an unlimited supply of them; `/play` rejects any
  uuid that didn't come from `/player`.
- **Minting is capped per IP** (`limits.mintsPerHourPerIp`). This is what gives
  the previous point teeth: the obvious bypass — a fresh uuid per request — now
  costs the one identifier a client can't rotate for free.
- **Plays are capped per uuid** (`limits.playCooldownSec`, checked against the
  database, so a server restart doesn't hand anyone a fresh window) **and per
  IP** (`limits.playsPerHourPerIp`, in memory). Only requests that actually land
  are charged against the IP budget — a refused request inflates nothing, and
  charging for it would let a player who double-taps burn their own hour.
- **Character names are checked against the game's roster** (`rosters/*.json`),
  so the board can never fill with strings the game never shipped.
- **A play is recorded when a run ENDS**, not when FIGHT! is pressed, so
  fabricating one costs a real run's worth of time.

What this does *not* stop: a determined person on a phone hotspot, cycling IPs,
can still inflate a counter. That is an acceptable outcome for a counter. What
it does guarantee is that the data stays clean and attributable — see below.

**One row per play, never a bare counter.** `plays` stores a row per play with
its uuid and timestamp, so counts are re-derived with a `GROUP BY` and a bad
actor's rows can simply be deleted afterwards. A column that only goes up would
make abuse permanent and unattributable.

## Rosters

`rosters/<gameId>.json` is the list of character names each game may report. The
server is deployed without the game's asset tree, so it can't read
`games/<id>/characters.json` directly — these extracts are committed alongside
it. Regenerate after adding or renaming a comedian:

```sh
cd server && npm run sync-rosters
```

Forgetting is not fatal: an unlisted name is rejected by `/play`, and a game with
no roster file at all falls back to shape-only validation.

## Database

All SQL lives in `db.js`, which implements the same async API on two drivers
(picked by `db.driver` in config):

- **sqlite** (dev): built-in `node:sqlite` (Node 22+), zero setup, file at
  `server/data/tight5fight.db`. Schema created automatically.
- **mysql** (prod): `mysql2` pool. Tables are created on first start
  (`CREATE TABLE IF NOT EXISTS`), so the only manual step is the database and
  user, once:

  ```sql
  CREATE DATABASE tight5fight_db CHARACTER SET utf8mb4;
  CREATE USER 'tight5fight'@'localhost' IDENTIFIED BY '<strong password>';
  GRANT ALL PRIVILEGES ON tight5fight_db.* TO 'tight5fight'@'localhost';
  ```

Two tables: `players` (anonymous minted ids) and `plays` (one row per play).

### Why one table and not one per theme

Per-theme tables (`tight5-leaderboard_global`, …) would force the theme name
into the table name, which means dynamic SQL on every query, backticks
everywhere, and a fresh injection surface each time a game is added. Instead
`plays` carries a `game_id` column indexed as `(game_id, character_name)`. The
boards are just as separate, adding a game needs no DDL at all, and no
user-controlled string ever reaches the SQL text.

### MySQL 5.5 notes

The prod VPS runs MySQL 5.5, which is old enough to have real constraints (and
is past end-of-life — no security patches since 2018; worth a migration when
convenient). `db.js` is written to run on 5.5 and 8.x alike:

- 5.5 allows only **one** `TIMESTAMP` column per table with a
  `CURRENT_TIMESTAMP` default, so no table here has an `updated_at`.
- InnoDB's index limit on 5.5 is 767 bytes and `utf8mb4` is 4 bytes/char, so
  every indexed column stays well under 191 characters.
- 5.5 has **no window functions**: rank is computed in `server.js` from the page
  offset rather than with `RANK() OVER ()`. Ties therefore get distinct
  consecutive ranks, which is what the scoreboard shows anyway.
- `LIMIT`/`OFFSET` can't be bound parameters on 5.5, so `db.js` uses
  `pool.query` (client-side interpolation) and coerces both to `Number` itself.

## Production deploy (VPS, games.mehesz.net API hub)

The backend lives behind Apache on `games.mehesz.net` under the `/tight5fight/`
prefix. `autoload/leaderboard.gd` hardcodes that hub for any page served from
`*.mehesz.net` or `*.imstandup.com`.

1. Copy `server/` to the VPS — it is **not** part of the game's rsync deploy,
   which only ships `build/`. Then `npm install`, create `config.prod.js` there,
   and run under a process manager with `NODE_ENV=production`:

   ```sh
   pm2 start server.js --name tight5fight-lb --env production
   ```

   In production the process binds to `127.0.0.1`, so the node port is never
   reachable from the internet — Apache is the only public entrance.

2. Enable the proxy modules once:

   ```sh
   sudo a2enmod proxy proxy_http && sudo systemctl reload apache2
   ```

3. Add the proxy rules inside the `games.mehesz.net` VirtualHost:

   ```apache
   # Tight 5 FIGHT! leaderboard backend (node on 127.0.0.1:8770)
   ProxyPreserveHost On
   ProxyPass        "/tight5fight/api/" "http://127.0.0.1:8770/"
   ProxyPassReverse "/tight5fight/api/" "http://127.0.0.1:8770/"
   ```

   The trailing slash on the target strips the prefix, so the node server keeps
   its clean `/player`, `/play`, `/leaderboard` routes.

   Because Apache is the only way in, the node process sees `127.0.0.1` as every
   client's address. It therefore trusts `X-Forwarded-For` **only** from
   loopback — accepting that header from anywhere would let any caller spoof its
   IP and walk straight through the per-IP limits.

4. If the game page is served over https, the hub must be too (an https page may
   not call an http endpoint):

   ```sh
   sudo certbot --apache -d games.mehesz.net
   ```
