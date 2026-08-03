class_name Weapons
extends RefCounted
## The melee weapons the player can carry. Purely cosmetic: every weapon swings
## with the mic stand's damage, reach and cooldown (see Player.SWING_*), so a
## run on the global leaderboard is never won by picking the chainsaw.
##
## The roster lives in shared/assets/weapons/weapons.json, right next to the
## art it lists — data, like characters.json and venues.json, not code. Adding
## one is a two-step job: drop a PNG in shared/assets/weapons/ and add a row to
## that file. Nothing else in the game hardcodes a weapon. A game can also ship
## its own games/<id>/weapons.json to replace the shared rack (see games/README.md).
##
## Every sprite shares the mic stand's canvas (302x900, art within y 22..872,
## striking end up, centred), which is what lets the swing and carry code size
## them all from the same constants — helper-tools/normalize_weapon.py puts
## generated art onto that canvas. Both guitars are swung by the NECK, so their
## art is turned end-for-end on the way in (normalize_weapon.py --rotate180) to
## put the body up at the striking end.
##
## Per-row fields (see weapons.json):
##
## `GripY` is the texture-space y the player's hand closes on. It is the one
## number that genuinely differs per weapon: a sword is held just under the
## crossguard, a bat down by the knob. Swing code scales grip-to-tip to a fixed
## on-screen length, so this also decides how much weapon hangs past the fist.
##
## `GripUp` flips the weapon end-for-end on the player's BACK only (never
## during the swing): slung handle-up over the shoulder, business end pointing
## down at the hip — which is how you would actually wear a sword or a shovel,
## and how you'd have to wear one to be able to draw it. The two that hang the
## other way are the ones a person really does carry pointy-end-up: the mic
## stand, whose head is its whole silhouette, and the chain, which has no
## business end at all. (The guitars are worn neck-up, like a gig bag.)

## The shared rack every game gets unless it ships its own weapons.json.
const SHARED_ROSTER := "res://shared/assets/weapons/weapons.json"

## The mic stand — what a player who has never opened the weapons tab carries,
## and the fallback whenever a saved pick can't be honoured. (The first row of
## weapons.json; keep the mic stand there.)
const DEFAULT := 0

## Rows normalized from JSON at load: {id, name, grip, grip_up, tex}.
static var _weapons: Array[Dictionary] = []


## Parse the roster. GameState calls this at boot with the active game's
## games/<id>/weapons.json path; when that file doesn't exist (the usual case)
## the shared rack loads instead. Rows with `"isDisabled": true` are benched:
## dropped entirely, like disabled venues — saves store the weapon by id, so a
## benched pick just falls back to the mic stand and no data is lost.
static func load_roster(override_path: String = "") -> void:
	var path := override_path \
			if override_path != "" and FileAccess.file_exists(override_path) \
			else SHARED_ROSTER
	var rows: Array = _read_json(path).get("weapons", [])
	var base := path.get_base_dir()
	var out: Array[Dictionary] = []
	for r in rows:
		if not (r is Dictionary) or bool(r.get("isDisabled", false)):
			continue
		var id := String(r.get("WeaponId", ""))
		if id == "":
			continue
		out.append({
			"id": id,
			"name": String(r.get("WeaponName", id.to_upper())),
			"grip": float(r.get("GripY", 780.0)),
			"grip_up": bool(r.get("GripUp", false)),
			"tex": _resolve_path(String(r.get("SpritePath", "")), base),
		})
	if out.is_empty():
		# A missing or mangled roster still leaves the player armed.
		out.append({"id": "mic", "name": "MIC STAND", "grip": 780.0,
				"grip_up": false,
				"tex": "res://shared/assets/parts/weapon_mic-in-stand_small.png"})
	_weapons = out


## SpritePath resolves like every other path in the data files: relative to the
## JSON's own folder. Two escapes let a game's weapons.json borrow shared art:
## a leading "shared/" resolves from the project root, and a full "res://" path
## is kept as-is.
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


## Every accessor funnels through here, so code that touches Weapons before
## GameState's boot-time load_roster() (or from a bare editor scene) still sees
## the shared rack rather than an empty one.
static func _entries() -> Array[Dictionary]:
	if _weapons.is_empty():
		load_roster()
	return _weapons


static func count() -> int:
	return _entries().size()


static func entry(idx: int) -> Dictionary:
	var w := _entries()
	return w[clampi(idx, 0, w.size() - 1)]


static func weapon_name(idx: int) -> String:
	return String(entry(idx).get("name", "?"))


static func texture_path(idx: int) -> String:
	return String(entry(idx).get("tex", ""))


static func grip_y(idx: int) -> float:
	return float(entry(idx).get("grip", 780.0))


## True when the weapon is worn handle-up (see `GripUp` above). The picker
## turns its cards over to match, so the rack shows each weapon the way you
## will actually be wearing it rather than the way its file happens to be
## stored.
static func grip_up(idx: int) -> bool:
	return bool(entry(idx).get("grip_up", false))


## Extra rotation for the sprite on the player's back — half a turn for a
## weapon worn handle-up. Callers add it to the carry tilt, which keeps the
## weapon on the same diagonal as the shoulder strap either way and only
## changes which end pokes up over the shoulder.
static func carry_spin(idx: int) -> float:
	return PI if grip_up(idx) else 0.0


## Loaded texture, or null when the art has not been imported yet. Callers
## guard on this exactly like every other optional asset in the game: a missing
## PNG costs you the weapon sprite, never the run.
static func texture(idx: int) -> Texture2D:
	var path := texture_path(idx)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Indices whose art actually imported. The picker lists these, so a half-added
## weapon shows up as nothing rather than as an empty box the player can pick
## and then appear to carry nothing.
static func available() -> Array[int]:
	var out: Array[int] = []
	for i in count():
		if texture(i) != null:
			out.append(i)
	return out


## Saved settings store the weapon by id, not by position, so reordering or
## inserting a row above never silently changes what everyone is carrying.
static func index_by_id(id: String) -> int:
	var w := _entries()
	for i in w.size():
		if String(w[i].get("id", "")) == id:
			return i
	return DEFAULT


static func id_of(idx: int) -> String:
	return String(entry(idx).get("id", ""))
