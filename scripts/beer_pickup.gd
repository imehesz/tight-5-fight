class_name BeerPickup
extends Area2D
## A beer bottle lying on the street. Walk over it to pick it up (up to the
## carry cap); once full, further bottles are left on the ground. Spawned by
## street.gd only after the first boss has been beaten.

var _sprite: Sprite2D
var _bob := 0.0


func _ready() -> void:
	add_to_group("beer_pickups")
	collision_layer = 0
	collision_mask = 2  # player hurtbox layer
	_sprite = Sprite2D.new()
	var bottle_path := GameState.projectile_path()
	if bottle_path != "" and ResourceLoader.exists(bottle_path):
		_sprite.texture = load(bottle_path)
	_sprite.scale = Vector2(2.4, 2.4)  # a little bigger than a thrown bottle
	add_child(_sprite)
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(39, 72)
	cs.shape = rs
	add_child(cs)
	area_entered.connect(_on_area_entered)
	_glint()


## A soft up/down bob so the bottle reads as an item, not scenery.
func _process(delta: float) -> void:
	_bob += delta
	_sprite.position.y = sin(_bob * 3.0) * 2.0


func _glint() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(_sprite, "modulate", Color(1.3, 1.3, 1.1), 0.6)
	tw.tween_property(_sprite, "modulate", Color(1, 1, 1), 0.6)


func _on_area_entered(area: Area2D) -> void:
	if not area.has_meta("fighter"):
		return
	if not (area.get_meta("fighter") is Player):
		return
	if not GameState.add_bottle():
		return  # carrying the max already — leave it lying there
	FloatingText.spawn(get_parent(), global_position + Vector2(0, -30),
			"+BEER", Color(1.0, 0.85, 0.35))
	GameState.play_sfx("clear")
	queue_free()
