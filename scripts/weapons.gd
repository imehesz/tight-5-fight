class_name Weapons
extends RefCounted
## The melee weapons the player can carry, and the one place their art and
## proportions are described. Purely cosmetic: every weapon swings with the
## mic stand's damage, reach and cooldown (see Player.SWING_*), so a run on the
## global leaderboard is never won by picking the chainsaw.
##
## Adding one is a two-step job — drop a PNG in shared/assets/weapons/ and add
## a row below. Nothing else in the game hardcodes a weapon.
##
## Every sprite shares the mic stand's canvas (302x900, art within y 22..872,
## striking end up, centred), which is what lets the swing and carry code size
## them all from the same constants — helper-tools/normalize_weapon.py puts
## generated art onto that canvas.

## `grip` is the texture-space y the player's hand closes on. It is the one
## number that genuinely differs per weapon: a sword is held just under the
## crossguard, a bat down by the knob. Swing code scales grip-to-tip to a fixed
## on-screen length, so this also decides how much weapon hangs past the fist.
##
## `grip_up` flips the weapon end-for-end on the player's BACK only (never
## during the swing): slung handle-up over the shoulder, business end pointing
## down at the hip — which is how you would actually wear a sword or a shovel,
## and how you'd have to wear one to be able to draw it. The two that hang the
## other way are the ones a person really does carry pointy-end-up: the mic
## stand, whose head is its whole silhouette, and the chain, which has no
## business end at all.
const WEAPONS: Array[Dictionary] = [
	{"id": "mic", "name": "MIC STAND", "grip": 780.0, "grip_up": false,
		"tex": "res://shared/assets/parts/weapon_mic-in-stand_small.png"},
	{"id": "sword", "name": "SWORD", "grip": 730.0, "grip_up": true,
		"tex": "res://shared/assets/weapons/weapon_sword.png"},
	{"id": "katana", "name": "KATANA", "grip": 745.0, "grip_up": true,
		"tex": "res://shared/assets/weapons/weapon_katana.png"},
	{"id": "bat", "name": "BAT", "grip": 790.0, "grip_up": true,
		"tex": "res://shared/assets/weapons/weapon_bat.png"},
	{"id": "chainsaw", "name": "CHAINSAW", "grip": 750.0, "grip_up": true,
		"tex": "res://shared/assets/weapons/weapon_chainsaw.png"},
	{"id": "shovel", "name": "SHOVEL", "grip": 700.0, "grip_up": true,
		"tex": "res://shared/assets/weapons/weapon_shovel.png"},
	{"id": "pool-cue", "name": "POOL CUE", "grip": 795.0, "grip_up": true,
		"tex": "res://shared/assets/weapons/weapon_pool-cue.png"},
	{"id": "chain", "name": "CHAIN", "grip": 785.0, "grip_up": false,
		"tex": "res://shared/assets/weapons/weapon_chain.png"},
	# Both guitars are swung by the NECK, so their art is turned end-for-end on
	# the way in (normalize_weapon.py --rotate180) to put the body up at the
	# striking end. Worn neck-up on the back, like a gig bag.
	{"id": "acoustic", "name": "ACOUSTIC", "grip": 690.0, "grip_up": true,
		"tex": "res://shared/assets/weapons/weapon_acoustic.png"},
	{"id": "metal", "name": "METAL", "grip": 710.0, "grip_up": true,
		"tex": "res://shared/assets/weapons/weapon_metal.png"},
]

## The mic stand — what a player who has never opened the weapons tab carries,
## and the fallback whenever a saved pick can't be honoured.
const DEFAULT := 0


static func count() -> int:
	return WEAPONS.size()


static func entry(idx: int) -> Dictionary:
	return WEAPONS[clampi(idx, 0, WEAPONS.size() - 1)]


static func weapon_name(idx: int) -> String:
	return String(entry(idx).get("name", "?"))


static func texture_path(idx: int) -> String:
	return String(entry(idx).get("tex", ""))


static func grip_y(idx: int) -> float:
	return float(entry(idx).get("grip", 780.0))


## True when the weapon is worn handle-up (see `grip_up` above). The picker
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
	for i in WEAPONS.size():
		if texture(i) != null:
			out.append(i)
	return out


## Saved settings store the weapon by id, not by position, so reordering or
## inserting a row above never silently changes what everyone is carrying.
static func index_by_id(id: String) -> int:
	for i in WEAPONS.size():
		if String(WEAPONS[i].get("id", "")) == id:
			return i
	return DEFAULT


static func id_of(idx: int) -> String:
	return String(entry(idx).get("id", ""))
