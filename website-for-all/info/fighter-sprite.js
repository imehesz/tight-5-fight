/* TIGHT 5 FIGHT! — draws one comedian (body + head) onto a canvas.
 *
 * Used by the trading-card popup on the MORE INFO pages: the card photo is
 * the actual in-game fighter, not just a head shot — the shared M/F body
 * sheet with the baked skin palette-swapped to the character's SkinColor,
 * their head socketed at the neck, and the wheelchair overlay when they ride
 * one.
 *
 * The numbers below mirror scripts/character_factory.gd + dancer.gd, same as
 * the copy inside stats/stats.js (which also animates them and is left
 * alone deliberately — the stats page is live, this file is additive). If
 * the game's sprite geometry ever changes, BOTH need the edit.
 *
 * Exposes:
 *   T5F_SPRITE.loadBodies(dir) -> Promise, once per page
 *   T5F_SPRITE.draw(canvas, charCfg, headImg)
 */
(function () {
  "use strict";

  var FRAME_W = 32, FRAME_H = 48;
  var IDLE_ROW = 0;                  // pose used for the card: standing still
  var NECK = [0, -39];
  var HEAD_SCALE = 2.4, HEAD_BASE_PX = 16;
  var SKIN = [233, 192, 152];        // #e9c098 baked into the sheets
  var WHEELIE_BASE_PX = 51, WHEELIE_POS = [-2, -21];
  var LEG_CUT = { M: 28, F: 31 };

  // canvas geometry in game pixels, scaled up S times and drawn pixelated
  var S = 4;
  var CANVAS_W = 44, CANVAS_H = 82, FEET_X = 22, FEET_Y = 78;

  var bodyImgs = {}, wheelImgs = [], sheetCache = {}, loading = null;

  function loadImage(src) {
    return new Promise(function (resolve) {
      var img = new Image();
      img.onload = function () { resolve(img); };
      img.onerror = function () { resolve(null); };
      img.src = src;
    });
  }

  // One load per page; every later call rides the same promise.
  function loadBodies(dir) {
    if (loading) return loading;
    loading = Promise.all([
      loadImage(dir + "body_male.png"),
      loadImage(dir + "body_female.png"),
      loadImage(dir + "wheelie_1.png"),
      loadImage(dir + "wheelie_2.png"),
    ]).then(function (got) {
      bodyImgs.M = got[0];
      bodyImgs.F = got[1] || got[0];
      wheelImgs = [got[2], got[3]];
      return !!bodyImgs.M;
    });
    return loading;
  }

  // Palette-swap the baked skin pixels to this character's SkinColor, cached
  // per (body, skin, chaired). Tolerant compare, like the game's: PNG
  // quantization can shift a channel by a hair.
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
      // Legs erased below the per-body cut line; the chair fills the space
      // (mirror of character_factory.gd _erase_legs).
      ctx.clearRect(0, IDLE_ROW * FRAME_H + LEG_CUT[body], c.width, FRAME_H - LEG_CUT[body]);
    }
    sheetCache[key] = c;
    return c;
  }

  function draw(canvas, cfg, headImg) {
    if (!bodyImgs.M) return false;
    canvas.width = CANVAS_W * S;
    canvas.height = CANVAS_H * S;
    var ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Only chair a character when both chair frames loaded, otherwise a
    // legless torso would float (mirror of wheelie_textures() returning []).
    var chaired = !!cfg.inWheelchair && !!(wheelImgs[0] && wheelImgs[1]);
    if (chaired) {
      var wi = wheelImgs[0];
      var ww = WHEELIE_BASE_PX, wh = wi.height * (ww / wi.width);
      ctx.drawImage(wi,
        (FEET_X + WHEELIE_POS[0] - ww / 2) * S,
        (FEET_Y + WHEELIE_POS[1] - wh / 2) * S, ww * S, wh * S);
    }

    ctx.drawImage(tintedSheet(cfg.BodyType, cfg.SkinColor, chaired),
      0, IDLE_ROW * FRAME_H, FRAME_W, FRAME_H,
      (FEET_X - FRAME_W / 2) * S, (FEET_Y - FRAME_H) * S, FRAME_W * S, FRAME_H * S);

    if (!headImg) return true;
    // Head normalized to HEAD_BASE_PX wide at scale 1, centered above the
    // neck anchor and lifted by half its own height (minus the 4px chin
    // overlap) — exactly like dancer.gd.
    var w = HEAD_SCALE * (Math.max(Number(cfg.HeadScale) || 1, 0.1)) * HEAD_BASE_PX;
    var h = headImg.height * (w / headImg.width);
    var cx = FEET_X + NECK[0] + (Number(cfg.HeadOffsetX) || 0);
    var cy = FEET_Y + NECK[1] - (h / 2 - 4) + (Number(cfg.HeadOffsetY) || 0);
    ctx.drawImage(headImg, (cx - w / 2) * S, (cy - h / 2) * S, w * S, h * S);
    return true;
  }

  window.T5F_SPRITE = { loadBodies: loadBodies, draw: draw, loadImage: loadImage };
})();
