class_name Enemy
extends Fighter
## Street hecklers and rival venue comedians. Passive hecklers wander and
## yell insults until provoked; aggressive ones chase and attack the player.

const INSULTS := [
	"Hey, you suck!",
	"BOO!",
	"My grandma is funnier!",
	"Heard 'em all before!",
	"Get a day job!",
	"Weak material, pal!",
	"Is THIS the show?",
]

var aggressive := true
var provoked := false
var target: Node2D
var score_value := 100
var attack_cooldown := 1.2
var attack_range := 42.0

const BAR_W := 26.0

## KO launch: how far back and how high a defeated heckler flies (px),
## plus the tumble angle while airborne.
const LAUNCH_DIST := 90.0
const LAUNCH_RISE := 46.0
const LAUNCH_TILT := 85.0

var _cooldown_left := 1.0
var _wander_dir := 0.0
var _wander_left := 0.0
var _insult_left := 0.0
var _bar_bg: ColorRect
var _bar_fill: ColorRect


func _init() -> void:
	hurt_layer = 4
	attack_mask = 2
	move_speed = 90.0
	max_health = 40.0
	damage_scale = 0.5
	# Every heckler dresses differently. Here rather than at each spawn site,
	# so no scene can forget it.
	outfit = GameState.random_enemy_outfit()


func _ready() -> void:
	super()
	add_to_group("enemies")
	_insult_left = randf_range(1.0, 3.0)
	_build_health_bar()
	health_changed.connect(_on_health_bar_update)


## Tiny life bar above the head; only visible once they've taken damage.
func _build_health_bar() -> void:
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0, 0, 0, 0.6)
	_bar_bg.size = Vector2(BAR_W + 2, 5)
	_bar_bg.position = Vector2(-(BAR_W + 2) / 2.0, -82)
	_bar_bg.z_index = 40
	_bar_bg.visible = false
	add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.position = Vector2(1, 1)
	_bar_fill.size = Vector2(BAR_W, 3)
	_bar_bg.add_child(_bar_fill)


func _on_health_bar_update(current: float, maximum: float) -> void:
	var ratio := current / maxf(maximum, 1.0)
	_bar_bg.visible = ratio < 0.999 and state != FState.DEAD
	_bar_fill.size.x = BAR_W * ratio
	if ratio < 0.35:
		_bar_fill.color = Color(0.9, 0.25, 0.2)
	elif ratio < 0.7:
		_bar_fill.color = Color(0.95, 0.8, 0.25)
	else:
		_bar_fill.color = Color(0.3, 0.9, 0.35)


func _physics_process(delta: float) -> void:
	if state == FState.DEAD:
		return
	if state == FState.HIT:
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		move_and_slide()
		return

	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	var has_target: bool = is_instance_valid(target) and target.get("state") != FState.DEAD
	if (aggressive or provoked) and has_target:
		_fight(delta)
	else:
		_wander(delta)
		_heckle(delta)


func _fight(_delta: float) -> void:
	var dx := target.global_position.x - global_position.x
	if absf(dx) > attack_range:
		apply_locomotion(signf(dx))
		return
	facing = 1 if dx > 0 else -1
	apply_locomotion(0.0)
	if _cooldown_left == 0.0 and can_act():
		try_attack(FState.PUNCH if randf() < 0.6 else FState.KICK)
		_cooldown_left = attack_cooldown


func _wander(delta: float) -> void:
	_wander_left -= delta
	if _wander_left <= 0.0:
		_wander_left = randf_range(1.0, 2.5)
		_wander_dir = [-0.5, 0.0, 0.0, 0.5].pick_random()
	apply_locomotion(_wander_dir)


func _heckle(delta: float) -> void:
	if aggressive:
		return
	_insult_left -= delta
	if _insult_left <= 0.0:
		_insult_left = randf_range(3.0, 6.0)
		FloatingText.spawn(get_parent(), global_position + Vector2(0, -100),
				INSULTS.pick_random(), Color.WHITE, true)


func take_hit(damage: float, from_x: float) -> void:
	provoked = true
	super(damage, from_x)


func _die() -> void:
	_bar_bg.visible = false
	GameState.add_score(score_value)
	GameState.count_ko(char_name)
	FloatingText.spawn(get_parent(), global_position + Vector2(0, -90),
			"+%d" % score_value, Color(0.6, 1.0, 0.6))
	super()
	# KO launch: fly backward away from the killer, arc up then back down to
	# the ground line this enemy stood on, tipping over while airborne. Safe to
	# tween: _physics_process early-returns in DEAD, so nothing fights for
	# control of position. The "defeated" animation keeps playing in flight.
	var fly := create_tween()
	fly.set_parallel(true)
	fly.tween_property(self, "position:x", position.x + last_hit_dir * LAUNCH_DIST, 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fly.tween_property(self, "rotation_degrees", last_hit_dir * LAUNCH_TILT, 0.4)
	var arc := create_tween()
	arc.tween_property(self, "position:y", position.y - LAUNCH_RISE, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	arc.tween_property(self, "position:y", position.y, 0.33) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var fade := create_tween()
	fade.tween_interval(1.0)
	fade.tween_property(self, "modulate:a", 0.0, 0.6)
	fade.tween_callback(queue_free)
