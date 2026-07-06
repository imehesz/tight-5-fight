extends Node2D
## The Street Phase: infinite scrolling street with random hecklers and
## periodically spawning venues. Walk to a venue door and press up to enter.

const GROUND_Y := 310.0
const TILE_W := 320.0
const TILE_COUNT := 5
const FIRST_VENUE_X := 900.0
const VENUE_SPACING_MIN := 1100.0
const VENUE_SPACING_MAX := 1600.0
const DOOR_HALF_WIDTH := 28.0
const HECKLER_MAX := 4

var player: Player
var camera: Camera2D
var hud: Hud

var _tiles: Array = []
var _doors: Array = []  # [{x, data, hint}]
var _next_venue_x := FIRST_VENUE_X
var _venue_index := 0
var _spawn_timer := 2.0
var _busy := false


func _ready() -> void:
	_build_tiles()
	camera = Camera2D.new()
	camera.limit_left = 0
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	hud = Hud.new()
	add_child(hud)
	hud.set_venue_text("THE STREET")
	add_child(TouchControls.new())
	_spawn_player(Vector2(120, GROUND_Y))
	camera.position = Vector2(320, 180)
	camera.reset_smoothing()


func _process(delta: float) -> void:
	if is_instance_valid(player):
		player.position.x = maxf(player.position.x, 20.0)
		camera.position = Vector2(maxf(player.position.x, 320.0), 180.0)
	_recycle_tiles()
	_maybe_spawn_venue()
	_maybe_spawn_heckler(delta)
	_cull_stragglers()
	_update_door_hints()


# ---------------------------------------------------------------- world
func _build_tiles() -> void:
	var tex: Texture2D = load("res://assets/gen/street/street_tile.png")
	for i in TILE_COUNT:
		var t := Sprite2D.new()
		t.texture = tex
		t.centered = false
		t.position = Vector2(i * TILE_W, 0)
		t.z_index = -10
		add_child(t)
		_tiles.append(t)


func _recycle_tiles() -> void:
	for t in _tiles:
		while t.position.x + TILE_W < camera.position.x - 480.0:
			t.position.x += TILE_COUNT * TILE_W
		while t.position.x > camera.position.x + 480.0:
			t.position.x -= TILE_COUNT * TILE_W


func _maybe_spawn_venue() -> void:
	if camera.position.x + 700.0 < _next_venue_x:
		return
	var data: Dictionary = GameState.venue_data_for_index(_venue_index)
	_venue_index += 1
	var vx := _next_venue_x
	_next_venue_x += randf_range(VENUE_SPACING_MIN, VENUE_SPACING_MAX)

	var ext := Sprite2D.new()
	var path := String(data.get("ExteriorSpritePath", ""))
	if ResourceLoader.exists(path):
		ext.texture = load(path)
	ext.centered = false
	# Exterior art is 160x120 with the door at the bottom center (at vx).
	ext.position = Vector2(vx - 80.0, GROUND_Y - 114.0)
	ext.z_index = -5
	add_child(ext)

	var hint := Label.new()
	hint.text = "^ ENTER"
	hint.position = Vector2(vx - 60.0, GROUND_Y - 136.0)
	hint.custom_minimum_size = Vector2(120, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 4)
	hint.modulate = Color(1.0, 0.9, 0.4)
	hint.visible = false
	add_child(hint)

	_doors.append({"x": vx, "data": data, "hint": hint})


func _update_door_hints() -> void:
	for d in _doors:
		d.hint.visible = is_instance_valid(player) \
				and absf(player.position.x - d.x) <= DOOR_HALF_WIDTH


# ---------------------------------------------------------------- spawns
func _spawn_player(pos: Vector2) -> void:
	player = Player.new()
	var cfg := GameState.selected_character_data()
	player.body_type = String(cfg.get("BodyType", "M"))
	player.head_path = String(cfg.get("HeadSpritePath", ""))
	player.position = pos
	player.interact_pressed.connect(_on_player_interact)
	player.died.connect(_on_player_died)
	add_child(player)
	hud.bind_player(player)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.target = player


func _maybe_spawn_heckler(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = randf_range(2.5, 5.0)
	if not is_instance_valid(player) \
			or get_tree().get_nodes_in_group("enemies").size() >= HECKLER_MAX:
		return
	var cfg: Dictionary = GameState.enemy_characters(1)[0]
	var e := Enemy.new()
	e.body_type = String(cfg.get("BodyType", "M"))
	e.head_path = String(cfg.get("HeadSpritePath", ""))
	e.aggressive = randf() < 0.4
	e.move_speed = randf_range(60.0, 95.0)
	e.score_value = 100
	e.target = player
	e.position = Vector2(camera.position.x + 380.0, GROUND_Y)
	add_child(e)


func _cull_stragglers() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.position.x < camera.position.x - 700.0:
			e.queue_free()


# ---------------------------------------------------------------- events
func _on_player_interact() -> void:
	if _busy or not is_instance_valid(player):
		return
	for d in _doors:
		if absf(player.position.x - d.x) <= DOOR_HALF_WIDTH:
			_busy = true
			GameState.pending_venue = d.data
			GameState.enter_venue()
			return


func _on_player_died(_f: Fighter) -> void:
	_busy = true
	await get_tree().create_timer(1.4).timeout
	var corpse := player
	if GameState.lose_life():
		GameState.finish_run()
		return
	if is_instance_valid(corpse):
		corpse.queue_free()
	_spawn_player(Vector2(maxf(camera.position.x - 200.0, 60.0), GROUND_Y))
	_busy = false
