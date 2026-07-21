# Sponsors — hosted ad rotation

This folder deploys with the landing site (`./deployScriptPRODWEB.sh go`) to
`https://games.imstandup.com/tight5fight/sponsors/`. Every live game edition
fetches `sponsors.json` from there on street load, so **adding or changing a
sponsor never requires redeploying a game** — paste the image, edit the JSON,
rsync the website.

## Adding a sponsor

1. Drop the ad image into `ads/`. **Ads are always 640x460** (PNG or JPG);
   the in-game billboard scales that exact shape, anything else gets
   letterboxed.
2. Add an entry to `sponsors.json`:

```json
{
  "sponsorId": "joes-pizza",
  "sponsorName": "Joe's Pizza",
  "inMarkets": ["tight5", "daytona"],
  "dateStart": "2026-08-01",
  "dateEnd": "2026-08-31",
  "imgLink": "ads/joes-pizza.png",
  "linkTo": "https://joespizza.example",
  "weight": 20
}
```

3. `./deployScriptPRODWEB.sh go` from the project root.

## Field reference

| Field | Meaning |
|-------|---------|
| `sponsorId` | Stable slug (`a-z0-9-`), max 40 chars. **Never rename it mid-campaign** — it is the key impression reports aggregate by. |
| `sponsorName` | Display name on the in-game SPONSORS screen. |
| `inMarkets` | Real game ids the ad runs in: `tight5` (= JAX), `daytona`, `celebs`, `killers`. |
| `dateStart` / `dateEnd` | `YYYY-MM-DD`, inclusive, compared in UTC. Outside the window the sponsor simply doesn't load — no takedown deploy needed. |
| `imgLink` | Path relative to this folder (keep images in `ads/`). |
| `linkTo` | URL the SPONSORS screen opens on tap. |
| `weight` | Relative share of billboard slots among active sponsors (weight 30 vs 20 → 60%/40% of ads shown). Pricing tiers map here. |
| `isDisabled` | `true` benches the sponsor immediately, same as the character/venue flag. |

How often billboards appear at all (regardless of sponsor count) is a game
constant, not a JSON field: `BILLBOARD_CHANCE` in `scenes/street.gd`.

## Impressions

Each billboard counts one impression when it actually scrolls into view, and
the tally ships to the backend when the run ends (rows in the
`sponsor_impressions` table, keyed by `sponsorId` + game). Reports: the
admin stats page (`admin.html?pwd=...`) shows per-sponsor totals for the last
30 days and all time.
