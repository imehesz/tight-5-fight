/* TIGHT 5 FIGHT! — per-game MORE INFO page engine.
 *
 * Each info/<game>/index.html sets
 *     window.T5F_INFO = { gameId, folder, label }
 * and loads this file. Three tabs: FIGHTERS (default), VENUES, SPONSORS.
 *
 * DATA — nothing new is copied for these pages. The rosters and their art
 * are already synced next door for the stats pages by
 * helper-tools/sync_stats_assets.sh, so we read them from there:
 *     ../../stats/<folder>/characters/{characters.json,*.png}
 *     ../../stats/<folder>/venues/{venues.json,*.png}
 * Sponsors come from the same hosted roster the game and the in-game
 * SPONSORS screen use: ../../sponsors/sponsors.json.
 *
 * PLAY sends the player straight into this edition with that comedian
 * preselected via ?fighter=<CharacterId> — the same deep link the game's
 * SHARE button hands out (see GameState._read_url_flags). A build that
 * predates the deep link just ignores the parameter and starts normally.
 *
 * Tapping a comedian's NAME opens their trading card (assets/card_male.jpg
 * or card_female.jpg by BodyType, drawn once with Higgsfield). The card
 * photo is the real in-game fighter via fighter-sprite.js, and an optional
 * "bio" string on the character renders as Markdown via md.js:
 *
 *     { "CharacterId": "d-man", ..., "bio": "**D-Man** started at..." }
 *
 * Add that key in games/<gameId>/characters.json (the source of truth) and
 * re-run helper-tools/sync_stats_assets.sh — no bio, no bio panel.
 *
 * NOTE: everything is fetch()ed, so test through a local web server.
 */
(function () {
  "use strict";

  var CFG = window.T5F_INFO || { gameId: "", folder: "", label: "?" };
  var ASSETS = "../../stats/" + CFG.folder + "/";
  var GAME_URL = "../../" + CFG.folder + "/";
  var SPONSORS_DIR = "../../sponsors/";

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
  }

  function fileOf(path) { return path ? String(path).split("/").pop() : ""; }

  function pad2(n) { return (n < 10 ? "0" : "") + n; }

  // UTC YYYY-MM-DD, matching Sponsors._runs_today's clock in the game.
  function todayUTC() {
    var d = new Date();
    return d.getUTCFullYear() + "-" + pad2(d.getUTCMonth() + 1) + "-" + pad2(d.getUTCDate());
  }

  // ---- page chrome ---------------------------------------------------------
  function header() {
    var back = el("a", "back", "◀ ALL CITIES");
    back.href = "../../";
    document.body.appendChild(back);
    var head = el("header");
    head.appendChild(el("h1", null, CFG.label + " INFO"));
    head.appendChild(el("p", "pitch", "WHO YOU CAN PLAY. WHERE YOU'LL FIGHT. WHO'S PICKING UP THE TAB."));
    document.body.appendChild(head);
  }

  function footer() {
    var f = el("footer");
    f.appendChild(document.createTextNode("PARODY — NOT AFFILIATED WITH OR ENDORSED BY ANYONE DEPICTED"));
    f.appendChild(document.createElement("br"));
    f.appendChild(document.createTextNode("MADE IN JACKSONVILLE, FL · © 2026 · "));
    var a = el("a", null, "LEGAL");
    a.href = "../../legal.html";
    f.appendChild(a);
    document.body.appendChild(f);
  }

  // ---- tabs ----------------------------------------------------------------
  // One <button> per tab over one <section class="board"> per panel. The
  // chosen tab is mirrored into the URL hash so a tab can be linked to
  // (/info/jax/#venues) and survives a reload.
  var TABS = [
    { id: "fighters", label: "FIGHTERS", sub: "EVERY COMEDIAN ON THE CARD · TAP PLAY TO TAKE ONE OUT" },
    { id: "venues", label: "VENUES", sub: "THE ROOMS YOU HAVE TO SURVIVE" },
    { id: "sponsors", label: "SPONSORS", sub: "THEY KEEP THE MICS ON · TAP ONE TO VISIT" },
  ];

  var panels = {}, buttons = {};

  function buildTabs() {
    var bar = el("nav", "tabs");
    bar.setAttribute("role", "tablist");
    document.body.appendChild(bar);

    TABS.forEach(function (t) {
      var b = el("button", "tab", t.label);
      b.type = "button";
      b.id = "tab-" + t.id;
      b.setAttribute("role", "tab");
      b.setAttribute("aria-selected", "false");
      b.setAttribute("aria-controls", "panel-" + t.id);
      b.addEventListener("click", function () { select(t.id, true); });
      bar.appendChild(b);
      buttons[t.id] = b;

      var box = el("section", "board");
      box.id = "panel-" + t.id;
      box.setAttribute("role", "tabpanel");
      box.setAttribute("aria-labelledby", "tab-" + t.id);
      box.hidden = true;
      box.appendChild(el("h2", null, t.label));
      box.appendChild(el("p", "sub", t.sub));
      box.appendChild(el("p", "empty", "LOADING…"));
      document.body.appendChild(box);
      panels[t.id] = box;
    });
  }

  function select(id, pushHash) {
    if (!panels[id] || buttons[id].disabled) return;
    TABS.forEach(function (t) {
      var on = t.id === id;
      buttons[t.id].setAttribute("aria-selected", on ? "true" : "false");
      panels[t.id].hidden = !on;
    });
    if (pushHash) history.replaceState(null, "", "#" + id);
  }

  // Replace a panel's body (everything under the h2 + sub) with rows, or an
  // empty-state line when there is nothing to show.
  function fill(id, nodes, emptyText) {
    var box = panels[id];
    while (box.children.length > 2) box.removeChild(box.lastChild);
    if (!nodes.length) {
      box.appendChild(el("p", "empty", emptyText));
      return;
    }
    var grid = el("div", "grid " + id);
    nodes.forEach(function (n) { grid.appendChild(n); });
    box.appendChild(grid);
  }

  // `eager` opts an image OUT of lazy loading. It matters for anything sitting
  // in a panel that is `hidden` (display:none) until its tab is opened: a lazy
  // image in a display:none subtree is the one case browsers genuinely
  // disagree about, and Safari can leave it unloaded forever — which, with the
  // onerror below, shows up as a tile with a caption and no art.
  function picture(cls, src, alt, eager) {
    var img = new Image();
    img.className = cls;
    img.alt = alt || "";
    if (!eager) img.loading = "lazy";
    img.src = src;
    // A missing PNG shouldn't leave a broken-image icon in the grid.
    img.onerror = function () { img.style.visibility = "hidden"; };
    return img;
  }

  // Shared A→Z comparator (roster order in the JSON is hand-maintained, so
  // every list on this page sorts for itself).
  function byName(key) {
    return function (a, b) {
      return String(a[key]).localeCompare(String(b[key]), "en",
        { numeric: true, sensitivity: "base" });
    };
  }

  // ---- panels --------------------------------------------------------------
  // Index letter a name files under: leading punctuation ignored, and
  // anything that isn't A-Z (904 Nika, DJ names) lands in "#".
  function indexLetter(name) {
    var ch = String(name).replace(/^[^0-9a-z]+/i, "").charAt(0).toUpperCase();
    return /[A-Z]/.test(ch) ? ch : "#";
  }

  function fighterTile(c) {
    var t = el("div", "tile");
    t.appendChild(picture("face", ASSETS + "characters/" + fileOf(c.HeadSpritePath), c.CharacterName));
    // The name is the door to the trading card.
    var nameBtn = el("button", "name name-btn", c.CharacterName);
    nameBtn.type = "button";
    nameBtn.title = "See " + c.CharacterName + "'s card";
    nameBtn.addEventListener("click", function () { openCard(c, nameBtn); });
    t.appendChild(nameBtn);
    var play = el("a", "play-btn", "▶ PLAY");
    play.href = GAME_URL + "?fighter=" + encodeURIComponent(c.CharacterId || "");
    t.appendChild(play);
    return t;
  }

  function renderFighters(chars) {
    // Benched comedians (`"isDisabled": true`) are not pickable in the game,
    // so they are not listed here either — same rule as GameState.playable.
    var live = chars.filter(function (c) { return !c.isDisabled; });
    // Sorted here rather than trusting characters.json order (which is roster
    // order, hand-maintained), then broken into A / B / C bands. The heading
    // rows are full-width members of the same grid, so the tile columns stay
    // aligned straight down the page.
    live.sort(byName("CharacterName"));
    var nodes = [], letters = [], band = null;
    live.forEach(function (c) {
      var letter = indexLetter(c.CharacterName);
      if (letter !== band) {
        band = letter;
        letters.push(letter);
        var h = el("h3", "letter", letter);
        h.id = letterId(letter);
        nodes.push(h);
      }
      nodes.push(fighterTile(c));
    });
    fill("fighters", nodes, "NO COMEDIANS ON THE CARD YET");
    // Jump bar goes between the sub line and the grid (fill() only ever
    // rebuilds from child 2 on, so it has to be inserted after the fill).
    if (letters.length) {
      var box = panels.fighters;
      box.insertBefore(jumpBar(letters), box.children[2]);
    }
    return live.length;
  }

  // "#" can't be an id fragment; everything else is a plain letter.
  function letterId(letter) { return "letter-" + (letter === "#" ? "0" : letter); }

  // Plain anchors: they work with the back button, and they still work if the
  // rest of the page's JS never runs. Only letters that HAVE comedians appear.
  function jumpBar(letters) {
    var nav = el("nav", "jump");
    nav.setAttribute("aria-label", "Jump to a letter");
    letters.forEach(function (letter) {
      var a = el("a", null, letter);
      a.href = "#" + letterId(letter);
      nav.appendChild(a);
    });
    return nav;
  }

  function renderVenues(venues) {
    var tiles = venues.filter(function (v) { return !v.isDisabled; }).map(function (v) {
      var t = el("div", "tile");
      t.appendChild(picture("venue-shot", ASSETS + "venues/" + fileOf(v.ExteriorSpritePath), v.VenueName));
      t.appendChild(el("p", "name", v.VenueName));
      return t;
    });
    fill("venues", tiles, "NO VENUES YET");
  }

  // A real sponsor sold in THIS market. `isSample` is how the template row in
  // sponsors.json opts out of every list on this page — it is permanently
  // disabled, so without this it would turn up under PAST SPONSORS as if
  // "Example Sponsor" had once bought billboards here.
  function inThisMarket(s) {
    if (!s || s.isSample || !s.sponsorId || !s.imgLink) return false;
    return (s.inMarkets || []).some(function (m) { return m === CFG.gameId; });
  }

  // Mirror of autoload/sponsors.gd _runs_today: live, running today, and
  // sold in THIS market.
  function runsToday(s, today) {
    if (!inThisMarket(s) || s.isDisabled) return false;
    if (s.dateStart && today < s.dateStart) return false;
    if (s.dateEnd && today > s.dateEnd) return false;
    return true;
  }

  // Ran here once, isn't running now: benched (`isDisabled`) or the campaign
  // window closed. A sponsor whose window hasn't OPENED yet is booked, not
  // past — they belong on neither list until their dateStart comes around.
  function isPast(s, today) {
    if (!inThisMarket(s) || runsToday(s, today)) return false;
    return !(s.dateStart && today < s.dateStart);
  }

  // Ad on top, name as its caption. Live ads load EAGERLY: this panel is
  // hidden until the tab is opened, and a paying sponsor's art must never be
  // the thing a browser decides not to fetch (see picture()). The past grid
  // can run long, so it stays lazy. A sponsor with no link renders as a plain
  // tile rather than an anchor to nowhere.
  //
  // NOTE the class name and the image paths: neither may contain "ad",
  // "banner", "promo" or "sponsor" as a path segment or filename prefix, or
  // ad blockers eat the request (ERR_BLOCKED_BY_CLIENT) and cosmetic filters
  // hide the element. See website-for-all/sponsors/README.md.
  function sponsorTile(s, past) {
    var t = el(s.linkTo ? "a" : "div", "tile" + (past ? " past" : ""));
    if (s.linkTo) {
      t.href = s.linkTo;
      t.target = "_blank";
      t.rel = "noopener";
    }
    var img = picture("marquee-shot", SPONSORS_DIR + s.imgLink, s.sponsorName, !past);
    // Belt and braces for the blocker case above: an image that never arrives
    // leaves a framed placeholder carrying the name, not a nameless hole where
    // a paying sponsor's art should be.
    img.onerror = function () {
      if (img.parentNode) {
        img.parentNode.replaceChild(el("div", "marquee-shot no-art", s.sponsorName), img);
      }
    };
    t.appendChild(img);
    t.appendChild(el("p", "name", s.sponsorName));
    return t;
  }

  function sectionHead(box, title, sub) {
    box.appendChild(el("h3", "section-head", title));
    box.appendChild(el("p", "sub", sub));
  }

  // The same pitch the in-game SPONSORS screen makes with its ADVERTISE HERE
  // button (scenes/sponsors_menu.gd) — one mailto, no form to maintain.
  var ADVERTISE_MAILTO = "mailto:tight5contact@gmail.com?subject=" +
    encodeURIComponent("TIGHT 5 FIGHT sponsorship");

  function advertiseCTA() {
    var row = el("div", "cta-row");
    var a = el("a", "play-btn", "▶ ADVERTISE HERE");
    a.href = ADVERTISE_MAILTO;
    row.appendChild(a);
    return row;
  }

  function renderSponsors(roster) {
    var today = todayUTC();
    var all = roster || [];
    var live = all.filter(function (s) { return runsToday(s, today); });
    var past = all.filter(function (s) { return isPast(s, today); });
    if (!live.length && !past.length) {
      // This city has no sponsor history at all → the tab greys out. Anyone
      // who arrived on a #sponsors link gets dropped back on FIGHTERS before
      // it locks. A city with PAST sponsors keeps its tab: the empty billboard
      // and the names of who used to be on it are the pitch.
      if (buttons.sponsors.getAttribute("aria-selected") === "true") select("fighters", false);
      buttons.sponsors.disabled = true;
      fill("sponsors", [], "THIS SPACE IS FOR SALE");
      return;
    }
    live.sort(byName("sponsorName"));
    fill("sponsors", live.map(function (s) { return sponsorTile(s, false); }),
      "NOBODY ON THE BOARD TODAY — THIS SPACE IS FOR SALE");

    // fill() only ever rebuilds from child 2 on, so the NOW SHOWING heading is
    // inserted after it (same dance as the fighters' jump bar); everything
    // below the live grid is appended.
    var box = panels.sponsors;
    var head = el("h3", "section-head", "NOW SHOWING");
    box.insertBefore(head, box.children[2]);
    if (past.length) {
      past.sort(byName("sponsorName"));
      sectionHead(box, "PAST SPONSORS",
        "THEY BOUGHT THE ROOM A ROUND · THEIR BILLBOARD IS OPEN AGAIN");
      var grid = el("div", "grid sponsors past-grid");
      past.forEach(function (s) { grid.appendChild(sponsorTile(s, true)); });
      box.appendChild(grid);
    }
    box.appendChild(advertiseCTA());
  }

  // ---- trading card --------------------------------------------------------
  // One modal reused for every comedian: a baseball-card frame (the Higgsfield
  // art in assets/, male or female by BodyType) with the fighter standing in
  // the stage window, their name on the nameplate, and the Markdown bio in the
  // panel underneath. Every text slot is positioned in PERCENTAGES of the card
  // box, and the two art files don't have identical panel geometry — hence the
  // per-variant numbers in info.css (.card.male / .card.female).
  var modal = null, cardEls = null, lastFocus = null;

  function buildModal() {
    modal = el("div", "modal");
    modal.setAttribute("role", "dialog");
    modal.setAttribute("aria-modal", "true");
    modal.setAttribute("aria-label", "Comedian card");
    modal.hidden = true;

    var card = el("div", "card");
    // Deliberately overhangs the top-left corner, sticker-style.
    var logo = picture("card-logo", "../../imgs/t5f-logo_mid.png", "Tight 5 Fight");
    var banner = el("p", "card-banner", CFG.label + " EDITION");
    var stage = el("div", "card-stage");
    var fig = el("canvas", "card-fig");
    stage.appendChild(fig);
    var name = el("p", "card-name");
    var bio = el("div", "card-bio");
    card.appendChild(logo);
    card.appendChild(banner);
    card.appendChild(stage);
    card.appendChild(name);
    card.appendChild(bio);

    // Buttons ride BELOW the card so they never cover the art.
    var actions = el("div", "card-actions");
    var play = el("a", "play-btn", "▶ PLAY");
    var close = el("button", "close-btn", "✕ CLOSE");
    close.type = "button";
    close.addEventListener("click", closeCard);
    actions.appendChild(play);
    actions.appendChild(close);

    var shell = el("div", "modal-shell");
    shell.appendChild(card);
    shell.appendChild(actions);
    modal.appendChild(shell);
    // A click on the backdrop (never on the card itself) closes.
    modal.addEventListener("click", function (ev) { if (ev.target === modal) closeCard(); });
    document.body.appendChild(modal);

    cardEls = { card: card, fig: fig, name: name, bio: bio, play: play, close: close };
  }

  function openCard(c, opener) {
    if (!modal) buildModal();
    lastFocus = opener || null;

    cardEls.card.className = "card " + (c.BodyType === "F" ? "female" : "male");
    cardEls.name.textContent = c.CharacterName;
    cardEls.play.href = GAME_URL + "?fighter=" + encodeURIComponent(c.CharacterId || "");
    modal.setAttribute("aria-label", c.CharacterName + " — comedian card");

    if (c.bio) {
      cardEls.bio.innerHTML = window.T5F_MD(c.bio);
      cardEls.bio.classList.remove("no-bio");
    } else {
      cardEls.bio.textContent = "— NO BIO ON FILE —";
      cardEls.bio.classList.add("no-bio");
    }
    cardEls.bio.scrollTop = 0;

    // The card photo: the real fighter, bodies loaded once for the page. Any
    // missing art just leaves the stage empty rather than blocking the card.
    var fig = cardEls.fig;
    fig.style.visibility = "hidden";
    Promise.all([
      window.T5F_SPRITE.loadBodies("../../stats/assets/"),
      window.T5F_SPRITE.loadImage(ASSETS + "characters/" + fileOf(c.HeadSpritePath)),
    ]).then(function (got) {
      if (cardEls.name.textContent !== c.CharacterName) return; // card moved on
      if (got[0] && window.T5F_SPRITE.draw(fig, c, got[1])) fig.style.visibility = "";
    });

    modal.hidden = false;
    document.body.classList.add("modal-open");
    cardEls.close.focus();
  }

  function closeCard() {
    if (!modal || modal.hidden) return;
    modal.hidden = true;
    document.body.classList.remove("modal-open");
    if (lastFocus) lastFocus.focus();
  }

  document.addEventListener("keydown", function (ev) {
    if (ev.key === "Escape") closeCard();
  });

  // ---- boot ----------------------------------------------------------------
  function main() {
    header();
    buildTabs();
    // FIGHTERS is the default; a #hash from a shared link wins.
    var want = location.hash.replace("#", "");
    select(panels[want] ? want : "fighters", false);
    footer();

    // Rosters are per-tab and independent: one failed fetch only empties its
    // own panel.
    fetch(ASSETS + "characters/characters.json")
      .then(function (r) { return r.json(); })
      .then(function (d) { renderFighters(d.characters || []); })
      .catch(function () { fill("fighters", [], "COULDN'T LOAD THE ROSTER — TRY AGAIN IN A MINUTE"); });

    fetch(ASSETS + "venues/venues.json")
      .then(function (r) { return r.json(); })
      .then(function (d) { renderVenues(d.venues || []); })
      .catch(function () { fill("venues", [], "COULDN'T LOAD THE VENUES — TRY AGAIN IN A MINUTE"); });

    fetch(SPONSORS_DIR + "sponsors.json")
      .then(function (r) { return r.json(); })
      .then(function (d) { renderSponsors(d.sponsors || []); })
      .catch(function () { renderSponsors([]); });
  }

  main();
})();
