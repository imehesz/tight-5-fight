class_name PlaneFlyby
extends Node2D
## Ambient banner plane: crosses the sky once in a random direction, dragging
## a cloth banner that ripples in the wind, with a random roster head riding
## on top as pilot. Lives in world space (a camera child would inherit every
## camera nudge and make the plane speed up/slow down as the player walks):
## the street hands it the camera, it spawns just off the upwind edge and
## frees itself once it's past the far one. The looping engine drone is a
## child of this node, so it dies with the plane — and with the whole street
## scene when the player enters a venue.

const SPEED := 140.0  # a hair above the player's 140 — you can't pace it
const HALF_W := 320.0  # design viewport is 640x360, camera-centered
const SKY_Y := -112.0  # camera-local: clear of the venue exteriors' rooflines
const BOB_AMP := 7.0
const BOB_SPEED := 1.7
const PROP_SWAP := 0.2
const PLANE_SCALE := 0.35
## Source-pixel anchors on the 437x235 plane art (centered coords): where the
## tow rope leaves the tail, and where the pilot sits. Rough for now — tune.
const TOW_ANCHOR := Vector2(215, -80)
const PILOT_POS := Vector2(-68, -75)
const PILOT_SCALE := 0.45
const BANNER_SEGMENTS := 12
const BANNER_H := 26.0
const BANNER_GAP := 10.0
const WAVE_SPEED := 7.0
const WAVE_AMP := 2.5
const BANNER_CLOTH := Color(0.96, 0.94, 0.88, 0.95)
const BANNER_INK := Color(0.75, 0.1, 0.12)

var banner_text := ""
var camera: Camera2D  # set by the spawner before add_child

var _dir := 1  # +1 flies left-to-right on screen, -1 the reverse
var _frames: Array = []
var _frame := 0
var _prop_timer := 0.0
var _rig: Node2D
var _sprite: Sprite2D
var _banner: Polygon2D
var _banner_w := 120.0
var _banner_x0 := 0.0  # trailing-signed x where the cloth attaches
var _engine: AudioStreamPlayer
var _pilot: Sprite2D
var _look_timer := randf_range(0.8, 2.5)
var _t := randf() * TAU
var _exit_x := 0.0


func _ready() -> void:
	z_index = -7  # in the sky: over the street tiles, behind exteriors/signs
	_dir = 1 if randf() < 0.5 else -1
	for p in ["res://shared/assets/bodies/plane_1.png",
			"res://shared/assets/bodies/plane_2.png"]:
		if ResourceLoader.exists(p):
			_frames.append(load(p))

	# The source art faces left, so it's already correct for dir == -1 and the
	# whole rig (plane + pilot) mirrors for dir == +1.
	_rig = Node2D.new()
	_rig.scale = Vector2(-PLANE_SCALE * _dir, PLANE_SCALE)
	_sprite = Sprite2D.new()
	if not _frames.is_empty():
		_sprite.texture = _frames[0]
	_rig.add_child(_sprite)
	_add_pilot()
	_build_banner()
	add_child(_rig)

	_engine = AudioStreamPlayer.new()
	_engine.bus = "SFX"
	add_child(_engine)
	if ResourceLoader.exists("res://shared/assets/sfx/plane.ogg"):
		var s: AudioStream = load("res://shared/assets/sfx/plane.ogg")
		if s is AudioStreamOggVorbis:
			s.loop = true
		_engine.stream = s
		_engine.volume_db = linear_to_db(0.05)
		_engine.play()

	_exit_x = HALF_W + 218.0 * PLANE_SCALE + BANNER_GAP + _banner_w + 40.0
	position = Vector2(camera.global_position.x - _dir * _exit_x,
			camera.global_position.y + SKY_Y)


func _process(delta: float) -> void:
	_t += delta
	position.x += _dir * SPEED * delta
	position.y = camera.global_position.y + SKY_Y + sin(_t * BOB_SPEED) * BOB_AMP
	rotation = sin(_t * BOB_SPEED * 0.7) * 0.03

	_prop_timer += delta
	if _prop_timer >= PROP_SWAP and _frames.size() > 1:
		_prop_timer = 0.0
		_frame = (_frame + 1) % _frames.size()
		_sprite.texture = _frames[_frame]

	if is_instance_valid(_pilot):
		_look_timer -= delta
		if _look_timer <= 0.0:
			_look_timer = randf_range(0.8, 2.5)
			_pilot.flip_h = not _pilot.flip_h

	_wave_banner()
	# Engine hum fades in from the edge, peaks overhead, fades back out.
	var rel_x := position.x - camera.global_position.x
	if _engine.playing:
		var presence: float = clampf(1.15 - absf(rel_x) / _exit_x, 0.05, 1.0)
		_engine.volume_db = linear_to_db(presence * 0.9)

	# Gone once past the far screen edge — or left hopelessly behind because
	# the player outran it (world-space, so the camera can walk away from it).
	if _dir * rel_x > _exit_x or _dir * rel_x < -_exit_x - 240.0:
		queue_free()


func _add_pilot() -> void:
	var chars: Array = GameState.characters
	if chars.is_empty():
		return
	var path := String(chars.pick_random().get("HeadSpritePath", ""))
	if not ResourceLoader.exists(path):
		return
	_pilot = Sprite2D.new()
	_pilot.texture = load(path)
	_pilot.scale = Vector2(PILOT_SCALE, PILOT_SCALE)
	_pilot.position = PILOT_POS
	_rig.add_child(_pilot)  # after the plane sprite, so it rides fully on top


## Cloth strip + static text + tow rope, all in root space (never mirrored, so
## the lettering stays readable in both directions). The strip is a Polygon2D
## rebuilt every frame by _wave_banner(); geometry extends from the tow point
## toward the trailing edge via the signed x in _banner_x0.
func _build_banner() -> void:
	var label := Label.new()
	label.text = banner_text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", BANNER_INK)
	_banner_w = label.get_minimum_size().x + 24.0

	var tow := TOW_ANCHOR * Vector2(-PLANE_SCALE * _dir, PLANE_SCALE)
	var s := float(-_dir)  # trailing direction: opposite of travel
	_banner_x0 = tow.x + s * BANNER_GAP

	var rope := Line2D.new()
	rope.width = 1.0
	rope.default_color = Color(0.15, 0.15, 0.18)
	rope.points = PackedVector2Array([tow, Vector2(_banner_x0, tow.y)])
	add_child(rope)

	_banner = Polygon2D.new()
	_banner.color = BANNER_CLOTH
	_banner.position = Vector2(0, tow.y)
	add_child(_banner)
	_wave_banner()

	var mid := _banner_x0 + s * _banner_w / 2.0
	label.position = Vector2(mid - _banner_w / 2.0 + 12.0,
			tow.y - label.get_minimum_size().y / 2.0)
	label.custom_minimum_size = Vector2(_banner_w - 24.0, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)


## Ripple the cloth: a sine runs down the strip, pinned at the attached end
## and swinging wider toward the free end.
func _wave_banner() -> void:
	var s := float(-_dir)
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in BANNER_SEGMENTS + 1:
		var f := float(i) / BANNER_SEGMENTS
		var x := _banner_x0 + s * _banner_w * f
		var off := sin(_t * WAVE_SPEED + f * 5.5) * WAVE_AMP * (0.2 + f)
		top.append(Vector2(x, -BANNER_H / 2.0 + off))
		bottom.append(Vector2(x, BANNER_H / 2.0 + off))
	bottom.reverse()
	_banner.polygon = top + bottom
