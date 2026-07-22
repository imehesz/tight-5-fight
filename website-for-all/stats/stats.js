/* TIGHT 5 FIGHT! — per-game stats page engine.
 *
 * Each stats/<game>/index.html sets window.T5F_STATS = { gameId, label }
 * and loads this file. It fetches the public /podium API (top 3 most
 * played, most beat up, top venues) and renders three podiums.
 *
 * The little comedians are the real thing: the game's generic M/F body
 * sheets (copied to ../assets/ by helper-tools/sync_stats_assets.sh) with
 * the baked skin color palette-swapped to each character's SkinColor on a
 * canvas, and the comedian's head PNG socketed at the neck — the same
 * numbers as scripts/character_factory.gd + dancer.gd, so a change there
 * should be mirrored here.
 *
 * NOTE: everything is fetch()ed, so test through a local web server
 */
(function () {
  "use strict";

  var CFG = window.T5F_STATS || { gameId: "", label: "?" };

  // ---- constants mirrored from character_factory.gd / dancer.gd ----------
  var FRAME_W = 32, FRAME_H = 48;
  var SHEET = { idle: { row: 0, frames: 2 }, walk: { row: 1, frames: 4 }, hit: { row: 5, frames: 1 } };
  var NECK = { idle: [0, -39], walk: [0, -39], hit: [-2, -38] };
  var HEAD_SCALE = 2.4, HEAD_BASE_PX = 16;
  var SKIN = [233, 192, 152]; // #e9c098 baked into the sheets
  // wheelchair overlay (characters with "inWheelchair"): legs erased below
  // the per-body cut line, chair drawn behind, normalized 51px wide
  var WHEELIE_BASE_PX = 51, WHEELIE_POS = [-2, -21];
  var LEG_CUT = { M: 28, F: 31 };
  var WALK_FRAME_MS = 1000 / 8;
  var STEP_MIN_MS = 400, STEP_MAX_MS = 900;

  // canvas geometry, in game pixels (scaled up S times, drawn pixelated)
  var S = 3;
  var CANVAS_W = 44, CANVAS_H = 82, FEET_X = 22, FEET_Y = 78;

  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Same host logic as the game's leaderboard.gd and admin.html: on the
  // real domain go through Apache's /tight5fight/api proxy; anywhere else
  // talk to a local dev server directly.
  function apiBase() {
    var h = location.hostname;
    if (h.endsWith("imstandup.com")) {
      return location.protocol + "//games.imstandup.com/tight5fight/api";
    }
    if (h && h !== "localhost" && h !== "127.0.0.1") return "http://" + h + ":8770";
    return "http://127.0.0.1:8770";
  }

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
  }

  function fmt(n) { return Number(n || 0).toLocaleString("en-US"); }

  function loadImage(src) {
    return new Promise(function (resolve) {
      var img = new Image();
      img.onload = function () { resolve(img); };
      img.onerror = function () { resolve(null); }; // a lost PNG costs a head, not the page
      img.src = src;
    });
  }

  // ---- body recoloring ----------------------------------------------------
  // Palette-swap the baked skin pixels to the character's SkinColor, once
  // per (body, skin) pair. Tolerant compare like the game's, because PNG
  // quantization can shift a channel by a hair.
  var sheetCache = {}; // "M|#hex[|w]" -> canvas
  var bodyImgs = {};   // "M"/"F" -> Image
  var wheelImgs = [];  // [wheelie_1, wheelie_2] once loaded

  function tintedSheet(bodyType, skinHex, chaired) {
    var body = bodyType === "F" ? "F" : "M";
    var key = body + "|" + skinHex + (chaired ? "|w" : "");
    if (sheetCache[key]) return sheetCache[key];
    var img = bodyImgs[body];
    var c = document.createElement("canvas");
    c.width = img.width; c.height = img.height;
    var ctx = c.getContext("2d");
    ctx.drawImage(img, 0, 0);
    var m = /^#?([0-9a-f]{6})$/i.exec(skinHex || "");
    if (m) {
      var r = parseInt(m[1].slice(0, 2), 16),
          g = parseInt(m[1].slice(2, 4), 16),
          b = parseInt(m[1].slice(4, 6), 16);
      if (!(r === SKIN[0] && g === SKIN[1] && b === SKIN[2])) {
        var data = ctx.getImageData(0, 0, c.width, c.height);
        var px = data.data;
        for (var i = 0; i < px.length; i += 4) {
          if (px[i + 3] > 0 &&
              Math.abs(px[i] - SKIN[0]) < 6 &&
              Math.abs(px[i + 1] - SKIN[1]) < 6 &&
              Math.abs(px[i + 2] - SKIN[2]) < 6) {
            px[i] = r; px[i + 1] = g; px[i + 2] = b;
          }
        }
        ctx.putImageData(data, 0, 0);
      }
    }
    if (chaired) {
      // Erase legs below the cut line (the chair fills the space), like
      // character_factory.gd _erase_legs — every pose we draw uses the
      // same straight cut, so one clearRect per row does it.
      var cut = LEG_CUT[body];
      for (var pose in SHEET) {
        ctx.clearRect(0, SHEET[pose].row * FRAME_H + cut, c.width, FRAME_H - cut);
      }
    }
    sheetCache[key] = c;
    return c;
  }

  // ---- dancers -------------------------------------------------------------
  var dancers = [];

  function makeDancer(charCfg, headImg) {
    var canvas = el("canvas", "dancer");
    canvas.width = CANVAS_W * S;
    canvas.height = CANVAS_H * S;
    var ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;

    // only chair a character when both chair frames actually loaded —
    // otherwise a legless torso would float (mirror of the game's
    // wheelie_textures() returning [] on a missing file)
    var chaired = !!charCfg.inWheelchair && !!(wheelImgs[0] && wheelImgs[1]);
    var d = {
      ctx: ctx,
      sheet: tintedSheet(charCfg.BodyType, charCfg.SkinColor, chaired),
      chaired: chaired,
      head: headImg,
      headScale: Math.max(Number(charCfg.HeadScale) || 1, 0.1),
      headDX: Number(charCfg.HeadOffsetX) || 0,
      headDY: Number(charCfg.HeadOffsetY) || 0,
      pose: "walk",
      flip: false,
      frame: 0,
      stepDue: 0,
      frameAt: 0,
    };
    draw(d);
    dancers.push(d);
    return canvas;
  }

  function draw(d) {
    var ctx = d.ctx;
    ctx.clearRect(0, 0, CANVAS_W * S, CANVAS_H * S);
    var anim = SHEET[d.pose];
    var f = d.pose === "walk" ? d.frame % anim.frames : 0;
    if (d.chaired) {
      // chair behind the body; second frame alternates in while walking
      var wi = wheelImgs[d.pose === "walk" ? f % 2 : 0];
      var ww = WHEELIE_BASE_PX;
      var wh = wi.height * (ww / wi.width);
      ctx.drawImage(wi,
        (FEET_X + WHEELIE_POS[0] - ww / 2) * S,
        (FEET_Y + WHEELIE_POS[1] - wh / 2) * S, ww * S, wh * S);
    }
    ctx.drawImage(d.sheet,
      f * FRAME_W, anim.row * FRAME_H, FRAME_W, FRAME_H,
      (FEET_X - FRAME_W / 2) * S, (FEET_Y - FRAME_H) * S, FRAME_W * S, FRAME_H * S);

    if (!d.head) return;
    // Head normalized to HEAD_BASE_PX wide at scale 1, centered above the
    // neck anchor and lifted by half its own height (minus the 4px chin
    // overlap), exactly like dancer.gd.
    var w = HEAD_SCALE * d.headScale * HEAD_BASE_PX;
    var h = d.head.height * (w / d.head.width);
    var neck = NECK[d.pose];
    var cx = FEET_X + neck[0] + d.headDX;
    var cy = FEET_Y + neck[1] - (h / 2 - 4) + d.headDY;
    ctx.save();
    ctx.translate(cx * S, cy * S);
    if (d.flip) ctx.scale(-1, 1);
    ctx.drawImage(d.head, -w / 2 * S, -h / 2 * S, w * S, h * S);
    ctx.restore();
  }

  function danceLoop(now) {
    for (var i = 0; i < dancers.length; i++) {
      var d = dancers[i], dirty = false;
      if (now >= d.stepDue) {
        d.pose = Math.random() < 0.5 ? "walk" : "hit";
        d.flip = Math.random() < 0.5;
        d.stepDue = now + STEP_MIN_MS + Math.random() * (STEP_MAX_MS - STEP_MIN_MS);
        d.frameAt = now;
        dirty = true;
      }
      if (d.pose === "walk" && now - d.frameAt >= WALK_FRAME_MS) {
        d.frame++;
        d.frameAt = now;
        dirty = true;
      }
      if (dirty) draw(d);
    }
    requestAnimationFrame(danceLoop);
  }

  // ---- page ----------------------------------------------------------------
  function header() {
    var back = el("a", "back", "◀ ALL CITIES");
    back.href = "../../";
    document.body.appendChild(back);
    var head = el("header");
    head.appendChild(el("h1", null, CFG.label + " STATS"));
    head.appendChild(el("p", "pitch", "WHO GOT PLAYED. WHO GOT PASTED. WHERE IT ALL WENT DOWN."));
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

  function board(title, sub) {
    var box = el("section", "board");
    box.appendChild(el("h2", null, title));
    box.appendChild(el("p", "sub", sub));
    document.body.appendChild(box);
    return box;
  }

  // rows arrive ranked 1..3; slots go in DOM order 2-1-3 so the winner
  // stands center and tallest (rank classes carry the step heights).
  function podium(box, rows, slotFill) {
    if (!rows.length) {
      box.appendChild(el("p", "empty", "NO DATA YET — THE STAGE IS YOURS"));
      return;
    }
    var pod = el("div", "podium");
    var order = [2, 1, 3];
    for (var i = 0; i < order.length; i++) {
      var rank = order[i];
      if (rank > rows.length) continue;
      var slot = el("div", "slot rank" + rank);
      slotFill(slot, rows[rank - 1]);
      var step = el("div", "step", String(rank));
      slot.appendChild(step);
      pod.appendChild(slot);
    }
    box.appendChild(pod);
  }

  function nameplate(name, stat, substat) {
    var who = el("p", "who", name);
    who.appendChild(el("span", "stat", stat));
    if (substat) who.appendChild(el("span", "substat", substat));
    return who;
  }

  function characterSlot(byName, headDir) {
    return function (slot, row, stat, substat) {
      var cfg = byName[row.character] || { BodyType: "M", SkinColor: "", HeadScale: 1 };
      var headFile = cfg.HeadSpritePath ? cfg.HeadSpritePath.split("/").pop() : null;
      var canvasHolder = el("div");
      slot.appendChild(canvasHolder);
      slot.appendChild(nameplate(row.character, stat, substat));
      var p = headFile ? loadImage(headDir + headFile) : Promise.resolve(null);
      p.then(function (head) {
        // no body sheet (../assets/ not synced) -> nameplate-only slot
        if (bodyImgs.M) canvasHolder.appendChild(makeDancer(cfg, head));
      });
    };
  }

  function main() {
    header();

    Promise.all([
      fetch("characters/characters.json").then(function (r) { return r.json(); }),
      fetch("venues/venues.json").then(function (r) { return r.json(); }),
      fetch(apiBase() + "/podium?gameId=" + encodeURIComponent(CFG.gameId))
        .then(function (r) { if (!r.ok) throw new Error("api " + r.status); return r.json(); }),
      loadImage("../assets/body_male.png"),
      loadImage("../assets/body_female.png"),
      loadImage("../assets/wheelie_1.png"),
      loadImage("../assets/wheelie_2.png"),
    ]).then(function (got) {
      var chars = (got[0].characters || []);
      var venues = (got[1].venues || []);
      var data = got[2];
      bodyImgs.M = got[3];
      bodyImgs.F = got[4] || got[3];
      wheelImgs = [got[5], got[6]];

      var byName = {};
      chars.forEach(function (c) { byName[c.CharacterName] = c; });
      var venueByName = {};
      venues.forEach(function (v) { venueByName[v.VenueName] = v; });

      var fillChar = characterSlot(byName, "characters/");

      podium(
        board("MOST PLAYED", "THE CROWD'S PICKS · TOTAL POINTS THEY'VE BANKED"),
        data.topPlayed || [],
        function (slot, row) {
          // Runs count hidden for now — may bring it back later:
          // fillChar(slot, row, fmt(row.score) + " PTS",
          //   fmt(row.plays) + (row.plays === 1 ? " RUN" : " RUNS"));
          fillChar(slot, row, fmt(row.score) + " PTS");
        });

      podium(
        board("MOST BEAT UP", "THE SCENE'S PUNCHING BAGS · KOs SUFFERED"),
        data.topBeat || [],
        function (slot, row) {
          fillChar(slot, row, fmt(row.kos) + (row.kos === 1 ? " KO" : " KOs"));
        });

      podium(
        board("TOP VENUES", "WHERE THE FIGHTS GO DOWN · DOORS WALKED THROUGH"),
        data.topVenues || [],
        function (slot, row) {
          var v = venueByName[row.venue];
          if (v && v.ExteriorSpritePath) {
            var img = new Image();
            img.className = "venue-pic";
            img.alt = row.venue;
            img.src = "venues/" + v.ExteriorSpritePath.split("/").pop();
            slot.appendChild(img);
          }
          slot.appendChild(nameplate(row.venue,
            fmt(row.entries) + (row.entries === 1 ? " ENTRY" : " ENTRIES")));
        });

      footer();
      if (!reduceMotion) requestAnimationFrame(danceLoop);
    }).catch(function (e) {
      var box = board("STATS", "");
      box.appendChild(el("p", "empty",
        "COULDN'T REACH THE SCOREKEEPER — TRY AGAIN IN A MINUTE"));
      footer();
      if (window.console) console.error(e);
    });
  }

  main();
})();
