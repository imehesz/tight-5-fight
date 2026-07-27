/* TIGHT 5 FIGHT! — the smallest Markdown renderer that covers a comedian bio.
 *
 * Deliberately hand-rolled instead of pulling in marked/showdown: the whole
 * site ships with zero JS dependencies, and a bio only ever needs paragraphs,
 * emphasis, links and lists. Exposes window.T5F_MD(src) -> HTML string.
 *
 * Supported: # h1 .. ### h3, **bold**, *italic* / _italic_, `code`,
 * [text](url), - / * bullet lists, 1. numbered lists, > blockquote,
 * --- rule, blank-line paragraphs; a single newline inside a paragraph is a
 * line break (GitHub-style), which is what people actually type.
 *
 * SAFETY: the source is escaped FIRST and every construct is built from the
 * escaped text, so a bio can never inject markup. Link targets are limited to
 * http(s)/mailto — anything else (javascript:, data:) renders as plain text.
 */
(function () {
  "use strict";

  function esc(s) {
    return String(s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function safeHref(url) {
    return /^(https?:\/\/|mailto:)/i.test(url) ? url : null;
  }

  // Everything that works INSIDE a line, applied to already-escaped text.
  // Code spans are parked FIRST (so `**not bold**` survives) behind NUL
  // sentinels — a placeholder ordinary prose can never collide with.
  var NUL = "\u0000";

  function inline(text) {
    var codes = [];
    text = text.replace(/`([^`]+)`/g, function (_, c) {
      return NUL + (codes.push(c) - 1) + NUL;
    });
    text = text
      .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, function (whole, label, url) {
        var href = safeHref(url);
        return href
          ? '<a href="' + href + '" target="_blank" rel="noopener">' + label + "</a>"
          : whole;
      })
      .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
      .replace(/(^|[^*])\*([^*]+)\*/g, "$1<i>$2</i>")
      .replace(/(^|\W)_([^_]+)_(?=\W|$)/g, "$1<i>$2</i>")
      .replace(/ +$/gm, ""); // trailing spaces are noise; every \n breaks anyway
    return text.replace(new RegExp(NUL + "(\\d+)" + NUL, "g"), function (_, i) {
      return "<code>" + codes[+i] + "</code>";
    });
  }

  function render(src) {
    if (!src) return "";
    var lines = esc(String(src)).replace(/\r\n?/g, "\n").split("\n");
    var out = [], list = null, para = [];

    function flushPara() {
      if (para.length) {
        out.push("<p>" + inline(para.join("\n")).replace(/\n/g, "<br>") + "</p>");
        para = [];
      }
    }
    function closeList() {
      if (list) { out.push("</" + list + ">"); list = null; }
    }
    function openList(tag) {
      if (list !== tag) { closeList(); out.push("<" + tag + ">"); list = tag; }
    }

    lines.forEach(function (line) {
      var m;
      if (!line.trim()) { flushPara(); closeList(); return; }
      if (/^\s*(---+|\*\*\*+)\s*$/.test(line)) {
        flushPara(); closeList(); out.push("<hr>"); return;
      }
      if ((m = /^\s*(#{1,3})\s+(.*)$/.exec(line))) {
        flushPara(); closeList();
        var h = m[1].length;
        out.push("<h" + h + ">" + inline(m[2]) + "</h" + h + ">");
        return;
      }
      // "&gt;", not ">": escaping already ran, so the marker arrives escaped.
      if ((m = /^\s*&gt;\s?(.*)$/.exec(line))) {
        flushPara(); closeList();
        out.push("<blockquote>" + inline(m[1]) + "</blockquote>");
        return;
      }
      if ((m = /^\s*[-*+]\s+(.*)$/.exec(line))) {
        flushPara(); openList("ul");
        out.push("<li>" + inline(m[1]) + "</li>");
        return;
      }
      if ((m = /^\s*\d+[.)]\s+(.*)$/.exec(line))) {
        flushPara(); openList("ol");
        out.push("<li>" + inline(m[1]) + "</li>");
        return;
      }
      closeList();
      para.push(line);
    });
    flushPara();
    closeList();
    return out.join("\n");
  }

  window.T5F_MD = render;
})();
