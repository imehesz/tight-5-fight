class_name Projectile
extends Area2D
## Thrown beer bottle. Straight throws fly at head height (duck under them);
## lobbed throws arc down onto the player's position (move away).

const GROUND_Y := 314.0
## Odds the crowd laughs when a boss bottle beans the player.
const LAUGH_CHANCE := 0.25
## Ducking under a boss fastball as it passes overhead pays a small bonus.
const CLOSE_CALL_POINTS := 50
const CLOSE_CALL_X := 12.0

var velocity := Vector2.ZERO
var arc_gravity := 0.0  # "gravity" is a native Area2D property
var damage := 10.0
## Boss throws (default) hit the player; player throws hit enemies instead.
var hits_enemies := false
var _sprite: Sprite2D
var _life := 4.0  # safety net so a throw that misses everything can't linger
var _close_call_done := false  # one close-call award per bottle


func _ready() -> void:
	add_to_group("projectiles")
	collision_layer = 0
	collision_mask = 4 if hits_enemies else 2  # enemy vs player hurtbox layer
	_sprite = Sprite2D.new()
	var bottle_path := GameState.projectile_path()
	if bottle_path != "" and ResourceLoader.exists(bottle_path):
		_sprite.texture = load(bottle_path)
	_sprite.scale = Vector2(1.5, 1.5)  # readable on phone screens
	add_child(_sprite)
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(12, 15)
	cs.shape = rs
	add_child(cs)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	_life -= delta
	velocity.y += arc_gravity * delta
	position += velocity * delta
	_sprite.rotation += 8.0 * delta
	# Boss fastballs only (lobs are dodged by moving, and the venue-clear
	# bonus already pays for that). ~5px of travel per frame, so the 12px
	# window can't be stepped over.
	if not hits_enemies and arc_gravity == 0.0 and not _close_call_done:
		var p := get_tree().get_first_node_in_group("player")
		if is_instance_valid(p) and p.is_ducking() \
				and absf(position.x - p.global_position.x) < CLOSE_CALL_X:
			_close_call_done = true
			GameState.add_score(CLOSE_CALL_POINTS)
			FloatingText.spawn(get_parent(), global_position + Vector2(0, -14),
					"CLOSE ONE! +%d" % CLOSE_CALL_POINTS, Color(0.6, 1.0, 0.6))
	if position.y >= GROUND_Y:
		_smash()
	elif _life <= 0.0:
		queue_free()


func _smash() -> void:
	FloatingText.spawn(get_parent(), global_position + Vector2(0, -10),
			"*crash*", Color(0.7, 0.9, 0.7))
	GameState.play_sfx("smash")
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	# Boss check first: boss hurtboxes carry no "fighter" meta. A stagger is
	# not a KO — plain add_score, so it never builds or extends a streak.
	if area.has_meta("boss"):
		var boss: Boss = area.get_meta("boss")
		if boss.stagger():
			GameState.add_score(Boss.STAGGER_POINTS)
			FloatingText.spawn(get_parent(), global_position + Vector2(0, -20),
					"STUNNED! +%d" % Boss.STAGGER_POINTS, Color(1.0, 0.85, 0.4))
		else:
			FloatingText.spawn(get_parent(), global_position + Vector2(0, -20),
					"*clink*", Color(0.7, 0.7, 0.75))
		GameState.play_sfx("smash")
		queue_free()
		return
	if not area.has_meta("fighter"):
		return
	var f: Fighter = area.get_meta("fighter")
	f.take_hit(damage, global_position.x)
	# Boss bottle beaning the player: the crowd finds it funny sometimes.
	# hits_enemies=false bottles exist only in boss venues, so venue-only free.
	if not hits_enemies and randf() < LAUGH_CHANCE:
		GameState.play_crowd("laugh")
		GameState.crowd_reaction.emit("laugh")
	queue_free()
