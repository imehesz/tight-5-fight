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
## (a dress and a shirt just take the same dye). Tops are spread around the
## color wheel with one light neutral, so no two read alike.
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
]
## Passed as `outfit` to wear whatever the sheet was drawn with. NPCs use it.
const OUTFIT_BAKED := -1
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
		outfit := OUTFIT_BAKED) -> SpriteFrames:
	var body := body_type if body_type in BODY_TYPES else "M"
	var fit := outfit_index(outfit)
	# Asking for the colors already in the sheet is the same as asking for the
	# sheet: skip the swap and share the NPCs' cached frames.
	if fit != OUTFIT_BAKED and _is_baked_outfit(body, fit):
		fit = OUTFIT_BAKED
	var key := body + "|" + skin.to_html(false) + "|" + str(fit)
	if _frames_cache.has(key):
		return _frames_cache[key]
	var tex := _body_texture(body, skin, fit)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for a in ANIMS:
		sf.add_animation(a.name)
		sf.set_animation_speed(a.name, a.fps)
		sf.set_animation_loop(a.name, a.loop)
		for f in int(a.frames):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(f * FRAME_W, int(a.row) * FRAME_H, FRAME_W, FRAME_H)
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


static func _body_texture(body: String, skin: Color, outfit: int) -> Texture2D:
	var tex: Texture2D = load(GameState.body_path(body))
	if skin.is_equal_approx(DEFAULT_SKIN) and outfit == OUTFIT_BAKED:
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
			swaps.append({"from": BAKED_OUTFIT[body][part], "to": OUTFITS[outfit][part]})
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			for s in swaps:
				if _matches(c, s["from"]):
					var t: Color = s["to"]
					img.set_pixel(x, y, Color(t.r, t.g, t.b, c.a))
					break
	return ImageTexture.create_from_image(img)


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
