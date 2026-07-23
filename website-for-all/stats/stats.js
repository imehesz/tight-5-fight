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

  // ---- trend charts (last 30 days) ----------------------------------------
  // Three SVG line charts under the podiums: the top-5 comedians/venues (same
  // ranking the podium shows) each get a daily line over the last 30 days,
  // coloured by ENTITY (rank order), with a tiny head/venue picture pinned to
  // the tip of the line. Palette is the data-viz skill's dark categorical set,
  // validated against this page's --panel surface for a 5-series line.
  var SVGNS = "http://www.w3.org/2000/svg";
  var SERIES_COLORS = ["#3987e5", "#d95926", "#199e70", "#c98500", "#d55181"];
  var clipSeq = 0;

  function svgEl(tag, attrs) {
    var n = document.createElementNS(SVGNS, tag);
    for (var k in attrs) n.setAttribute(k, attrs[k]);
    return n;
  }

  function pad2(n) { return (n < 10 ? "0" : "") + n; }
  function isoDay(d) { return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()); }

  // The 30 calendar days ending today, as 'YYYY-MM-DD' — the fixed X axis
  // every line is plotted onto (days with no activity read 0).
  function lastNDays(n) {
    var out = [], base = new Date();
    base.setHours(0, 0, 0, 0);
    for (var i = n - 1; i >= 0; i--) {
      var d = new Date(base);
      d.setDate(base.getDate() - i);
      out.push(isoDay(d));
    }
    return out;
  }

  function shortDay(iso) { var p = iso.split("-"); return (+p[1]) + "/" + (+p[2]); }

  // A round step so gridlines land on 1/2/5·10ⁿ, ~4 of them.
  function niceStep(maxV) {
    var raw = Math.max(maxV, 1) / 4;
    var p = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10));
    var n = raw / p;
    return Math.max(1, (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p);
  }

  // { names, rows:[{name,day,value}] } from /trends -> one series per name in
  // RANK order, each with a value for every axis day and its picture src.
  function buildSeries(block, axis, srcOf) {
    var names = (block && block.names) || [];
    var byName = {};
    names.forEach(function (nm) { byName[nm] = {}; });
    ((block && block.rows) || []).forEach(function (r) {
      if (byName[r.name]) byName[r.name][r.day] = r.value;
    });
    return names.map(function (nm, i) {
      return {
        name: nm,
        color: SERIES_COLORS[i % SERIES_COLORS.length],
        values: axis.map(function (day) { return byName[nm][day] || 0; }),
        src: srcOf(nm),
      };
    });
  }

  // Tip of a line = its most recent day with any activity (where the picture
  // sits). -1 when the series is flat-zero across the window.
  function lastActiveIndex(values) {
    for (var i = values.length - 1; i >= 0; i--) if (values[i] > 0) return i;
    return -1;
  }

  function trendChart(box, series, axis, unit) {
    var hasData = series.some(function (s) { return lastActiveIndex(s.values) >= 0; });
    if (!hasData) {
      box.appendChild(el("p", "empty", "NO DATA YET — THE STAGE IS YOURS"));
      return;
    }

    var W = 640, H = 260, padL = 40, padR = 34, padT = 16, padB = 34;
    var plotW = W - padL - padR, plotH = H - padT - padB;

    var maxV = 1;
    series.forEach(function (s) { s.values.forEach(function (v) { if (v > maxV) maxV = v; }); });
    var step = niceStep(maxV);
    var niceMax = Math.ceil(maxV / step) * step;

    function X(i) { return padL + (axis.length <= 1 ? 0 : (i / (axis.length - 1)) * plotW); }
    function Y(v) { return padT + plotH - (v / niceMax) * plotH; }

    var wrap = el("div", "chart-wrap");
    var svg = svgEl("svg", {
      class: "chart", viewBox: "0 0 " + W + " " + H,
      role: "img", "aria-label": box.querySelector("h2").textContent + " — last 30 days",
    });

    // horizontal gridlines + Y labels
    for (var g = 0; g <= niceMax + 0.0001; g += step) {
      var gy = Y(g);
      svg.appendChild(svgEl("line", {
        class: "grid", x1: padL, y1: gy, x2: W - padR, y2: gy,
      }));
      var lbl = svgEl("text", { class: "axis-txt", x: padL - 6, y: gy + 3, "text-anchor": "end" });
      lbl.textContent = String(Math.round(g));
      svg.appendChild(lbl);
    }

    // X labels at a handful of days (first, quarters, TODAY)
    var ticks = [0, 7, 14, 21, axis.length - 1];
    ticks.forEach(function (i, k) {
      if (i >= axis.length) return;
      var tx = svgEl("text", {
        class: "axis-txt", x: X(i), y: H - padB + 16,
        "text-anchor": k === 0 ? "start" : k === ticks.length - 1 ? "end" : "middle",
      });
      tx.textContent = i === axis.length - 1 ? "TODAY" : shortDay(axis[i]);
      svg.appendChild(tx);
    });

    // one polyline per series, then its picture at the tip
    series.forEach(function (s) {
      var pts = s.values.map(function (v, i) { return X(i) + "," + Y(v); }).join(" ");
      svg.appendChild(svgEl("polyline", {
        points: pts, fill: "none", stroke: s.color,
        "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round",
        "vector-effect": "non-scaling-stroke", class: "series-line",
      }));
    });
    series.forEach(function (s) {
      var li = lastActiveIndex(s.values);
      if (li < 0) return;
      var cx = X(li), cy = Y(s.values[li]), R = 12;
      if (s.src) {
        var cid = "t5fclip" + (++clipSeq);
        var defs = svgEl("defs", {});
        var clip = svgEl("clipPath", { id: cid });
        clip.appendChild(svgEl("circle", { cx: cx, cy: cy, r: R }));
        defs.appendChild(clip);
        svg.appendChild(defs);
        var img = svgEl("image", {
          x: cx - R, y: cy - R, width: 2 * R, height: 2 * R,
          preserveAspectRatio: "xMidYMid slice", "clip-path": "url(#" + cid + ")",
        });
        img.setAttributeNS("http://www.w3.org/1999/xlink", "href", s.src);
        img.setAttribute("href", s.src);
        svg.appendChild(img);
      }
      svg.appendChild(svgEl("circle", {
        cx: cx, cy: cy, r: R, fill: s.src ? "none" : s.color,
        stroke: s.color, "stroke-width": 2, "vector-effect": "non-scaling-stroke",
        class: "face-ring",
      }));
    });

    // hover crosshair + tooltip
    var cross = svgEl("line", { class: "crosshair", y1: padT, y2: padT + plotH, x1: padL, x2: padL });
    cross.style.display = "none";
    svg.appendChild(cross);
    var hit = svgEl("rect", { x: padL, y: padT, width: plotW, height: plotH, fill: "transparent" });
    svg.appendChild(hit);

    var tip = el("div", "chart-tip");
    tip.style.display = "none";
    wrap.appendChild(svg);
    wrap.appendChild(tip);

    function move(ev) {
      var rect = svg.getBoundingClientRect();
      var vbx = (ev.clientX - rect.left) / rect.width * W;
      var idx = Math.round((vbx - padL) / plotW * (axis.length - 1));
      idx = Math.max(0, Math.min(axis.length - 1, idx));
      cross.setAttribute("x1", X(idx));
      cross.setAttribute("x2", X(idx));
      cross.style.display = "";
      tip.innerHTML = "";
      tip.appendChild(el("div", "tip-day", axis[idx] === axis[axis.length - 1] ? "TODAY" : shortDay(axis[idx])));
      series.forEach(function (s) {
        var row = el("div", "tip-row");
        row.appendChild(svgSwatchDot(s.color));
        row.appendChild(el("span", "tip-name", s.name));
        row.appendChild(el("span", "tip-val", fmt(s.values[idx]) + " " + unit));
        tip.appendChild(row);
      });
      tip.style.display = "";
      // keep the tooltip inside the wrap, flipping side near the right edge
      var wr = wrap.getBoundingClientRect();
      var left = ev.clientX - wr.left + 14;
      if (left + 150 > wr.width) left = ev.clientX - wr.left - 150 - 14;
      tip.style.left = Math.max(4, left) + "px";
      tip.style.top = Math.max(4, ev.clientY - wr.top - 10) + "px";
    }
    function leave() { cross.style.display = "none"; tip.style.display = "none"; }
    hit.addEventListener("pointermove", move);
    hit.addEventListener("pointerdown", move);
    hit.addEventListener("pointerleave", leave);

    box.appendChild(wrap);

    // legend (identity is never colour-alone: picture + name ride with it)
    var legend = el("div", "chart-legend");
    series.forEach(function (s) {
      var item = el("div", "chart-legend-item");
      var sw = el("span", "chart-swatch");
      sw.style.background = s.color;
      item.appendChild(sw);
      if (s.src) {
        var f = new Image();
        f.className = "chart-face";
        f.alt = "";
        f.src = s.src;
        f.style.borderColor = s.color;
        item.appendChild(f);
      }
      item.appendChild(el("span", "legend-name", s.name));
      legend.appendChild(item);
    });
    box.appendChild(legend);

    // accessible data table (identity + exact numbers without the chart)
    var det = el("details", "chart-data");
    det.appendChild(el("summary", null, "SEE THE NUMBERS"));
    var scroll = el("div", "table-scroll");
    var table = el("table");
    var thead = el("tr");
    thead.appendChild(el("th", null, "DAY"));
    series.forEach(function (s) { thead.appendChild(el("th", null, s.name)); });
    table.appendChild(thead);
    axis.forEach(function (day, i) {
      // only rows with some activity, newest first — keeps the table short
      if (!series.some(function (s) { return s.values[i] > 0; })) return;
      var tr = el("tr");
      tr.appendChild(el("td", null, shortDay(day)));
      series.forEach(function (s) { tr.appendChild(el("td", null, fmt(s.values[i]))); });
      table.insertBefore(tr, table.children[1] || null);
    });
    scroll.appendChild(table);
    det.appendChild(scroll);
    box.appendChild(det);
  }

  function svgSwatchDot(color) {
    var s = el("span", "tip-dot");
    s.style.background = color;
    return s;
  }

  function renderTrendCharts(trends, byName, venueByName) {
    var axis = lastNDays(30);
    function headSrc(nm) {
      var c = byName[nm];
      var f = c && c.HeadSpritePath ? c.HeadSpritePath.split("/").pop() : null;
      return f ? "characters/" + f : null;
    }
    function venueSrc(nm) {
      var v = venueByName[nm];
      var f = v && v.ExteriorSpritePath ? v.ExteriorSpritePath.split("/").pop() : null;
      return f ? "venues/" + f : null;
    }
    trendChart(
      board("MOST PLAYED — 30 DAYS", "DAILY RUNS PER COMEDIAN · TOP 5"),
      buildSeries(trends && trends.topPlayed, axis, headSrc), axis, "RUNS");
    trendChart(
      board("MOST BEAT UP — 30 DAYS", "DAILY KOs SUFFERED · TOP 5"),
      buildSeries(trends && trends.topBeat, axis, headSrc), axis, "KOs");
    trendChart(
      board("VENUES VISITED — 30 DAYS", "DAILY DOORS WALKED THROUGH · TOP 5"),
      buildSeries(trends && trends.topVenues, axis, venueSrc), axis, "ENTRIES");
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
      // Trends are a separate, non-fatal fetch: a failure here leaves the
      // podiums untouched and the charts show their own empty state.
      fetch(apiBase() + "/trends?gameId=" + encodeURIComponent(CFG.gameId))
        .then(function (r) { return r.ok ? r.json() : null; })
        .catch(function () { return null; }),
    ]).then(function (got) {
      var chars = (got[0].characters || []);
      var venues = (got[1].venues || []);
      var data = got[2];
      bodyImgs.M = got[3];
      bodyImgs.F = got[4] || got[3];
      wheelImgs = [got[5], got[6]];
      var trends = got[7];

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
          // Fights = KOs landed inside the venue. Hidden while 0: the tally
          // only exists on new-client runs, so early boards would otherwise
          // read "0 FIGHTS" across the podium.
          slot.appendChild(nameplate(row.venue,
            fmt(row.entries) + (row.entries === 1 ? " ENTRY" : " ENTRIES"),
            row.fights ? fmt(row.fights) + (row.fights === 1 ? " FIGHT" : " FIGHTS") : null));
        });

      renderTrendCharts(trends, byName, venueByName);

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
