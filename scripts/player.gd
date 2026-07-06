class_name Player
extends Fighter
## The chosen comedian. Reads input actions (shared by keyboard and the
## on-screen touch controls) and emits interact_pressed for door entry.

signal interact_pressed


func _init() -> void:
	hurt_layer = 2
	attack_mask = 4
	move_speed = 140.0


func _physics_process(delta: float) -> void:
	if state == FState.DEAD:
		return
	if state == FState.HIT:
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		move_and_slide()
		return

	set_ducking(Input.is_action_pressed("duck"))
	if state == FState.DUCK:
		return

	if Input.is_action_just_pressed("punch"):
		try_attack(FState.PUNCH)
	elif Input.is_action_just_pressed("kick"):
		try_attack(FState.KICK)
	if Input.is_action_just_pressed("interact"):
		interact_pressed.emit()

	apply_locomotion(Input.get_axis("move_left", "move_right"))
