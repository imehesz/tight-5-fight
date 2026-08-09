"use strict";
// ONE-TIME: run after deploying the attacker_name change to stamp LEGACY
// beatdown rows with the comedian their run was played as, so the BEEF board
// isn't empty on day one. Never called automatically — a whole-table UPDATE
// has no business running on every boot — and safe to re-run (it only touches
// attacker_name = '' rows).
//
//   Dev:  node backfill_beef.js          (stop the API server first: two
//                                         writers on one SQLite file lock)
//   Prod: NODE_ENV=production node backfill_beef.js   (run on the server,
//                                         easiest right after pm2 restart)
const db = require("./db");

(async () => {
  await db.init();
  const r = await db.backfillBeef();
  console.log(
    `beef backfill: ${r.filled} of ${r.total} rows stamped, ${r.remaining} unmatched (kept '').`
  );
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
