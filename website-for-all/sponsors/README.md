# Sponsors — hosted ad rotation

This folder deploys with the landing site (`./deployScriptPRODWEB.sh go`) to
`https://games.imstandup.com/tight5fight/sponsors/`. Every live game edition
fetches `sponsors.json` from there on street load, so **adding or changing a
sponsor never requires redeploying a game** — paste the image, edit the JSON,
rsync the website.

## ⚠️ Never put "ad", "sponsor", "banner" or "promo" in a FILE PATH

Ad blockers (uBlock Origin, AdBlock, Brave shields) match on URL patterns, and
`/ads/`, `sponsor_*`, `banner*` and `promo*` are all on the standard filter
lists. The artwork used to live at `sponsors/ads/sponsor_joes-pizza.png`, and
for every visitor running a blocker — call it a third of desktop traffic —
**every one of those requests was killed** (`ERR_BLOCKED_BY_CLIENT`):

- the website's SPONSORS tab showed names with no artwork;
- the in-game billboards silently got no texture, so `sponsors.gd` skipped
  those sponsors entirely — no billboard on the street, and **no impression
  counted**, which quietly under-reports what every sponsor is paying for.

So the images live in `marquee/` with plain business-name filenames, and the
website's CSS class is `marquee-shot`, never `ad-*` (cosmetic filters hide
elements by class name too). Keep it that way. If you ever need to check,
open the page with the blocker ON — a clean console is the only proof.

The folder name `sponsors/` itself is currently fine on the common lists, and
changing it would mean editing `PROD_SPONSORS_URL` in `autoload/sponsors.gd`
and rebuilding every edition. If it ever does start getting blocked: deploy
the renamed folder alongside the old one, ship the game change, then delete
the old folder once every edition is redeployed.

## Adding a sponsor

1. Drop the ad image into `marquee/`, named after the business
   (`joes-pizza.png` — no `sponsor_` prefix, see the warning above).
   **Artwork is always 640x460** (PNG or JPG); the in-game billboard scales
   that exact shape, anything else gets letterboxed.
2. Add an entry to `sponsors.json`:

```json
{
  "sponsorId": "joes-pizza",
  "sponsorName": "Joe's Pizza",
  "inMarkets": ["tight5", "daytona"],
  "dateStart": "2026-08-01",
  "dateEnd": "2026-08-31",
  "imgLink": "marquee/joes-pizza.png",
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
| `isSample` | `true` marks a row as a template, not a real customer. The only thing that reads it is the website's **PAST SPONSORS** list, which would otherwise advertise "Example Sponsor" as a former backer. Only the example row at the top of the file should carry it. |

How often billboards appear at all (regardless of sponsor count) is a game
constant, not a JSON field: `BILLBOARD_CHANCE` in `scenes/street.gd`.

## Where a sponsor shows up

| | In-game billboards + SPONSORS screen | Website `/info/<game>/#sponsors` |
|---|---|---|
| Running today, in this market | yes | **NOW SHOWING** |
| `isDisabled`, or `dateEnd` has passed | no | **PAST SPONSORS** (greyed, still linked) |
| `dateStart` hasn't arrived yet | no | nowhere — booked, not past |
| Not in `inMarkets` for that game | no | nowhere |

So **benching a sponsor doesn't erase them from the site** — they move down to
PAST SPONSORS, which is deliberate: an empty billboard next to the names of
everyone who used to be on it is the pitch to the next one. If a sponsor needs
to disappear completely (they asked, or the row was never a real customer),
give them `"isSample": true` or delete the entry.

## Impressions

Each billboard counts one impression when it actually scrolls into view, and
the tally ships to the backend when the run ends (rows in the
`sponsor_impressions` table, keyed by `sponsorId` + game). Reports: the
admin stats page (`admin.html?pwd=...`) shows per-sponsor totals for the last
30 days and all time.
