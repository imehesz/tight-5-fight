#!/usr/bin/env python3
"""Auto-populate a game's characters.json from its head PNGs.

Scans <game>/assets/heads/*.png, treats each filename as a comedian's name,
looks the person up on Wikipedia/Wikidata (free, no API key), and figures out:

  * BodyType  -> "M" / "F"   (Wikidata sex-or-gender, P21)
  * SkinColor -> light / dark bucket (Wikipedia race/ethnicity categories)

then merges the results into <game>/characters.json (keeping any existing
entries and their HeadScale / HeadOffsetY).

Filenames are usually concatenated ("davechappelle.png"), so we brute-force a
two-way first/last split and keep the candidate whose Wikipedia title most
closely matches the filename AND is a real person (Wikidata "instance of
human"). Misspelled or obscure names ("burtkreischer" -> Bert Kreischer,
"jerreysignfeld" -> Jerry Seinfeld) can't be resolved automatically; those are
reported as UNRESOLVED and can be fixed via a per-game head_overrides.json.

Only requires the `requests` library. Results are cached in
helper-tools/.cache/classify_cache.json so re-runs are instant and network-free.

Usage:
    python3 helper-tools/classify_heads.py --game celebs
    python3 helper-tools/classify_heads.py --game celebs --dry-run
    python3 helper-tools/classify_heads.py --heads path/to/heads --out path/to/characters.json

Overrides (games/<game>/head_overrides.json), any subset of fields per file:
    {
      "burtkreischer": {"name": "Bert Kreischer", "gender": "M", "skin": "light"},
      "jerreysignfeld": {"query": "Jerry Seinfeld"},
      "kylekanine":     {"name": "Kyle Kanine", "gender": "M", "skin": "light"}
    }
  - "query": force the Wikipedia search string (fixes misspellings), still auto-detect.
  - "name"/"gender"/"skin": hard-code a field, skipping lookup for it.
"""
import argparse
import difflib
import json
import os
import re
import sys
import time

try:
    import requests
except ImportError:
    sys.exit("This tool needs the 'requests' library:  pip install requests")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
CACHE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache", "classify_cache.json")

# Skin swatches (match the existing hand-authored characters.json entries).
SKIN_LIGHT = "#e9c098"
SKIN_DARK = "#a0683c"

# Head PNGs that are template placeholders, not comedians.
DEFAULT_SKIP = {"hero1", "hero2"}

# Wikipedia category keywords that indicate a darker skin bucket. Tonality is
# intentionally coarse (two buckets), so this errs toward broad African-descent
# signals and otherwise defaults to the light swatch.
DARK_CATEGORY_KEYWORDS = (
    "African-American", "African American", "African-Canadian", "African-British",
    "Black British", "Black Canadian", "of African descent", "of Nigerian descent",
    "of Ghanaian descent", "of Jamaican descent", "of Kenyan descent",
    "of Somali descent", "of Ethiopian descent", "Nigerian", "Ghanaian", "Jamaican",
    "Xhosa", "Zulu", "Somali", "Kenyan descent",
)

WIKI_API = "https://en.wikipedia.org/w/api.php"
WD_API = "https://www.wikidata.org/w/api.php"

session = requests.Session()
session.headers["User-Agent"] = "open-mic-night/classify_heads (imehesz@gmail.com)"


def _norm(s):
    return re.sub(r"[^a-z]", "", s.lower())


def _get(url, params):
    for attempt in range(3):
        try:
            r = session.get(url, params=params, timeout=20)
            r.raise_for_status()
            return r.json()
        except Exception:
            time.sleep(0.5 * (attempt + 1))
    return {}


# ----------------------------------------------------------------- Wikidata
def wd_claims(qid):
    """Return {'P31': [...ids], 'P21': [...ids], 'P172': [...ids]} for an entity."""
    d = _get(WD_API, {"action": "wbgetentities", "ids": qid,
                      "props": "claims", "format": "json"})
    cl = d.get("entities", {}).get(qid, {}).get("claims", {})

    def ids(p):
        out = []
        for c in cl.get(p, []):
            dv = c["mainsnak"].get("datavalue")
            if dv and isinstance(dv["value"], dict) and "id" in dv["value"]:
                out.append(dv["value"]["id"])
        return out

    return {"P31": ids("P31"), "P21": ids("P21"), "P172": ids("P172")}


def wiki_search(query, limit=3):
    """Return [(title, qid), ...] for a Wikipedia full-text search."""
    d = _get(WIKI_API, {"action": "query", "generator": "search",
                        "gsrsearch": query, "gsrlimit": limit,
                        "prop": "pageprops", "format": "json"})
    pages = d.get("query", {}).get("pages", {})
    out = []
    for p in pages.values():
        out.append((p.get("index", 99), p["title"],
                    p.get("pageprops", {}).get("wikibase_item")))
    out.sort()
    return [(t, q) for _, t, q in out]


def wiki_race_categories(title):
    """Return the matched dark-bucket category titles for a page (may be empty)."""
    d = _get(WIKI_API, {"action": "query", "prop": "categories",
                        "titles": title, "cllimit": 500, "format": "json"})
    pages = d.get("query", {}).get("pages", {})
    if not pages:
        return []
    cats = [c["title"] for c in next(iter(pages.values())).get("categories", [])]
    return [c for c in cats if any(k in c for k in DARK_CATEGORY_KEYWORDS)]


# ---------------------------------------------------------------- resolving
def _split_points(name):
    """Split positions to try, common first-name lengths (3-7) first."""
    pts = list(range(2, len(name) - 1))
    pts.sort(key=lambda i: (0 if 3 <= i <= 7 else 1, abs(i - 5)))
    return pts


def resolve_name(name, query=None):
    """Look a comedian up. Returns dict(title, gender, skin, ratio) or None.

    `query` forces the search string (used by overrides to fix misspellings);
    otherwise brute-force two-way splits of the concatenated filename are tried.
    """
    candidates = {}   # title -> qid
    best = None       # (ratio, title, qid)

    def consider(results):
        nonlocal best
        for title, qid in results:
            if not qid or title in candidates:
                continue
            candidates[title] = qid
            ratio = difflib.SequenceMatcher(None, _norm(title), name).ratio()
            if best is None or ratio > best[0]:
                best = (ratio, title, qid)

    if query:
        consider(wiki_search(query))
    else:
        for i in _split_points(name):
            consider(wiki_search(name[:i] + " " + name[i:]))
            time.sleep(0.05)
            # Early accept once we have a near-exact, confirmed-human match.
            if best and best[0] >= 0.9 and _finalize(best) is not None:
                break

    if best is None:
        return None
    ranked = sorted(candidates.items(),
                    key=lambda kv: difflib.SequenceMatcher(None, _norm(kv[0]), name).ratio(),
                    reverse=True)
    for title, qid in ranked[:3]:
        result = _finalize((difflib.SequenceMatcher(None, _norm(title), name).ratio(), title, qid))
        if result:
            return result
    return None


def _finalize(cand, min_ratio=0.6):
    """Given (ratio, title, qid), confirm human & return dict or None."""
    ratio, title, qid = cand
    if ratio < min_ratio:
        return None
    claims = wd_claims(qid)
    if "Q5" not in claims["P31"]:
        return None
    gender = "F" if "Q6581072" in claims["P21"] else "M"
    dark = bool(wiki_race_categories(title))
    # Drop disambiguators like " (comedian)" / " (actor)" from the display name.
    display = re.sub(r"\s*\([^)]*\)\s*$", "", title).strip()
    return {"title": display, "gender": gender,
            "skin": "dark" if dark else "light", "ratio": round(ratio, 2)}


# -------------------------------------------------------------------- cache
def load_json(path, default):
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return default


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


# --------------------------------------------------------------------- main
def prettify_filename(stem):
    """Fallback display name from a filename when lookup fails."""
    return re.sub(r"[_-]+", " ", stem).title()


def build_entry(head_file, name, gender, skin, existing):
    """Assemble one characters.json entry, preserving existing tweaks."""
    prev = existing.get("assets/heads/" + head_file, {})
    return {
        "CharacterName": name,
        "HeadScale": prev.get("HeadScale", 1),
        "HeadOffsetY": prev.get("HeadOffsetY", 0),
        "HeadSpritePath": "assets/heads/" + head_file,
        "BodyType": gender,
        "SkinColor": SKIN_DARK if skin == "dark" else SKIN_LIGHT,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", help="game folder name under games/ (e.g. celebs)")
    ap.add_argument("--heads", help="explicit heads dir (overrides --game)")
    ap.add_argument("--out", help="explicit characters.json path (overrides --game)")
    ap.add_argument("--overrides", help="overrides json (default games/<game>/head_overrides.json)")
    ap.add_argument("--skip", default=",".join(sorted(DEFAULT_SKIP)),
                    help="comma-separated filename stems to ignore")
    ap.add_argument("--force", action="store_true", help="re-resolve heads already in characters.json")
    ap.add_argument("--no-cache", action="store_true", help="ignore the resolution cache")
    ap.add_argument("--dry-run", action="store_true", help="print results, don't write characters.json")
    args = ap.parse_args()

    if args.heads and args.out:
        heads_dir, out_path = args.heads, args.out
    elif args.game:
        base = os.path.join(ROOT, "games", args.game)
        heads_dir = os.path.join(base, "assets", "heads")
        out_path = os.path.join(base, "characters.json")
    else:
        ap.error("provide --game, or both --heads and --out")

    overrides_path = args.overrides
    if not overrides_path and args.game:
        overrides_path = os.path.join(ROOT, "games", args.game, "head_overrides.json")
    overrides = load_json(overrides_path, {}) if overrides_path else {}

    skip = {s for s in args.skip.split(",") if s}
    cache = {} if args.no_cache else load_json(CACHE_PATH, {})

    if not os.path.isdir(heads_dir):
        sys.exit("heads dir not found: " + heads_dir)

    existing_doc = load_json(out_path, {"characters": []})
    existing_by_path = {c["HeadSpritePath"]: c for c in existing_doc.get("characters", [])}

    png_stems = sorted({os.path.splitext(f)[0] for f in os.listdir(heads_dir)
                        if f.lower().endswith(".png")})

    entries, unresolved, rows = [], [], []
    for stem in png_stems:
        head_file = stem + ".png"
        sprite = "assets/heads/" + head_file
        if stem in skip:
            continue
        if sprite in existing_by_path and not args.force:
            entries.append(existing_by_path[sprite])
            rows.append((head_file, existing_by_path[sprite]["CharacterName"], "kept", "-", "-"))
            continue

        ov = overrides.get(stem, {})
        name = ov.get("name")
        gender = ov.get("gender")
        skin = ov.get("skin")
        source = "override" if ov else "auto"

        # If the filename already separates the words ("dave-chappelle",
        # "dave_chappelle", "dave chappelle") use them directly — no guessing.
        query = ov.get("query")
        if not query and re.search(r"[ _-]", stem):
            query = " ".join(w for w in re.split(r"[ _\-]+", stem) if w)

        # Fill any missing field via lookup (cached).
        if name is None or gender is None or skin is None:
            key = query or stem
            res = cache.get(key) if not args.no_cache else None
            if res is None:
                res = resolve_name(stem, query=query)
                if res:  # only cache hits — a transient miss must not stick forever
                    cache[key] = res
            if res:
                name = name or res["title"]
                gender = gender or res["gender"]
                skin = skin or res["skin"]
                source = source if ov else "wiki"

        if not gender or not skin:
            # Couldn't determine the essentials; report and skip (unless override named it).
            if name:
                # Have a name but not attributes -> default and flag.
                entry = build_entry(head_file, name, gender or "M", skin or "light", existing_by_path)
                entries.append(entry)
                rows.append((head_file, name, source + "*", entry["BodyType"], entry["SkinColor"]))
                unresolved.append((stem, "attributes defaulted (add gender/skin to overrides)"))
            else:
                unresolved.append((stem, "no Wikipedia match (add to head_overrides.json)"))
            continue

        if not name:
            name = prettify_filename(stem)
        entry = build_entry(head_file, name, gender, skin, existing_by_path)
        entries.append(entry)
        rows.append((head_file, name, source, entry["BodyType"], entry["SkinColor"]))

    # ---- report
    w = max((len(r[0]) for r in rows), default=10)
    print(f"\nHeads dir: {heads_dir}")
    print(f"{'FILE':<{w}}  {'CHARACTER':<24} {'SRC':<9} {'BODY':<4} SKIN")
    for f, n, s, b, sk in rows:
        print(f"{f:<{w}}  {n:<24} {s:<9} {b:<4} {sk}")

    if unresolved:
        print("\nUNRESOLVED (" + str(len(unresolved)) + ") — add these to " +
              (overrides_path or "a --overrides file") + ":")
        for stem, why in unresolved:
            print(f"  {stem:<22} {why}")

    if not args.no_cache:
        save_json(CACHE_PATH, cache)

    if args.dry_run:
        print("\n[dry-run] characters.json not written.")
        return

    save_json(out_path, {"characters": entries})
    print(f"\nWrote {len(entries)} characters -> {out_path}")


if __name__ == "__main__":
    main()
