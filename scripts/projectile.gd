class_name Projectile
extends Area2D
## Thrown beer bottle. Straight throws fly at head height (duck under them);
## lobbed throws arc down onto the player's position (move away).

const GROUND_Y := 314.0

var velocity := Vector2.ZERO
var arc_gravity := 0.0  # "gravity" is a native Area2D property
var damage := 10.0
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("projectiles")
	collision_layer = 0
	collision_mask = 2  # player hurtbox
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/gen/props/bottle.png")
	add_child(_sprite)
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(8, 10)
	cs.shape = rs
	add_child(cs)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	velocity.y += arc_gravity * delta
	position += velocity * delta
	_sprite.rotation += 8.0 * delta
	if position.y >= GROUND_Y:
		_smash()
	elif position.x < -200.0 or position.x > 5000.0:
		queue_free()


func _smash() -> void:
	FloatingText.spawn(get_parent(), global_position + Vector2(0, -10),
			"*crash*", Color(0.7, 0.9, 0.7))
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	if not area.has_meta("fighter"):
		return
	var f: Fighter = area.get_meta("fighter")
	f.take_hit(damage, global_position.x)
	queue_free()
