class_name CharacterFactory
extends RefCounted
## Modular character system: two generic animated bodies (M/F) + swappable
## comedian heads socketed at the neck. Sheet layout must match
## tools/gen_assets.py (rows = animations, columns = frames, 32x48 frames).

## Body sheets are resolved per active game via GameState.body_path() (shared
## defaults live in shared/assets/bodies/; a game may override them in its
## manifest). M/F are the only supported body types.
const BODY_TYPES := ["M", "F"]
## Skin tone baked into the generated sheets (SKIN in tools/gen_assets.py).
## body_frames() palette-swaps exactly these pixels to a character's SkinColor.
const DEFAULT_SKIN := Color(233 / 255.0, 192 / 255.0, 152 / 255.0)
## Outfit colors baked into each sheet by tools/gen_assets.py (its MALE and
## FEMALE dicts) — the pixels body_frames() looks for when recoloring. Nobody
## wears them unrecolored in-game; they are the "before" side of the swap.
## The female sheet draws a dress, so its "bottom" never appears in the art
## today; it is listed only so both bodies describe an outfit alike.
const BAKED_OUTFIT := {
	"M": {"top": Color(66 / 255.0, 98 / 255.0, 200 / 255.0),
			"bottom": Color(46 / 255.0, 46 / 255.0, 72 / 255.0)},
	"F": {"top": Color(202 / 255.0, 64 / 255.0, 128 / 255.0),
			"bottom": Color(122 / 255.0, 42 / 255.0, 92 / 255.0)},
}
## The outfits the player can pick from — one shared list, worn on either body
## (a dress and a shirt just take the same dye). Eight flat tops, then eight
## gradient ones; both sets are spread around the color wheel with a neutral
## apiece, so no two read alike.
const OUTFITS := [
	{"name": "BLUE", "top": Color(66 / 255.0, 98 / 255.0, 200 / 255.0),
			"bottom": Color(46 / 255.0, 46 / 255.0, 72 / 255.0)},
	{"name": "CRIMSON", "top": Color(198 / 255.0, 48 / 255.0, 58 / 255.0),
			"bottom": Color(70 / 255.0, 26 / 255.0, 34 / 255.0)},
	{"name": "GOLD", "top": Color(226 / 255.0, 176 / 255.0, 42 / 255.0),
			"bottom": Color(74 / 255.0, 56 / 255.0, 26 / 255.0)},
	{"name": "BONE", "top": Color(226 / 255.0, 230 / 255.0, 238 / 255.0),
			"bottom": Color(58 / 255.0, 60 / 255.0, 74 / 255.0)},
	{"name": "PINK", "top": Color(202 / 255.0, 64 / 255.0, 128 / 255.0),
			"bottom": Color(122 / 255.0, 42 / 255.0, 92 / 255.0)},
	{"name": "CYAN", "top": Color(46 / 255.0, 178 / 255.0, 182 / 255.0),
			"bottom": Color(24 / 255.0, 84 / 255.0, 88 / 255.0)},
	{"name": "VIOLET", "top": Color(134 / 255.0, 74 / 255.0, 214 / 255.0),
			"bottom": Color(70 / 255.0, 38 / 255.0, 116 / 255.0)},
	{"name": "LIME", "top": Color(126 / 255.0, 190 / 255.0, 60 / 255.0),
			"bottom": Color(52 / 255.0, 78 / 255.0, 30 / 255.0)},
	# Gradient tops (see "top2"): the shirt fades from "top" at the shoulders
	# to "top2" at the hem. The shirt is only ~13px tall, so the ends are set
	# far apart (light/saturated down to deep) — a subtle pair just reads as a
	# flat shirt at this scale. Ordered as a walk around the wheel, so the
	# picker's last two rows go warm -> green -> blue -> neutral -> purple.
	{"name": "SUNSET", "top": Color(252 / 255.0, 196 / 255.0, 88 / 255.0),
			"top2": Color(184 / 255.0, 34 / 255.0, 92 / 255.0),
			"bottom": Color(86 / 255.0, 38 / 255.0, 52 / 255.0)},
	{"name": "COPPER", "top": Color(248 / 255.0, 166 / 255.0, 70 / 255.0),
			"top2": Color(104 / 255.0, 40 / 255.0, 16 / 255.0),
			"bottom": Color(62 / 255.0, 34 / 255.0, 18 / 255.0)},
	{"name": "ACID", "top": Color(226 / 255.0, 246 / 255.0, 96 / 255.0),
			"top2": Color(48 / 255.0, 92 / 255.0, 22 / 255.0),
			"bottom": Color(40 / 255.0, 58 / 255.0, 18 / 255.0)},
	{"name": "EMERALD", "top": Color(154 / 255.0, 236 / 255.0, 138 / 255.0),
			"top2": Color(12 / 255.0, 84 / 255.0, 78 / 255.0),
			"bottom": Color(24 / 255.0, 64 / 255.0, 54 / 255.0)},
	{"name": "OCEAN", "top": Color(136 / 255.0, 222 / 255.0, 244 / 255.0),
			"top2": Color(24 / 255.0, 50 / 255.0, 150 / 255.0),
			"bottom": Color(26 / 255.0, 42 / 255.0, 78 / 255.0)},
	{"name": "STEEL", "top": Color(202 / 255.0, 218 / 255.0, 240 / 255.0),
			"top2": Color(40 / 255.0, 50 / 255.0, 76 / 255.0),
			"bottom": Color(40 / 255.0, 46 / 255.0, 62 / 255.0)},
	{"name": "TWILIGHT", "top": Color(224 / 255.0, 176 / 255.0, 246 / 255.0),
			"top2": Color(52 / 255.0, 34 / 255.0, 142 / 255.0),
			"bottom": Color(44 / 255.0, 32 / 255.0, 78 / 255.0)},
	{"name": "BUBBLEGUM", "top": Color(252 / 255.0, 192 / 255.0, 222 / 255.0),
			"top2": Color(160 / 255.0, 26 / 255.0, 118 / 255.0),
			"bottom": Color(86 / 255.0, 22 / 255.0, 66 / 255.0)},
]
## Passed as `outfit` to wear whatever the sheet was drawn with. NPCs use it.
const OUTFIT_BAKED := -1
## Wheelchair overlay for characters with "inWheelchair" in characters.json:
## legs are erased from their body frames and this chair (drawn behind the
## body) fills the space. Two frames; [1] alternates in while walking.
## Art can be any size — it is normalized to display WHEELIE_BASE_PX wide,
## like heads. WHEELIE_POS centers the chair art on the fighter (feet origin).
const WHEELIE_PATHS := [
	"res://shared/assets/bodies/wheelie_1.png",
	"res://shared/assets/bodies/wheelie_2.png",
]
const WHEELIE_BASE_PX := 51.0
## x is relative to facing: negative = behind the character (mirrors on flip).
const WHEELIE_POS := Vector2(-2, -21)
const FRAME_W := 32
const FRAME_H := 48
const ANIMS := [
	{"name": "idle", "row": 0, "frames": 2, "fps": 4.0, "loop": true},
	{"name": "walk", "row": 1, "frames": 4, "fps": 8.0, "loop": true},
	{"name": "punch", "row": 2, "frames": 3, "fps": 10.0, "loop": false},
	{"name": "kick", "row": 3, "frames": 3, "fps": 9.0, "loop": false},
	{"name": "duck", "row": 4, "frames": 1, "fps": 4.0, "loop": true},
	{"name": "hit", "row": 5, "frames": 1, "fps": 3.0, "loop": false},
	{"name": "defeated", "row": 6, "frames": 1, "fps": 2.0, "loop": false},
]
## Neck anchor per animation, relative to the fighter's feet. The head sprite
## is centered above this point (lifted by half its scaled height), so heads
## of any size stay socketed to the neck.
const HEAD_OFFSETS := {
	"idle": Vector2(0, -39),
	"walk": Vector2(0, -39),
	"punch": Vector2(1, -39),
	"kick": Vector2(1, -39),
	"duck": Vector2(0, -27),
	"hit": Vector2(-2, -38),
	"defeated": Vector2(-10, -2),
}

static var _frames_cache := {}


static func body_frames(body_type: String, skin: Color = DEFAULT_SKIN,
		outfit := OUTFIT_BAKED, wheelchair := false) -> SpriteFrames:
	var body := body_type if body_type in BODY_TYPES else "M"
	var fit := outfit_index(outfit)
	# Asking for the colors already in the sheet is the same as asking for the
	# sheet: skip the swap and share the NPCs' cached frames.
	if fit != OUTFIT_BAKED and _is_baked_outfit(body, fit):
		fit = OUTFIT_BAKED
	var key := body + "|" + skin.to_html(false) + "|" + str(fit) \
			+ ("|w" if wheelchair else "")
	if _frames_cache.has(key):
		return _frames_cache[key]
	var tex := _body_texture(body, skin, fit, wheelchair)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for a in ANIMS:
		var row := int(a.row)
		# A wheelchair comedian has no leg art to kick with: sample the kick
		# from the punch row instead, so KICK reads as a second arm strike
		# (chair-ram). Same frame count, and the kick row is never displayed.
		if wheelchair and a.name == "kick":
			row = 2  # punch row
		sf.add_animation(a.name)
		sf.set_animation_speed(a.name, a.fps)
		sf.set_animation_loop(a.name, a.loop)
		for f in int(a.frames):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(f * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)
			sf.add_frame(a.name, at)
	_frames_cache[key] = sf
	return sf


## Clamp an outfit choice to a real one; OUTFIT_BAKED passes through.
static func outfit_index(outfit: int) -> int:
	if outfit == OUTFIT_BAKED:
		return OUTFIT_BAKED
	return clampi(outfit, 0, OUTFITS.size() - 1)


static func _is_baked_outfit(body: String, outfit: int) -> bool:
	return OUTFITS[outfit]["top"].is_equal_approx(BAKED_OUTFIT[body]["top"]) \
			and OUTFITS[outfit]["bottom"].is_equal_approx(BAKED_OUTFIT[body]["bottom"])


## Swatch color for the settings picker.
static func outfit_color(outfit: int) -> Color:
	return OUTFITS[clampi(outfit, 0, OUTFITS.size() - 1)]["top"]


## The shirt's bottom color, for the swatch to fade to. Equals outfit_color()
## for the flat outfits, so callers can always draw a two-stop gradient.
static func outfit_color2(outfit: int) -> Color:
	var o: Dictionary = OUTFITS[clampi(outfit, 0, OUTFITS.size() - 1)]
	return o.get("top2", o["top"])


## Vertical extent of the shirt within one frame, as (first_row, last_row):
## the y range, modulo the frame height, where the baked shirt color appears.
## Gives a gradient the same span on every frame of every animation, so a
## walking comedian's shirt doesn't shimmer.
static func _shirt_band(img: Image, baked_top: Color) -> Vector2:
	var lo := FRAME_H
	var hi := -1
	for y in img.get_height():
		var yl := y % FRAME_H
		if yl >= lo and yl <= hi:
			continue  # this row is already inside the band
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and _matches(c, baked_top):
				lo = mini(lo, yl)
				hi = maxi(hi, yl)
				break
	return Vector2(lo, hi)


static func _body_texture(body: String, skin: Color, outfit: int,
		wheelchair := false) -> Texture2D:
	var tex: Texture2D = load(GameState.body_path(body))
	if not wheelchair and skin.is_equal_approx(DEFAULT_SKIN) and outfit == OUTFIT_BAKED:
		return tex
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	# One pass, source pixel -> replacement, so a recolor can never be
	# re-matched and swapped a second time (e.g. a shirt dyed skin-colored).
	var swaps := [{"from": DEFAULT_SKIN, "to": skin}]
	if outfit != OUTFIT_BAKED:
		for part in ["top", "bottom"]:
			var s := {"from": BAKED_OUTFIT[body][part], "to": OUTFITS[outfit][part]}
			# A gradient top fades down the shirt, so it needs the shirt's own
			# y range (measured, not hardcoded — it differs per body sheet).
			if part == "top" and OUTFITS[outfit].has("top2"):
				var band := _shirt_band(img, BAKED_OUTFIT[body]["top"])
				if band.y > band.x:
					s["to2"] = OUTFITS[outfit]["top2"]
					s["band"] = band
			swaps.append(s)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			for s in swaps:
				if _matches(c, s["from"]):
					var t: Color = s["to"]
					if s.has("to2"):
						var band: Vector2 = s["band"]
						var yl := float(y % FRAME_H)
						t = t.lerp(s["to2"],
								clampf((yl - band.x) / (band.y - band.x), 0.0, 1.0))
					img.set_pixel(x, y, Color(t.r, t.g, t.b, c.a))
					break
	if wheelchair:
		_erase_legs(img, body)
	return ImageTexture.create_from_image(img)


## Clear leg pixels for wheelchair characters; the chair sprite fills the
## space. Cut lines come from tools/gen_assets.py geometry: legs start at
## y29 (M) / y32 (F), and walk's scissor lines poke ~1px above that, so the
## cut sits one row higher. The kick row is left alone — body_frames() never
## samples it for wheelchair characters (kick shows the punch row instead).
static func _erase_legs(img: Image, body: String) -> void:
	var cut := 31 if body == "F" else 28
	var clear := Color(0, 0, 0, 0)
	for a in ANIMS:
		var top := int(a.row) * FRAME_H
		for y in range(top, top + FRAME_H):
			var yl := y - top
			for x in img.get_width():
				var wipe := false
				match a.name:
					"idle", "walk", "punch", "hit":
						wipe = yl >= cut
					"duck":
						wipe = yl >= 34  # seated lap + shoes
					"defeated":
						# Lying pose: legs stick out right of the torso.
						wipe = (x % FRAME_W) >= 23 and yl >= 39
				if wipe:
					img.set_pixel(x, y, clear)


static func _matches(c: Color, target: Color) -> bool:
	# Tolerant compare: import/quantization can shift channels by a hair.
	return absf(c.r - target.r) < 0.02 \
			and absf(c.g - target.g) < 0.02 \
			and absf(c.b - target.b) < 0.02


static func head_texture(path: String) -> Texture2D:
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	# Fallback so a bad JSON path never crashes the game.
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.75, 0.6))
	return ImageTexture.create_from_image(img)


static func head_offset(anim: String) -> Vector2:
	return HEAD_OFFSETS.get(anim, Vector2(0, -39))


## Both wheelchair frames, or [] if either is missing — callers skip the
## chair sprite entirely rather than risk indexing a half-loaded pair.
static func wheelie_textures() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for p in WHEELIE_PATHS:
		if not ResourceLoader.exists(p):
			return []
		out.append(load(p) as Texture2D)
	return out
