class_name PlaneDrop
extends Area2D
## Payload released by the banner plane, living in world space as a sibling
## of the plane so it survives the plane flying off. Three kinds:
##  - "bomb": whistles down ballistically and explodes on the street (or on
##    a direct hit); the player is slowed 25% for 4s if caught in the blast.
##  - "box": a GOOD SET BOX parachuting down. Touch it in the air or grab it
##    off the ground within 3s (1.5 resting + 1.5 blinking, then gone) for
##    +25% speed for 4s.
##  - "beer": a FREE BEER BOX, which falls and expires exactly like the good
##    set box but tops the player's beer up to the carry cap. Only ever
##    dropped once the beer mechanic is unlocked (after the first boss); a
##    player already carrying the cap gets nothing and the box is left alone.

const GROUND_Y := 300.0  # same rest height street items (beer) use
const BOMB_W := 66.0     # display widths — sources are large PNGs
const BOX_W := 50.0
const GRAVITY := 480.0
const BOMB_VX := 112.0   # forward momentum inherited from the plane
const BOX_FALL := 70.0   # parachute descent, px/s
const BOX_DRIFT := 25.0
const BOX_SWAY := 18.0
const SLOW_MULT := 0.75
const BOOST_MULT := 1.25
const EFFECT_TIME := 4.0
const BOX_REST := 1.5
const BOX_BLINK := 1.5
const BOX_POINTS := 50
## Generous on purpose. The bomb is aimed at a camera-local point at release
## (plane_flyby._drop_off) and never leads the player, so during the ~0.9s fall
## a running player covers ~126px and walks clean out of a tight blast. This is
## the stopgap; the real fix is leading the player's velocity at release.
const BOOM_RADIUS := 130.0
const BOMB_DAMAGE_PCT := 0.15  # of the player's max health

const BOMB_TEX := "res://shared/assets/parts/t5f-bomb_med.png"
const BOMB_TEX_RTL := "res://shared/assets/parts/t5f-bomb_med_lr.png"
const CHUTE_TEX := "res://shared/assets/parts/t5f-good-set-box_parachute.png"
const BOX_TEX := "res://shared/assets/parts/t5f-good-set-box_no-parachute.png"
const BEER_CHUTE_TEX := "res://shared/assets/parts/t5f-free-beer-box_parachute.png"
const BEER_BOX_TEX := "res://shared/assets/parts/t5f-free-beer-box_no-parachute.png"
## NOTE: extension is load-bearing. Unlike GameState._load_stream(), which
## tries .ogg/.mp3/.wav in turn, this path is literal -- it silently
## no-ops if the file is not found. Changed .ogg -> .wav on 2026-08-24
## with the Vorbis-to-QOA swap; keep in sync with shared/assets/sfx/.
const WHISTLE := "res://shared/assets/sfx/sfx-bomb-drop.wav"

var kind := "bomb"  # "bomb" | "box" | "beer", set by the plane before add_child
var dir := 1        # travel direction inherited from the plane

var _sprite: Sprite2D
var _vy := 0.0
var _landed := false
var _age := 0.0
var _done := false
var _whistle: AudioStreamPlayer


## The bomb art is direction-specific and never mirrored: the base PNG flies
## left-to-right, the _rtl PNG right-to-left — falling back to the base art
## until the RTL file exists.
static func bomb_tex(dir_: int) -> String:
	if dir_ < 0 and ResourceLoader.exists(BOMB_TEX_RTL):
		return BOMB_TEX_RTL
	return BOMB_TEX


## Both box kinds share the good-set box's art dimensions (461x680 chuted,
## 461x323 collapsed), so they fall, land and expire on identical geometry.
func _chute_tex() -> String:
	return BEER_CHUTE_TEX if kind == "beer" else CHUTE_TEX


func _box_tex() -> String:
	return BEER_BOX_TEX if kind == "beer" else BOX_TEX


func _ready() -> void:
	z_index = 1  # in front of exteriors and fighters while it falls past them
	collision_layer = 0
	collision_mask = 2  # player hurtbox layer
	_sprite = Sprite2D.new()
	add_child(_sprite)
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	cs.shape = rs
	add_child(cs)
	if kind == "bomb":
		_set_tex(bomb_tex(dir), BOMB_W)
		rs.size = Vector2(57, 27)
		_start_whistle()
	else:
		_set_tex(_chute_tex(), BOX_W)
		# The box rides at the bottom of the chute art (origin = box bottom).
		rs.size = Vector2(44, 32)
		cs.position.y = -17.0
	area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if kind == "bomb":
		_vy += GRAVITY * delta
		position += Vector2(dir * BOMB_VX, _vy) * delta
		# Nose tips from level toward straight down as it falls.
		rotation = move_toward(rotation, dir * PI / 2.0, 2.2 * delta)
		if position.y >= GROUND_Y - 8.0:
			_explode()
		return
	if not _landed:
		position.x += (dir * BOX_DRIFT + sin(_age * 2.5) * BOX_SWAY) * delta
		position.y += BOX_FALL * delta
		if position.y >= GROUND_Y:
			position.y = GROUND_Y
			_landed = true
			_age = 0.0
			_set_tex(_box_tex(), BOX_W)  # chute collapses on touchdown
		return
	# Grounded: fresh for BOX_REST, blinks for BOX_BLINK, then it's gone.
	if _age > BOX_REST + BOX_BLINK:
		queue_free()
	elif _age > BOX_REST:
		_sprite.visible = fmod(_age, 0.24) < 0.12


func _set_tex(path: String, width: float) -> void:
	if not ResourceLoader.exists(path):
		return
	_sprite.texture = load(path)
	var s := width / _sprite.texture.get_width()
	_sprite.scale = Vector2(s, s)
	if kind != "bomb":
		# Anchor the art's bottom edge at the node origin, so landing maths
		# stay the same whether the chute is attached (680px) or gone (323px).
		_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0)


func _start_whistle() -> void:
	if GameState.is_sfx_muted("bomb-drop"):
		return
	if not ResourceLoader.exists(WHISTLE):
		return
	_whistle = AudioStreamPlayer.new()
	_whistle.stream = load(WHISTLE)
	_whistle.bus = "SFX"
	GameState.apply_playback_type(_whistle)
	_whistle.volume_db = linear_to_db(0.75)  # the raw wav runs hot
	add_child(_whistle)
	_whistle.play()


func _on_area_entered(area: Area2D) -> void:
	if _done or not area.has_meta("fighter"):
		return
	if not (area.get_meta("fighter") is Player):
		return
	if kind == "bomb":
		_explode()
	elif kind == "beer":
		_grab_beer()
	else:
		_grab(area.get_meta("fighter"))


## Tops the player's beer off to the carry cap — 0, 1 or 2 bottles all become
## MAX_BOTTLES. A player already carrying the cap gets nothing at all, and the
## box is left where it is (like a ground bottle) rather than eaten.
func _grab_beer() -> void:
	if GameState.beer_bottles >= GameState.MAX_BOTTLES:
		return
	_done = true
	GameState.set_bottles(GameState.MAX_BOTTLES)
	GameState.add_score(BOX_POINTS)
	FloatingText.spawn(get_parent(), global_position + Vector2(0, -46),
			"FREE BEER!", Color(1.0, 0.78, 0.25))
	FloatingText.spawn(get_parent(), global_position + Vector2(0, -62),
			"+%d" % BOX_POINTS, Color(1.0, 0.85, 0.35))
	GameState.play_sfx("clear")
	queue_free()


func _grab(p: Player) -> void:
	_done = true
	p.apply_speed_effect(BOOST_MULT, EFFECT_TIME)
	GameState.add_score(BOX_POINTS)
	# Seconds back on the run clock — chasing the box is worth the detour. The
	# HUD flies its own "+10s" up to the clock (hud.gd _on_time_added), so no
	# floating text for it here.
	GameState.add_time(GameState.BOX_TIME_BONUS)
	FloatingText.spawn(get_parent(), global_position + Vector2(0, -46),
			"+SPEED!", Color(0.45, 1.0, 0.5))
	FloatingText.spawn(get_parent(), global_position + Vector2(0, -62),
			"+%d" % BOX_POINTS, Color(1.0, 0.85, 0.35))
	GameState.play_sfx("clear")
	queue_free()


func _explode() -> void:
	_done = true
	_sprite.visible = false
	set_deferred("monitoring", false)
	if is_instance_valid(_whistle):
		_whistle.stop()
	GameState.play_sfx("smash")
	GameState.request_shake(6.0)
	_burst()
	# The street scene owns the player; venues never spawn drops.
	var p: Variant = get_parent().get("player")
	if p is Player and is_instance_valid(p) \
			and global_position.distance_to(p.global_position) <= BOOM_RADIUS:
		p.apply_speed_effect(SLOW_MULT, EFFECT_TIME)
		# Through take_hit so the blast also flinches/knocks the player back
		# (and handles death) exactly like any other hit.
		p.take_hit(p.max_health * BOMB_DAMAGE_PCT, global_position.x)
		# The real punishment: half a minute off the run clock. The HUD flies
		# its own "-30s" down to the clock (hud.gd _on_time_lost), so the
		# floating text here stays about the blast.
		GameState.lose_time(GameState.BOMB_TIME_PENALTY)
		FloatingText.spawn(get_parent(), p.global_position + Vector2(0, -70),
				"SLOWED!", Color(1.0, 0.35, 0.3))
	await get_tree().create_timer(1.1).timeout
	queue_free()


## Fireball + lingering smoke, all CPU particles (web-export friendly), plus
## a white core flash that swells and fades.
func _burst() -> void:
	var fire := CPUParticles2D.new()
	fire.one_shot = true
	fire.explosiveness = 1.0
	fire.amount = 26
	fire.lifetime = 0.5
	fire.direction = Vector2.UP
	fire.spread = 180.0
	fire.gravity = Vector2(0, -40)
	fire.initial_velocity_min = 60.0
	fire.initial_velocity_max = 190.0
	fire.scale_amount_min = 3.0
	fire.scale_amount_max = 7.0
	fire.color_ramp = _ramp([Color(1, 0.95, 0.6), Color(1, 0.55, 0.1),
			Color(0.55, 0.1, 0.05, 0.0)])
	fire.emitting = true
	add_child(fire)

	var smoke := CPUParticles2D.new()
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	smoke.amount = 14
	smoke.lifetime = 0.95
	smoke.direction = Vector2.UP
	smoke.spread = 70.0
	smoke.gravity = Vector2(0, -70)
	smoke.initial_velocity_min = 25.0
	smoke.initial_velocity_max = 70.0
	smoke.scale_amount_min = 5.0
	smoke.scale_amount_max = 10.0
	smoke.color_ramp = _ramp([Color(0.35, 0.33, 0.3, 0.85),
			Color(0.2, 0.2, 0.2, 0.0)])
	smoke.emitting = true
	add_child(smoke)

	var flash := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 14:
		pts.append(Vector2.from_angle(TAU * i / 14) * 12.0)
	flash.polygon = pts
	flash.color = Color(1, 1, 0.9)
	add_child(flash)
	var tw := create_tween().set_parallel()
	tw.tween_property(flash, "scale", Vector2(4.5, 4.5), 0.16)
	tw.tween_property(flash, "modulate:a", 0.0, 0.16)


func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	var offs := PackedFloat32Array()
	for i in colors.size():
		offs.append(float(i) / (colors.size() - 1))
	g.offsets = offs
	return g
