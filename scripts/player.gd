class_name Player
extends Fighter
## The chosen comedian. Reads input actions (shared by keyboard and the
## on-screen touch controls) and emits interact_pressed for door entry.

signal interact_pressed

## Baseline walk speed; plane drops nudge it via apply_speed_effect().
const BASE_SPEED := 140.0

## Mic-stand swing: an overhead melee hit with double the punch/kick reach,
## gated by a cooldown (punch/kick have none). Damage is kick +15%. During
## the swing SwingSwoosh draws the stand + arc; between swings the stand
## rides on the player's back (see CARRY_* below).
const SWING_DAMAGE := KICK_DAMAGE * 1.15
const SWING_COOLDOWN := 1.5
const SWING_TIME := 0.25
## Punch hitbox reaches ~29px from center (18 + 22/2); this box ends at ~58.
const SWING_BOX_SIZE := Vector2(48, 20)
const SWING_BOX_X := 34.0
## The stand rides on the player's back between swings: slung diagonally,
## mic head poking up behind the shoulder, drawn behind the body sprite.
const CARRY_POS := Vector2(-5, -26)  # sprite center, x mirrors with facing
const CARRY_TILT := 0.4              # radians off vertical, toward the back
const CARRY_LEN := 47.6              # full stand height in local px

## Brief lock while the throw animation plays, so the player can't walk or
## re-throw mid-toss (the melee state machine is untouched — no punch damage).
var _throw_lock := 0.0
var _speed_timer := 0.0
var _swing_lock := 0.0
var _swing_cooldown := 0.0
var _swing_box: Area2D
var _carried_stand: Sprite2D


func _init() -> void:
	hurt_layer = 2
	attack_mask = 4
	move_speed = BASE_SPEED
	# Here rather than at each spawn site, so no scene can forget it.
	outfit = GameState.outfit


func _ready() -> void:
	super()
	# Lets in-flight boss bottles find the player for the close-call check.
	add_to_group("player")
	_build_swing_box()
	_build_carried_stand()


## The between-swings stand on the back. Child index 0 keeps it behind the
## body/head sprites without z_index (negative z would drop it behind the
## scene background, which draws at z 0).
func _build_carried_stand() -> void:
	if not ResourceLoader.exists(SwingSwoosh.STAND_TEX):
		return
	_carried_stand = Sprite2D.new()
	_carried_stand.texture = load(SwingSwoosh.STAND_TEX)
	var s := CARRY_LEN / _carried_stand.texture.get_height()
	_carried_stand.scale = Vector2(s, s)
	_carried_stand.position = CARRY_POS
	add_child(_carried_stand)
	move_child(_carried_stand, 0)


func _process(delta: float) -> void:
	super(delta)
	if _carried_stand:
		# Hidden while the SwingSwoosh draws its own stand, and on defeat
		# (a floating diagonal stand over a lying body looks wrong).
		_carried_stand.visible = _swing_lock <= 0.0 and state != FState.DEAD
		_carried_stand.position.x = CARRY_POS.x * facing
		_carried_stand.flip_h = facing < 0
		_carried_stand.rotation = -CARRY_TILT * facing


## Separate hitbox for the mic-stand swing so the shared punch/kick hitbox
## (and everyone's hurtboxes) keep their tuned sizes untouched.
func _build_swing_box() -> void:
	_swing_box = Area2D.new()
	_swing_box.collision_layer = 0
	_swing_box.collision_mask = attack_mask
	_swing_box.monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SWING_BOX_SIZE
	shape.shape = rect
	_swing_box.add_child(shape)
	_swing_box.position = Vector2(SWING_BOX_X, -30)
	# Reuses Fighter's victim/damage plumbing, same as punch and kick.
	_swing_box.area_entered.connect(_on_hitbox_area_entered)
	add_child(_swing_box)


## Temporary speed modifier from plane drops: bomb slow (0.75) or good-set-box
## boost (1.25). A fresh effect replaces whatever is running outright.
func apply_speed_effect(mult: float, duration: float) -> void:
	move_speed = BASE_SPEED * mult
	_speed_timer = duration


## THE "player got hit" hook — Phase 2's crowd boo goes in here too, don't
## add a second override. Any damage (melee or bottle) breaks the KO streak;
## death passes through here as well, so no separate death hook is needed.
func take_hit(damage: float, from_x: float) -> void:
	GameState.reset_streak()
	# Getting hit interrupts a swing in progress (the cooldown still runs).
	if _swing_lock > 0.0:
		_swing_lock = 0.0
		_swing_box.set_deferred("monitoring", false)
	super(damage, from_x)


func _physics_process(delta: float) -> void:
	if state == FState.DEAD:
		return
	if _speed_timer > 0.0:
		_speed_timer -= delta
		if _speed_timer <= 0.0:
			move_speed = BASE_SPEED
	if _swing_cooldown > 0.0:
		_swing_cooldown -= delta
		if _swing_cooldown <= 0.0:
			GameState.swing_ready_changed.emit(true)
	if state == FState.HIT:
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		move_and_slide()
		return
	if _throw_lock > 0.0:
		_throw_lock -= delta
		velocity.x = 0
		move_and_slide()
		return
	if _swing_lock > 0.0:
		_swing_lock -= delta
		if _swing_lock <= 0.0:
			_swing_box.set_deferred("monitoring", false)
		velocity.x = 0
		move_and_slide()
		return

	set_ducking(Input.is_action_pressed("duck"))
	if state == FState.DUCK:
		return

	if Input.is_action_just_pressed("throw") and _try_throw():
		return
	if Input.is_action_just_pressed("swing") and _try_swing():
		return
	if Input.is_action_just_pressed("punch"):
		try_attack(FState.PUNCH)
	elif Input.is_action_just_pressed("kick"):
		try_attack(FState.KICK)
	if Input.is_action_just_pressed("interact"):
		interact_pressed.emit()

	apply_locomotion(Input.get_axis("move_left", "move_right"))


## Throw a beer bottle forward at head height. Returns true if one was thrown.
func _try_throw() -> bool:
	if not can_act() or not GameState.use_bottle():
		return false
	_throw_lock = 0.35
	velocity.x = 0
	_play("punch")  # reuse the wind-up pose; state stays IDLE so no fist hitbox
	GameState.play_sfx("throw")
	var b := Projectile.new()
	b.hits_enemies = true
	b.position = position + Vector2(facing * 22.0, -40.0)
	b.velocity = Vector2(facing * 320.0, 0.0)
	get_parent().add_child(b)
	return true


## Overhead mic-stand swing. Returns true if it started. Like the throw,
## state stays IDLE (so the fist hitbox never arms) and a lock timer holds
## the player in place for the SWING_TIME.
func _try_swing() -> bool:
	if not can_act() or _swing_cooldown > 0.0:
		return false
	_swing_lock = SWING_TIME
	_swing_cooldown = SWING_COOLDOWN
	GameState.swing_ready_changed.emit(false)
	velocity.x = 0
	_victims.clear()
	_attack_damage = SWING_DAMAGE * damage_scale
	_swing_box.position = Vector2(SWING_BOX_X * facing, -30)
	_swing_box.monitoring = true
	_play("punch")  # reuse the wind-up pose; the swoosh arc sells the swing
	GameState.play_sfx("swing" if GameState.has_sfx("swing") else "throw")
	var sw := SwingSwoosh.new()
	sw.facing = facing
	sw.duration = SWING_TIME
	add_child(sw)
	return true
