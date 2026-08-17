class_name StreetDecor
extends RefCounted
## The street's ambient dressing: the small stuff in the foreground strip
## between the fighters' feet and the bottom of the frame. Purely decorative —
## no collision, no damage, no pickups, nothing that can change a run. If a
## prop's art is missing the street simply grows less of it.
##
## Two kinds, because they need two different lifetimes:
##
##   `litter`   — static props lying on the pavement (crumpled newspaper).
##                Scattered once when a stretch of street is generated, then
##                streamed in and out with the venues and billboards and saved
##                with the street, so the trash is in the same place when you
##                walk back out of a venue.
##   `critters` — things that run through and leave (a rat). Spawned on a
##                timer near the camera, free themselves on the way out;
##                nothing about them is persisted, because nothing about them
##                lasts long enough to be worth remembering.
##
## The roster lives in shared/assets/decor/decor.json, exactly like
## weapons.json: adding a prop is a PNG plus a row, no code. Run the art
## through helper-tools/normalize_decor.py first (it also prints the alpha
## profile you read `FootFrac` off).
##
## Shared fields:
##   `DecorId`    — stable id; litter is saved by it, so don't rename casually.
##   `SpritePath` — resolved like every other data-file path: relative to this
##                  JSON's folder, `shared/...` from the project root, or a
##                  full res:// path kept as-is.
##   `Scale`      — on-screen size, in 640x360 design px per source px. The
##                  ONLY size control; nothing is baked into the art, so a prop
##                  that lands too big is a JSON edit, never a regeneration.
##   `Weight`     — share of the picks against its siblings, like sponsors.
##   `isDisabled` — benched, exactly like a venue or a weapon.
##
## Critter-only fields:
##   `FootFrac`   — where the ground contact sits, as a fraction of sprite
##                  height. NOT 1.0 for anything with a tail or a trailing
##                  bit: the rat's tail hangs below its paws, and standing the
##                  bounding box on the pavement puts the animal on tiptoe.
##   `SpeedMin/Max`, `PauseMin/Max` — run speed (design px/sec) and how long it
##                  stops to look around.
##   `BobPx`, `BobHz` — the scurry: how far the body lifts while running and
##                  how fast. Small. Set BobPx to 0 for something that glides.

const SHARED_ROSTER := "res://shared/assets/decor/decor.json"

static var _litter: Array[Dictionary] = []
static var _critters: Array[Dictionary] = []
static var _loaded := false


## Parse the roster. GameState calls this at boot with the active game's
## games/<id>/decor.json; when that file doesn't exist (the usual case) the
## shared set loads instead, so a new edition gets the street dressing for
## free and only overrides it if it actually wants different trash.
static func load_roster(override_path: String = "") -> void:
	var path := override_path \
			if override_path != "" and FileAccess.file_exists(override_path) \
			else SHARED_ROSTER
	var doc := _read_json(path)
	var base := path.get_base_dir()
	_litter = _rows(doc.get("litter", []), base)
	_critters = _rows(doc.get("critters", []), base)
	_loaded = true


## A missing or mangled roster is not an error worth a crash — it just means a
## bare street. Every accessor funnels through here so code that touches decor
## before GameState's boot-time load (or from a bare editor scene) still sees
## the shared set rather than an empty one.
static func _ensure() -> void:
	if not _loaded:
		load_roster()


static func litter() -> Array[Dictionary]:
	_ensure()
	return _litter


static func critters() -> Array[Dictionary]:
	_ensure()
	return _critters


## Weighted pick from a pool, skipping anything whose art has not imported —
## an invisible prop would otherwise take up a slot and leave a gap in the
## street for no reason. {} when the pool has nothing usable, which every
## caller treats as "place nothing".
static func _pick(pool: Array[Dictionary]) -> Dictionary:
	var usable: Array[Dictionary] = []
	var total := 0
	for r in pool:
		if texture(r) == null:
			continue
		usable.append(r)
		total += int(r.weight)
	if usable.is_empty():
		return {}
	var roll := randi() % maxi(total, 1)
	for r in usable:
		roll -= int(r.weight)
		if roll < 0:
			return r
	return usable.back()


static func pick_litter() -> Dictionary:
	return _pick(litter())


static func pick_critter() -> Dictionary:
	return _pick(critters())


## Restore path for litter saved in street_state: the id is persisted, the row
## is not. {} when the prop vanished from the roster mid-session (can't happen
## inside one page load, but the caller stays defensive anyway).
static func litter_by_id(id: String) -> Dictionary:
	for r in litter():
		if String(r.id) == id:
			return r
	return {}


## Loaded texture for a row, or null when the art has not been imported yet.
## Guarded like every other optional asset in the game: a missing PNG costs
## you the prop, never the run.
static func texture(row: Dictionary) -> Texture2D:
	var path := String(row.get("tex", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# ---------------------------------------------------------------- loading
static func _rows(raw: Array, base: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in raw:
		if not (r is Dictionary) or bool(r.get("isDisabled", false)):
			continue
		var id := String(r.get("DecorId", ""))
		if id == "":
			continue
		out.append({
			"id": id,
			"tex": _resolve_path(String(r.get("SpritePath", "")), base),
			"scale": float(r.get("Scale", 0.12)),
			"weight": maxi(int(r.get("Weight", 20)), 1),
			"foot": clampf(float(r.get("FootFrac", 1.0)), 0.0, 1.0),
			"speed_min": float(r.get("SpeedMin", 55.0)),
			"speed_max": float(r.get("SpeedMax", 85.0)),
			"pause_min": float(r.get("PauseMin", 0.7)),
			"pause_max": float(r.get("PauseMax", 2.0)),
			"bob_px": float(r.get("BobPx", 0.0)),
			"bob_hz": float(r.get("BobHz", 10.0)),
		})
	return out


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
