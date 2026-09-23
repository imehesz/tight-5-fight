class_name Decorators
extends RefCounted
## The chest decorations the player can wear — a flag, a logo, a gold star —
## pinned to the shirt (or the dress) wherever their comedian is drawn.
## Purely cosmetic: nothing here touches damage, speed or score.
##
## The catalog is ONE shared list every edition wears — shared/assets/
## decorators/decorators.json, right next to the art it lists — plus an
## optional games/<id>/decorators.json for a city's own extras. Data, like
## characters.json and weapons.json, not code: adding one is a PNG in that
## folder and a row in that file. Nothing in the game hardcodes a decoration.
##
## Unlike weapons, a city file ADDS to the shared list rather than replacing it.
## A city row whose id is new leads the shelf; one whose id is already shared
## overlays that row field by field, so `{"id": "palm-tree", "enabled": false}`
## benches one shared decoration in one edition without copying the rest.
##
## NB the manifest key is "decorators", NOT "decor" — that one is already taken
## by the street's ambient dressing (see StreetDecor).
##
## Per-row fields (see decorators.json):
##   id       permanent identity. Saves and purchases key on this, so a row can
##            be renamed or re-priced without anyone losing what they bought.
##   category display grouping ONLY — the picker heads a block with it and
##            nothing else ever reads it.
##   name     what the card is labelled.
##   path     PNG relative to the JSON it is written in (or "shared/..." / a
##            full res:// path).
##   price    JOKE POINTS. 0 means wear it straight away; anything higher has
##            to be bought once, and the SERVER charges it (see /decor).
##   enabled  false benches the row: dropped entirely, like a disabled venue.
##            A benched pick falls back to nothing, so no save is ever broken.
##   scale    optional per-item size multiplier on CHEST_BASE_PX, for art whose
##            subject doesn't fill its canvas. Defaults to 1.0.

## "wearing nothing", the value a save holds for a player who has never picked.
const NONE := -1

## How wide a decoration is drawn on the body, in body-local pixels, before a
## row's own `scale`. Art of any canvas size is normalized to it, exactly like
## heads are normalized to Fighter.HEAD_BASE_PX — so this one number is the
## size knob for the whole shelf.
##
## Measured against both body sheets rather than guessed. Standing, the shirt
## runs neck+3 to neck+18 (the male sheet; the female dress carries on to
## neck+23), and below the shoulders the torso is 12px across, x -6..5. A 10px
## square centred on CHEST_POS therefore lands inside the shirt on every frame
## of every animation, with a pixel of margin either side.
const CHEST_BASE_PX := 10.0

## Where the decoration sits, relative to the animation's NECK anchor
## (CharacterFactory.HEAD_OFFSETS) — the same trick the chest strap uses, so it
## rides the walk bob, the punch lean and the hit recoil with no per-frame
## tuning. x mirrors with facing.
const CHEST_POS := Vector2(0, 10)

## Ducking squashes the torso to roughly half its standing height — the shirt
## ends at neck+12 instead of neck+18 — so the decoration needs its own shorter
## anchor and a size to match, or it would spill off onto the knees.
const CHEST_DUCK_POS := Vector2(0, 7)
const DUCK_SCALE := 0.7

## Rows normalized from JSON at load: {id, name, category, price, tex, scale}.
static var _rows: Array[Dictionary] = []


## Every edition wears this list; a city's decorators.json only adds to it.
const SHARED_PATH := "res://shared/assets/decorators/decorators.json"


## Parse the catalog. GameState calls this at boot with the active game's
## games/<id>/decorators.json path, which usually does not exist — then the
## edition simply wears the shared list as it is.
static func load_roster(path: String) -> void:
	var shared := _read_rows(SHARED_PATH)
	var city: Array[Dictionary] = []
	if path != SHARED_PATH:
		city = _read_rows(path)
	var by_id := {}
	for r in shared:
		by_id[r["id"]] = r
	var extras: Array[Dictionary] = []
	for r in city:
		if by_id.has(r["id"]):
			# Overlay: only the fields the city wrote change. A missing "path"
			# keeps the shared art, already resolved against the shared folder.
			by_id[r["id"]].merge(r, true)
		else:
			extras.append(r)
	var out: Array[Dictionary] = []
	for r in extras + shared:
		if not bool(r.get("enabled", true)):
			continue
		var id := String(r["id"])
		out.append({
			"id": id,
			"name": String(r.get("name", id.to_upper())),
			"category": String(r.get("category", "MISC")),
			"price": maxi(int(r.get("price", 0)), 0),
			"tex": String(r.get("path", "")),
			"scale": maxf(float(r.get("scale", 1.0)), 0.05),
		})
	_rows = out


## One file's rows, with ids checked and each "path" resolved against THAT
## file's folder — done per file, before merging, because a city overlay and
## the shared row it overlays live in different folders. A missing file is [].
static func _read_rows(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if path == "" or not FileAccess.file_exists(path):
		return out
	var base := path.get_base_dir()
	for r in _read_json(path).get("decorators", []):
		if not (r is Dictionary) or String(r.get("id", "")) == "":
			continue
		var row: Dictionary = r.duplicate()
		row["id"] = String(row["id"])
		if row.has("path"):
			row["path"] = _resolve_path(String(row["path"]), base)
		out.append(row)
	return out


## Paths resolve like every other path in the data files: relative to the
## JSON's own folder, with the same two escapes Weapons allows — a leading
## "shared/" resolves from the project root, a full "res://" path is kept.
static func _resolve_path(rel: String, base: String) -> String:
	if rel == "" or rel.begins_with("res://"):
		return rel
	if rel.begins_with("shared/"):
		return "res://" + rel
	return base.path_join(rel)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


static func count() -> int:
	return _rows.size()


## True when this game ships any decorations at all. The settings screen hides
## its whole tab on a game that doesn't.
static func any() -> bool:
	return not available().is_empty()


static func entry(idx: int) -> Dictionary:
	if idx < 0 or idx >= _rows.size():
		return {}
	return _rows[idx]


static func id_of(idx: int) -> String:
	return String(entry(idx).get("id", ""))


static func decor_name(idx: int) -> String:
	return String(entry(idx).get("name", ""))


static func category(idx: int) -> String:
	return String(entry(idx).get("category", ""))


## JOKE POINTS this costs. 0 is FREE here (unlike Weapons.next_upgrade_cost,
## where 0 means "not for sale") — a free decoration is the common case.
static func price(idx: int) -> int:
	return int(entry(idx).get("price", 0))


static func item_scale(idx: int) -> float:
	return float(entry(idx).get("scale", 1.0))


## Loaded texture, or null when the art has not been imported. Callers guard on
## this like every other optional asset: a missing PNG costs the decoration,
## never the run.
static func texture(idx: int) -> Texture2D:
	var path := String(entry(idx).get("tex", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Indices whose art actually imported — what the picker lists, so a half-added
## decoration shows up as nothing rather than as an empty card you can equip
## and then appear to wear nothing.
static func available() -> Array[int]:
	var out: Array[int] = []
	for i in _rows.size():
		if texture(i) != null:
			out.append(i)
	return out


## Saved settings store the decoration by id, not by position, for the reason
## weapons do: inserting a row above must never silently change what everyone
## is wearing. Unknown (including "") → NONE.
static func index_by_id(id: String) -> int:
	if id == "":
		return NONE
	for i in _rows.size():
		if String(_rows[i].get("id", "")) == id:
			return i
	return NONE


## Category labels in FIRST-SEEN order, so the picker's blocks follow the order
## of decorators.json rather than an alphabetical one nobody chose.
static func categories() -> Array[String]:
	var out: Array[String] = []
	for i in available():
		var c := category(i)
		if not out.has(c):
			out.append(c)
	return out


## The available rows in one category, in file order.
static func in_category(c: String) -> Array[int]:
	var out: Array[int] = []
	for i in available():
		if category(i) == c:
			out.append(i)
	return out


## Anchor and size for the decoration on a body playing `anim`, in body-local
## pixels. One place decides this, so the in-run player and the menu dancers
## can never drift apart. `facing` mirrors x exactly like the head and strap.
static func chest_offset(anim: String, facing := 1) -> Vector2:
	var neck := CharacterFactory.head_offset(anim)
	var p := CHEST_DUCK_POS if anim == "duck" else CHEST_POS
	return Vector2((neck.x + p.x) * facing, neck.y + p.y)


## Sprite scale for `idx` on a body playing `anim`, normalizing any canvas size
## down to CHEST_BASE_PX the way heads are normalized to HEAD_BASE_PX.
static func chest_scale(idx: int, anim: String) -> float:
	var tex := texture(idx)
	if tex == null:
		return 0.0
	var s := CHEST_BASE_PX * item_scale(idx) / maxf(tex.get_width(), 1.0)
	return s * (DUCK_SCALE if anim == "duck" else 1.0)
