class_name CharacterFactory
extends RefCounted
## Modular character system: two generic animated bodies (M/F) + swappable
## comedian heads socketed at the neck. Sheet layout must match
## tools/gen_assets.py (rows = animations, columns = frames, 32x48 frames).

const BODY_SHEETS := {
	"M": "res://assets/gen/bodies/body_male.png",
	"F": "res://assets/gen/bodies/body_female.png",
}
## Skin tone baked into the generated sheets (SKIN in tools/gen_assets.py).
## body_frames() palette-swaps exactly these pixels to a character's SkinColor.
const DEFAULT_SKIN := Color(233 / 255.0, 192 / 255.0, 152 / 255.0)
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


static func body_frames(body_type: String, skin: Color = DEFAULT_SKIN) -> SpriteFrames:
	var body := body_type if BODY_SHEETS.has(body_type) else "M"
	var key := body + "|" + skin.to_html(false)
	if _frames_cache.has(key):
		return _frames_cache[key]
	var tex := _body_texture(body, skin)
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


static func _body_texture(body: String, skin: Color) -> Texture2D:
	var tex: Texture2D = load(BODY_SHEETS[body])
	if skin.is_equal_approx(DEFAULT_SKIN):
		return tex
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and _is_default_skin(c):
				img.set_pixel(x, y, Color(skin.r, skin.g, skin.b, c.a))
	return ImageTexture.create_from_image(img)


static func _is_default_skin(c: Color) -> bool:
	# Tolerant compare: import/quantization can shift channels by a hair.
	return absf(c.r - DEFAULT_SKIN.r) < 0.02 \
			and absf(c.g - DEFAULT_SKIN.g) < 0.02 \
			and absf(c.b - DEFAULT_SKIN.b) < 0.02


static func head_texture(path: String) -> Texture2D:
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	# Fallback so a bad JSON path never crashes the game.
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.75, 0.6))
	return ImageTexture.create_from_image(img)


static func head_offset(anim: String) -> Vector2:
	return HEAD_OFFSETS.get(anim, Vector2(0, -39))
