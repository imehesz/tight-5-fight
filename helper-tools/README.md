# helper-tools/

Helpers for generating new games. Not bundled into the game build. Run from the
repo root with system `python3`.

(Note: the older `tools/` folder is gitignored — put anything meant to be
committed here in `helper-tools/` instead.)

## classify_heads.py

Populates a game's `characters.json` from the head PNGs in its
`assets/heads/` folder. Each filename is treated as a comedian's name; the tool
looks the person up on Wikipedia/Wikidata (free, no API key) and fills in:

- `BodyType`  — `M` / `F` (Wikidata sex-or-gender)
- `SkinColor` — light `#e9c098` / dark `#a0683c` (Wikipedia race/ethnicity categories)

Existing entries are kept (including any hand-tuned `HeadScale` / `HeadOffsetY`);
`hero1` / `hero2` template placeholders are skipped.

```bash
python3 helper-tools/classify_heads.py --game celebs --dry-run   # preview, writes nothing
python3 helper-tools/classify_heads.py --game celebs             # write characters.json
python3 helper-tools/classify_heads.py --game celebs --force     # re-resolve existing too
```

Requires only `requests`. Resolutions are cached in `helper-tools/.cache/` so
re-runs are instant and offline.

### Filename tips (fewer overrides)

Concatenated filenames (`davechappelle.png`) work, but the tool has to *guess*
the word boundaries. You get the most reliable results with two habits:

- **Separate the words** with `-`, `_`, or a space (`dave-chappelle.png`) — the
  tool then searches the exact words instead of brute-forcing splits.
- **Spell the name correctly** — `taylor-tomlinson`, not `taylortomlison`.

With both, correctly-spelled comedians who have a Wikipedia page resolve
automatically; overrides are only needed for people with no Wikipedia page.

### Overrides

Concatenated filenames mostly resolve automatically (`davechappelle` → Dave
Chappelle), but misspellings and obscure names can't. The tool prints those as
`UNRESOLVED`; fix them in `games/<game>/head_overrides.json` (auto-loaded):

```json
{
  "jerreysignfeld": {"query": "Jerry Seinfeld"},
  "rychardpryor":   {"query": "Richard Pryor"},
  "kylekanine":     {"name": "Kyle Kanine", "gender": "M", "skin": "light"}
}
```

- `query` — force the Wikipedia search string, but still auto-detect gender/skin.
- `name` / `gender` / `skin` — hard-code a field, skipping lookup for it.
