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

  function picture(cls, src, alt) {
    var img = new Image();
    img.className = cls;
    img.alt = alt || "";
    img.loading = "lazy";
    img.src = src;
    // A missing PNG shouldn't leave a broken-image icon in the grid.
    img.onerror = function () { img.style.visibility = "hidden"; };
    return img;
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
    live.sort(function (a, b) {
      return String(a.CharacterName).localeCompare(String(b.CharacterName), "en",
        { numeric: true, sensitivity: "base" });
    });
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

  // Mirror of autoload/sponsors.gd _runs_today: live, running today, and
  // sold in THIS market.
  function runsToday(s, today) {
    if (!s || s.isDisabled) return false;
    if (!s.sponsorId || !s.imgLink) return false;
    if (!(s.inMarkets || []).some(function (m) { return m === CFG.gameId; })) return false;
    if (s.dateStart && today < s.dateStart) return false;
    if (s.dateEnd && today > s.dateEnd) return false;
    return true;
  }

  function renderSponsors(roster) {
    var today = todayUTC();
    var live = (roster || []).filter(function (s) { return runsToday(s, today); });
    if (!live.length) {
      // Nothing to show → the tab greys out. Anyone who arrived on a
      // #sponsors link gets dropped back on FIGHTERS before it locks.
      if (buttons.sponsors.getAttribute("aria-selected") === "true") select("fighters", false);
      buttons.sponsors.disabled = true;
      fill("sponsors", [], "THIS SPACE IS FOR SALE");
      return;
    }
    var tiles = live.map(function (s) {
      var a = el("a", "tile");
      a.href = s.linkTo || "#";
      a.target = "_blank";
      a.rel = "noopener";
      a.appendChild(picture("ad-shot", SPONSORS_DIR + s.imgLink, s.sponsorName));
      a.appendChild(el("p", "name", s.sponsorName));
      return a;
    });
    fill("sponsors", tiles, "THIS SPACE IS FOR SALE");
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
