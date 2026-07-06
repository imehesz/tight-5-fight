class_name Fighter
extends CharacterBody2D
## Base beat-'em-up combatant: modular body + socketed head, simple
## rectangular hurtbox/hitbox combat, ducking, hit reactions and defeat.

signal died(fighter: Fighter)
signal health_changed(current: float, maximum: float)

enum FState { IDLE, WALK, PUNCH, KICK, DUCK, HIT, DEAD }

const PUNCH_DAMAGE := 10.0
const KICK_DAMAGE := 16.0
const STAND_BOX := Rect2(-8, -44, 16, 44)
const DUCK_BOX := Rect2(-8, -26, 16, 26)
## Whole-fighter scale (boxes scale with it) and extra bobblehead scale for
## the head sprite — heads are real people's pixelated photos, go big.
const BODY_SCALE := 1.4
const HEAD_SCALE := 2.4

var body_type := "M"
var head_path := ""
var max_health := 100.0
var health := 100.0
var move_speed := 130.0
var damage_scale := 1.0
var facing := 1
var state: FState = FState.IDLE
var hurt_layer := 2   # collision layer bit value of our hurtbox
var attack_mask := 4  # hurtbox layers our attacks connect with

var body_sprite: AnimatedSprite2D
var head_sprite: Sprite2D
var hurtbox: Area2D
var hitbox: Area2D
var _hurt_shape: CollisionShape2D
var _attack_damage := 0.0
var _victims := {}


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	health = max_health
	scale = Vector2(BODY_SCALE, BODY_SCALE)
	_build_visuals()
	_build_boxes()
	_play("idle")


func _build_visuals() -> void:
	body_sprite = AnimatedSprite2D.new()
	body_sprite.sprite_frames = CharacterFactory.body_frames(body_type)
	body_sprite.offset = Vector2(0, -CharacterFactory.FRAME_H / 2.0)
	body_sprite.animation_finished.connect(_on_animation_finished)
	body_sprite.frame_changed.connect(_on_frame_changed)
	add_child(body_sprite)

	head_sprite = Sprite2D.new()
	head_sprite.texture = CharacterFactory.head_texture(head_path)
	head_sprite.scale = Vector2(HEAD_SCALE, HEAD_SCALE)
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
	var lift := 8.0 * HEAD_SCALE - 4.0
	head_sprite.position = Vector2(neck.x * facing, neck.y - lift)
	hitbox.position.x = 18 * facing


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
	health = maxf(health - damage, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()
		return
	state = FState.HIT
	_set_hurt_rect(STAND_BOX)
	hitbox.set_deferred("monitoring", false)
	velocity.x = signf(global_position.x - from_x) * 60.0
	_play("hit")


func _die() -> void:
	state = FState.DEAD
	velocity = Vector2.ZERO
	hurtbox.set_deferred("collision_layer", 0)
	hitbox.set_deferred("monitoring", false)
	_play("defeated")
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
