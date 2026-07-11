# Tight 5 FIGHT! — Landing Website Requirements

## Why this exists

Shared links (mostly Facebook) point at the bare domain
`https://games.imstandup.com/`, whose DocumentRoot
(`/var/www/imstandup.com/games/` on the VPS) has no `index.html` — visitors
get a **403** and bounce. Day-one logs showed real people hitting that wall.

This page turns the bare domain into the front door: one screen that lists
every Tight 5 FIGHT! theme and sends the player into the one they pick.

## Scope (deliberately small)

- **ONE static HTML file** (`index.html`). All CSS and any JS inline in the
  file. No build step, no framework, no npm, nothing to install.
- No backend, no analytics, no cookies, no forms.
- Images are OPTIONAL (see Theme cards below) — v1 must look good with pure
  CSS/text cards so nothing blocks shipping.

## Where it lives

- **Repo:** create `landing/index.html` inside `src/open-mic-night/`.
- **Prod:** the file is copied to `/var/www/imstandup.com/games/index.html`
  on the VPS, sitting NEXT TO the existing `tight5fight/` build folders —
  it must not touch or rename anything already deployed.
- **IMPORTANT — deployment is manual by the owner.** Do NOT ssh/rsync to the
  VPS (172.245.91.173) from a Claude session, not even read-only. Deliver
  the file plus a one-line `scp`/`rsync` command the owner runs himself.

## Content

### Header
- Title: **TIGHT 5 FIGHT!**
- One-line pitch, something like: *"A comedian beat-'em-up. Pick your city,
  pick your comic, survive the hecklers."*

### Theme cards (the core of the page)

One card per live theme, each linking to its play URL:

| Theme | URL |
|---|---|
| JAX Edition (Jacksonville comedians) | `https://games.imstandup.com/tight5fight/jax/` |
| Celebs Edition (celebrity comedians) | `https://games.imstandup.com/tight5fight/celebs/` |

- The theme list will GROW (other cities are being added). Structure the
  page so adding a theme is trivial — either a small JS array rendered at
  load, or a clearly-commented copy-paste HTML block. Optimize for "owner
  adds a card in 60 seconds with a text editor".
- Each card: theme name, one-line description, a big **PLAY** affordance.
  The ENTIRE card should be tappable, not just a small link.
- Optional per-card image slot (e.g. `assets/jax.png` next to index.html):
  if the image file is missing the card must still render correctly
  (CSS-only fallback, no broken-image icon).

### Footer
- "Buy me a coffee" link: `https://buymeacoffee.com/imehesz` (opens new tab).
- Small copyright / "made in Jacksonville" line — owner's call.

## Look & feel

- Match the game's aesthetic: dark night-street background, **Press Start
  2P** typeface (load via Google Fonts with `font-display: swap`; fall back
  to any monospace — the page must be readable if the font fails), neon
  accents. The game currently uses hot pink/purple neon (ENTER signs,
  FIGHT! button) and gold highlights — reuse that family.
- Subtle motion is welcome (e.g. a gentle neon flicker or bobbing arrow à
  la the in-game ENTER sign) but must be pure CSS and respect
  `prefers-reduced-motion`.
- No layout shift while loading; the page is one screen of content.

## Mobile requirements (primary audience is phones)

- `<meta name="viewport" content="width=device-width, initial-scale=1">`.
- Cards stack vertically on narrow screens, side-by-side on wide ones
  (simple flexbox/grid, no media-query gymnastics needed beyond that).
- Touch targets generously sized: cards at least ~64px tall, nothing
  smaller than ~45px tap height anywhere.
- Test mentally against small phones (360px wide) AND desktop; no
  horizontal scrolling ever.

## Link-share behavior (the Facebook fix)

- Proper `<title>` and meta description.
- Open Graph tags so shares render a decent card:
  `og:title`, `og:description`, `og:url`, and `og:image` **only if** an
  image is actually deployed alongside the page (a broken og:image is worse
  than none).

## Non-goals (v1)

- No leaderboard display, no news feed, no theme screenshots carousel.
- No server-side anything. No redirects — the page IS the destination.
- Don't touch the Apache vhost; if it serves `index.html` by default this
  works as-is (DirectoryIndex is standard).

## Acceptance checklist

- [ ] Single `index.html`, self-contained (only external request allowed:
      Google Fonts, with graceful fallback).
- [ ] Both current themes listed and linking to the correct URLs above.
- [ ] Adding a third theme is a documented, trivial edit.
- [ ] Whole card tappable; comfortable on a 360px-wide phone.
- [ ] Looks like Tight 5 FIGHT! (dark + neon + pixel font), not a generic
      template.
- [ ] Valid HTML, no console errors, no broken images when optional assets
      are absent.
- [ ] Owner-run deploy command documented in a comment at the top of the
      HTML file itself.
