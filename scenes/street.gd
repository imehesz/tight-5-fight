extends Node2D
## The Street Phase: infinite scrolling street with random hecklers and
## periodically spawning venues. Walk to a venue door and press up to enter.

const GROUND_Y := 310.0
const TILE_W := 320.0
const TILE_COUNT := 5
const FIRST_VENUE_X := 900.0
const VENUE_SPACING_MIN := 1100.0
const VENUE_SPACING_MAX := 1600.0
const DOOR_HALF_WIDTH := 34.0
const EXTERIOR_HEIGHT := 180.0
const HECKLER_MAX := 4
## Beer bottles rest slightly above the fighters' feet; at most a couple lie
## on the visible street at once so they read as a treat, not litter.
const BEER_GROUND_Y := 300.0
const BEER_MAX_ON_SCREEN := 2

var player: Player
var camera: Camera2D
var hud: Hud

var _tiles: Array = []
var _doors: Array = []  # [{x, data, cleared, hint}]
var _next_venue_x := FIRST_VENUE_X
var _venue_index := 0
var _spawn_timer := 2.0
var _beer_timer := 3.0
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

	var saved: Dictionary = GameState.street_state
	if saved.has("doors"):
		# Returning from a venue: rebuild the street exactly as it was.
		_next_venue_x = float(saved.next_venue_x)
		_venue_index = int(saved.venue_index)
		for d in saved.doors:
			_add_venue(float(d.x), d.data, bool(d.cleared))
		_spawn_player(Vector2(float(saved.player_x), GROUND_Y))
	else:
		_spawn_player(Vector2(120, GROUND_Y))
	camera.position = Vector2(maxf(player.position.x, 320.0), 180.0)
	camera.reset_smoothing()


func _process(delta: float) -> void:
	if is_instance_valid(player):
		player.position.x = maxf(player.position.x, 20.0)
		camera.position = Vector2(maxf(player.position.x, 320.0), 180.0)
	_recycle_tiles()
	_maybe_spawn_venue()
	_maybe_spawn_heckler(delta)
	_maybe_spawn_beer(delta)
	_cull_stragglers()
	_update_door_hints()


# ---------------------------------------------------------------- world
func _build_tiles() -> void:
	var tex: Texture2D = load(GameState.street_tile_path())
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
	_add_venue(_next_venue_x, GameState.venue_data_for_index(_venue_index), false)
	_venue_index += 1
	_next_venue_x += randf_range(VENUE_SPACING_MIN, VENUE_SPACING_MAX)


func _add_venue(vx: float, data: Dictionary, cleared: bool) -> void:
	var ext := Sprite2D.new()
	var path := String(data.get("ExteriorSpritePath", ""))
	if ResourceLoader.exists(path):
		ext.texture = load(path)
	ext.centered = false
	# Exterior art displays at a fixed 180px height (640x360 source → 0.5x,
	# never upscaled beyond legacy 160x120), door at bottom center (vx).
	var ext_w := 240.0
	if ext.texture:
		var s := EXTERIOR_HEIGHT / float(ext.texture.get_height())
		ext.scale = Vector2(s, s)
		ext_w = ext.texture.get_width() * s
	ext.position = Vector2(vx - ext_w / 2.0, GROUND_Y - 174.0)
	ext.z_index = -5
	add_child(ext)

	var hint := Label.new()
	hint.text = "^ ENTER"
	hint.position = Vector2(vx - 60.0, GROUND_Y - 196.0)
	hint.custom_minimum_size = Vector2(120, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 4)
	hint.modulate = Color(1.0, 0.9, 0.4)
	hint.visible = false
	add_child(hint)

	if cleared:
		_add_cancelled_tape(vx)
	_doors.append({"x": vx, "data": data, "cleared": cleared, "hint": hint})


func _add_cancelled_tape(vx: float) -> void:
	var tape := Node2D.new()
	tape.position = Vector2(vx, GROUND_Y - 95.0)
	tape.rotation = deg_to_rad(-8.0)
	tape.z_index = -4
	var band := ColorRect.new()
	band.color = Color(0.93, 0.9, 0.82, 0.95)
	band.size = Vector2(250, 24)
	band.position = Vector2(-125, -12)
	tape.add_child(band)
	var txt := Label.new()
	txt.text = "CANCELLED"
	txt.position = Vector2(-125, -12)
	txt.custom_minimum_size = Vector2(250, 24)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.add_theme_font_size_override("font_size", 16)
	txt.add_theme_color_override("font_color", Color(0.82, 0.08, 0.08))
	tape.add_child(txt)
	add_child(tape)


func _update_door_hints() -> void:
	for d in _doors:
		d.hint.visible = not d.cleared and is_instance_valid(player) \
				and absf(player.position.x - d.x) <= DOOR_HALF_WIDTH


# ---------------------------------------------------------------- spawns
func _spawn_player(pos: Vector2) -> void:
	player = Player.new()
	player.configure(GameState.selected_character_data())
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
	var e := Enemy.new()
	e.configure(GameState.enemy_characters(1)[0])
	e.aggressive = randf() < 0.4
	e.move_speed = randf_range(60.0, 95.0)
	e.score_value = 100
	# Each boss cleared toughens the mob by 10% (health + damage).
	var mult := GameState.enemy_strength_mult()
	e.max_health *= mult
	e.damage_scale *= mult
	e.target = player
	e.position = Vector2(camera.position.x + 380.0, GROUND_Y)
	add_child(e)


func _maybe_spawn_beer(delta: float) -> void:
	if not GameState.beer_unlocked() or GameState.beer_bottles >= GameState.MAX_BOTTLES:
		return
	_beer_timer -= delta
	if _beer_timer > 0.0:
		return
	_beer_timer = randf_range(4.0, 8.0)
	if not is_instance_valid(player) \
			or get_tree().get_nodes_in_group("beer_pickups").size() >= BEER_MAX_ON_SCREEN:
		return
	var pickup := BeerPickup.new()
	pickup.position = Vector2(camera.position.x + randf_range(300.0, 440.0), BEER_GROUND_Y)
	add_child(pickup)


func _cull_stragglers() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.position.x < camera.position.x - 700.0:
			e.queue_free()
	for b in get_tree().get_nodes_in_group("beer_pickups"):
		if b.position.x < camera.position.x - 700.0:
			b.queue_free()


# ---------------------------------------------------------------- events
func _on_player_interact() -> void:
	if _busy or not is_instance_valid(player):
		return
	for i in _doors.size():
		var d: Dictionary = _doors[i]
		if d.cleared or absf(player.position.x - d.x) > DOOR_HALF_WIDTH:
			continue
		_busy = true
		GameState.pending_venue = d.data
		GameState.pending_door = i
		GameState.street_state = _capture_state()
		GameState.enter_venue()
		return


## Snapshot of the street layout so it survives the venue scene swap.
func _capture_state() -> Dictionary:
	var doors: Array = []
	for d in _doors:
		doors.append({"x": d.x, "data": d.data, "cleared": d.cleared})
	return {
		"player_x": player.position.x,
		"next_venue_x": _next_venue_x,
		"venue_index": _venue_index,
		"doors": doors,
	}


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
