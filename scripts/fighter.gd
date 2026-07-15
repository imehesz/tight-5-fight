class_name Fighter
extends CharacterBody2D
## Base beat-'em-up combatant: modular body + socketed head, simple
## rectangular hurtbox/hitbox combat, ducking, hit reactions and defeat.

signal died(fighter: Fighter)
signal health_changed(current: float, maximum: float)

enum FState { IDLE, WALK, PUNCH, KICK, DUCK, HIT, DEAD }

const PUNCH_DAMAGE := 10.0
const KICK_DAMAGE := 16.0
## Combat juice tuning: longer hitstop on a killing blow, the white-blink
## flash on any hit, and the shake sizes for "player hurt" vs "somebody KO'd".
const KILL_HITSTOP := 0.09
const FLASH_COLOR := Color(6.0, 6.0, 6.0)
const FLASH_FADE := 0.12
const SHAKE_PLAYER_HURT := 3.0
const SHAKE_KO := 4.0
const STAND_BOX := Rect2(-8, -44, 16, 44)
const DUCK_BOX := Rect2(-8, -26, 16, 26)
## Whole-fighter scale (boxes scale with it) and extra bobblehead scale for
## the head sprite — heads are real people's pixelated photos, go big.
## Head textures can be any size (200x200 photos, 16x16 pixel art...): they
## are normalized so every head displays as if it were 16px * HEAD_SCALE.
const BODY_SCALE := 1.4
const HEAD_SCALE := 2.4
const HEAD_BASE_PX := 16.0

## Roster name from characters.json ("CharacterName"). The global board
## counts KOs by this, so an unconfigured fighter ("" here) never reports.
var char_name := ""
var body_type := "M"
var skin_color := CharacterFactory.DEFAULT_SKIN
## Index into CharacterFactory.OUTFITS. Player and Enemy each pick one in
## _init() (settings / random); anything else wears the sheet as drawn.
var outfit := CharacterFactory.OUTFIT_BAKED
var head_path := ""
## Optional per-character head nudges (JSON "HeadOffsetX"/"HeadOffsetY", in
## body pixels). Positive Y moves the head DOWN — use it when long hair puts
## the chin well above the image bottom, so the chin still meets the neck.
## Positive X moves the head toward the facing direction (mirrors on flip).
## head_scale (JSON "HeadScale") is an extra zoom on top of normalization —
## bump it above 1.0 when big hair fills the crop and shrinks the face.
var head_offset_x := 0.0
var head_offset_y := 0.0
var head_scale := 1.0
## JSON "inWheelchair": legs are erased from the body frames and a chair
## sprite (behind the body) rides along. Kick plays the punch animation.
var in_wheelchair := false
var max_health := 100.0
var health := 100.0
var move_speed := 130.0
## Extra whole-fighter size multiplier on top of BODY_SCALE (boxes scale with
## it). Venues bump this to make the comedians roomier; set before add_child.
var size_scale := 1.0
var damage_scale := 1.0
var facing := 1
## Direction (+1/-1) the last hit should push this fighter — AWAY from the
## attacker. Set first thing in take_hit(); needed because on a fatal hit the
## knockback line is never reached (_die() returns first), yet the KO launch
## in enemy.gd still needs the direction.
var last_hit_dir := 1.0
var state: FState = FState.IDLE
var hurt_layer := 2   # collision layer bit value of our hurtbox
var attack_mask := 4  # hurtbox layers our attacks connect with

var body_sprite: AnimatedSprite2D
var head_sprite: Sprite2D
var wheel_sprite: Sprite2D
var _wheelie_tex: Array[Texture2D] = []
var hurtbox: Area2D
var hitbox: Area2D
var _hurt_shape: CollisionShape2D
var _attack_damage := 0.0
var _victims := {}


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	health = max_health
	scale = Vector2(BODY_SCALE, BODY_SCALE) * size_scale
	_build_visuals()
	_build_boxes()
	_play("idle")


func _build_visuals() -> void:
	# Chair first, so it draws behind the body (seat back behind the torso).
	if in_wheelchair:
		_wheelie_tex = CharacterFactory.wheelie_textures()
	if not _wheelie_tex.is_empty():
		wheel_sprite = Sprite2D.new()
		wheel_sprite.texture = _wheelie_tex[0]
		var ws := CharacterFactory.WHEELIE_BASE_PX \
				/ maxf(wheel_sprite.texture.get_width(), 1.0)
		wheel_sprite.scale = Vector2(ws, ws)
		wheel_sprite.position = CharacterFactory.WHEELIE_POS
		add_child(wheel_sprite)

	body_sprite = AnimatedSprite2D.new()
	body_sprite.sprite_frames = CharacterFactory.body_frames(
			body_type, skin_color, outfit, in_wheelchair)
	body_sprite.offset = Vector2(0, -CharacterFactory.FRAME_H / 2.0)
	body_sprite.animation_finished.connect(_on_animation_finished)
	body_sprite.frame_changed.connect(_on_frame_changed)
	add_child(body_sprite)

	head_sprite = Sprite2D.new()
	head_sprite.texture = CharacterFactory.head_texture(head_path)
	var s := HEAD_SCALE * head_scale \
			* (HEAD_BASE_PX / maxf(head_sprite.texture.get_width(), 1.0))
	head_sprite.scale = Vector2(s, s)
	add_child(head_sprite)


func _build_boxes() -> void:
	# Body shape only silences move_and_slide; it collides with nothing.
	var body_shape := CollisionShape2D.new()
	var brect := RectangleShape2D.new()
	brect.size = Vector2(12, 30)
	body_shape.shape = brect
	body_shape.position = Vector2(0, -15)
	collision_layer = 0
	collision_mask = 0
	add_child(body_shape)

	hurtbox = Area2D.new()
	hurtbox.collision_layer = hurt_layer
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	hurtbox.set_meta("fighter", self)
	_hurt_shape = CollisionShape2D.new()
	var hrect := RectangleShape2D.new()
	hrect.size = STAND_BOX.size
	_hurt_shape.shape = hrect
	_hurt_shape.position = STAND_BOX.get_center()
	hurtbox.add_child(_hurt_shape)
	add_child(hurtbox)

	hitbox = Area2D.new()
	hitbox.collision_layer = 0
	hitbox.collision_mask = attack_mask
	hitbox.monitoring = false
	var hshape := CollisionShape2D.new()
	var arect := RectangleShape2D.new()
	arect.size = Vector2(22, 14)
	hshape.shape = arect
	hitbox.add_child(hshape)
	hitbox.position = Vector2(18, -30)
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	add_child(hitbox)


func _process(_delta: float) -> void:
	body_sprite.flip_h = facing < 0
	head_sprite.flip_h = facing < 0
	var neck := CharacterFactory.head_offset(body_sprite.animation)
	# Lift the head so it sits on the neck, minus a little overlap.
	var lift := head_sprite.texture.get_height() * head_sprite.scale.y / 2.0 - 4.0
	head_sprite.position = Vector2((neck.x + head_offset_x) * facing,
			neck.y - lift + head_offset_y)
	hitbox.position.x = 18 * facing
	if wheel_sprite:
		wheel_sprite.flip_h = facing < 0
		wheel_sprite.position.x = CharacterFactory.WHEELIE_POS.x * facing
		# Wheels roll with the walk cycle; parked on frame 1 otherwise.
		var wf := body_sprite.frame % 2 if state == FState.WALK else 0
		wheel_sprite.texture = _wheelie_tex[wf]


## Apply a character entry from characters.json. Call before add_child().
func configure(cfg: Dictionary) -> void:
	char_name = String(cfg.get("CharacterName", ""))
	body_type = String(cfg.get("BodyType", "M"))
	skin_color = Color.from_string(String(cfg.get("SkinColor", "")),
			CharacterFactory.DEFAULT_SKIN)
	head_path = String(cfg.get("HeadSpritePath", ""))
	head_offset_x = float(cfg.get("HeadOffsetX", 0))
	head_offset_y = float(cfg.get("HeadOffsetY", 0))
	head_scale = maxf(float(cfg.get("HeadScale", 1.0)), 0.1)
	in_wheelchair = bool(cfg.get("inWheelchair", false))


# ---------------------------------------------------------------- actions
func can_act() -> bool:
	return state == FState.IDLE or state == FState.WALK


func try_attack(kind: FState) -> void:
	if not can_act():
		return
	state = kind
	velocity.x = 0
	_victims.clear()
	_attack_damage = (PUNCH_DAMAGE if kind == FState.PUNCH else KICK_DAMAGE) * damage_scale
	_play("punch" if kind == FState.PUNCH else "kick")
	GameState.play_sfx("punch" if kind == FState.PUNCH else "kick")


func set_ducking(on: bool) -> void:
	if on and can_act():
		state = FState.DUCK
		velocity.x = 0
		_play("duck")
		_set_hurt_rect(DUCK_BOX)
	elif not on and state == FState.DUCK:
		state = FState.IDLE
		_play("idle")
		_set_hurt_rect(STAND_BOX)


func is_ducking() -> bool:
	return state == FState.DUCK


## Shared walk/idle handling; subclasses feed a -1..1 direction each frame.
func apply_locomotion(dir: float) -> void:
	if not can_act():
		move_and_slide()
		return
	velocity.x = dir * move_speed
	if absf(dir) > 0.01:
		facing = 1 if dir > 0 else -1
		state = FState.WALK
		_play("walk")
	else:
		state = FState.IDLE
		_play("idle")
	move_and_slide()


func take_hit(damage: float, from_x: float) -> void:
	if state == FState.DEAD:
		return
	last_hit_dir = signf(global_position.x - from_x)
	if last_hit_dir == 0.0:
		last_hit_dir = float(-facing)
	flash()
	if health - damage <= 0.0:
		GameState.hitstop(KILL_HITSTOP)
	else:
		GameState.hitstop()
	health = maxf(health - damage, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()
		return
	if self is Player:
		GameState.request_shake(SHAKE_PLAYER_HURT)
	state = FState.HIT
	_set_hurt_rect(STAND_BOX)
	hitbox.set_deferred("monitoring", false)
	velocity.x = last_hit_dir * 60.0
	_play("hit")
	GameState.play_sfx("hurt")


## Blink the whole fighter (body + head + wheelchair) white for a moment.
## Modulating self covers all child sprites; values above 1.0 saturate the
## bright pixels toward white, which is exactly the arcade "hit blink".
func flash() -> void:
	modulate = FLASH_COLOR
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, FLASH_FADE)


func _die() -> void:
	state = FState.DEAD
	velocity = Vector2.ZERO
	hurtbox.set_deferred("collision_layer", 0)
	hitbox.set_deferred("monitoring", false)
	GameState.request_shake(SHAKE_KO)
	_play("defeated")
	GameState.play_sfx("defeat")
	died.emit(self)


# ---------------------------------------------------------------- internals
func _set_hurt_rect(r: Rect2) -> void:
	# Deferred: this can run from inside a physics signal callback.
	(_hurt_shape.shape as RectangleShape2D).set_deferred("size", r.size)
	_hurt_shape.set_deferred("position", r.get_center())


func _play(anim: String) -> void:
	if body_sprite.animation != anim or not body_sprite.is_playing():
		body_sprite.play(anim)


func _on_frame_changed() -> void:
	var attacking := state == FState.PUNCH or state == FState.KICK
	hitbox.monitoring = attacking and body_sprite.frame == 1


func _on_animation_finished() -> void:
	if state == FState.PUNCH or state == FState.KICK or state == FState.HIT:
		state = FState.IDLE
		hitbox.monitoring = false
		_play("idle")


func _on_hitbox_area_entered(area: Area2D) -> void:
	if _victims.has(area) or not area.has_meta("fighter"):
		return
	_victims[area] = true
	var target: Fighter = area.get_meta("fighter")
	target.take_hit(_attack_damage, global_position.x)
