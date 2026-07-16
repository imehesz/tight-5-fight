class_name Player
extends Fighter
## The chosen comedian. Reads input actions (shared by keyboard and the
## on-screen touch controls) and emits interact_pressed for door entry.

signal interact_pressed

## Baseline walk speed; plane drops nudge it via apply_speed_effect().
const BASE_SPEED := 140.0

## Brief lock while the throw animation plays, so the player can't walk or
## re-throw mid-toss (the melee state machine is untouched — no punch damage).
var _throw_lock := 0.0
var _speed_timer := 0.0


func _init() -> void:
	hurt_layer = 2
	attack_mask = 4
	move_speed = BASE_SPEED
	# Here rather than at each spawn site, so no scene can forget it.
	outfit = GameState.outfit


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
	super(damage, from_x)


func _physics_process(delta: float) -> void:
	if state == FState.DEAD:
		return
	if _speed_timer > 0.0:
		_speed_timer -= delta
		if _speed_timer <= 0.0:
			move_speed = BASE_SPEED
	if state == FState.HIT:
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		move_and_slide()
		return
	if _throw_lock > 0.0:
		_throw_lock -= delta
		velocity.x = 0
		move_and_slide()
		return

	set_ducking(Input.is_action_pressed("duck"))
	if state == FState.DUCK:
		return

	if Input.is_action_just_pressed("throw") and _try_throw():
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
