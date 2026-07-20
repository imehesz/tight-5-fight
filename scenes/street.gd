extends Node2D
## The Street Phase: infinite scrolling street with random hecklers and
## periodically spawning venues. Walk to a venue door and press up to enter.

const GROUND_Y := 310.0
const TILE_W := 320.0
const TILE_COUNT := 5
## Past the opening camera view (which ends at x=640), so the first door
## never pops in mid-screen — far enough for a short walk (and the opening
## heckler brawl), near enough that a new player is brawling inside a venue
## within ~30 s. Tuned by feel: 900 dragged, 650 was too close.
const FIRST_VENUE_X := 750.0
const VENUE_SPACING_MIN := 1100.0
const VENUE_SPACING_MAX := 1600.0
const DOOR_HALF_WIDTH := 34.0
const EXTERIOR_HEIGHT := 180.0
## Neon ENTER sign floating above every enterable venue: resting height,
## bob travel, and its tube/glow colors. It brightens when the player is
## in range of the door, replacing the old proximity-only "^ ENTER" label.
const SIGN_Y := GROUND_Y - 204.0
const SIGN_BOB := 4.0
const SIGN_NEON := Color(1.0, 0.35, 0.8)
const SIGN_TEXT := Color(1.0, 0.72, 0.95)
const SIGN_DIM := Color(0.62, 0.62, 0.7)
## Run-start "FIND A VENUE" hint sign: on screen this long, then fades.
const HINT_S := 4.0
const HECKLER_MAX := 4
## Street fighters (player + hecklers) sit between the old 1.0 street size
## and the venue's 1.3 — readable on phones without crowding the scroll.
const FIGHTER_SCALE := 1.25
## Beer bottles rest slightly above the fighters' feet; at most a couple lie
## on the visible street at once so they read as a treat, not litter.
const BEER_GROUND_Y := 300.0
const BEER_MAX_ON_SCREEN := 2
## Banner-plane flybys (games with planeBanners in their manifest only): the
## first shows up early so it's easy to spot, then they stay an occasional treat.
const PLANE_FIRST_WAIT_MAX := 12.0
const PLANE_WAIT_MIN := 18.0
const PLANE_WAIT_MAX := 40.0

var player: Player
var camera: Camera2D
var hud: Hud

var _tiles: Array = []
var _doors: Array = []  # [{x, data, cleared, sign}]
var _next_venue_x := FIRST_VENUE_X
var _venue_index := 0
var _spawn_timer := 2.0
## The run's opening heckler is guaranteed hostile, so combat gets
## demonstrated immediately; cleared once spent (or on a restored street).
var _first_heckler := true
var _beer_timer := 3.0
var _plane_timer := randf_range(4.0, PLANE_FIRST_WAIT_MAX)
var _plane: PlaneFlyby
var _hint_sign: Node2D
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
	# Auto-disconnected when this scene is freed; no manual cleanup needed.
	GameState.shake_requested.connect(_on_shake)

	var saved: Dictionary = GameState.street_state
	if saved.has("doors"):
		# Returning from a venue: rebuild the street exactly as it was.
		_next_venue_x = float(saved.next_venue_x)
		_venue_index = int(saved.venue_index)
		for d in saved.doors:
			_add_venue(float(d.x), d.data, bool(d.cleared))
		_spawn_player(Vector2(float(saved.player_x), GROUND_Y))
		# Mid-run pacing is untouched: no fast spawn, no forced aggression.
		_first_heckler = false
	else:
		_spawn_player(Vector2(120, GROUND_Y))
		_spawn_timer = 0.5  # first heckler shows up almost immediately
		# Goal hint, only at the very start of a run — venues_entered, not
		# "fresh street", so walking back out of venue 1 stays hint-free.
		if GameState.venues_entered == 0:
			_spawn_hint_sign()
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
	_maybe_spawn_plane(delta)
	_cull_stragglers()
	_update_door_signs()


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

	var sign := _make_enter_sign()
	sign.position = Vector2(vx, SIGN_Y)
	sign.visible = not cleared
	add_child(sign)

	if cleared:
		_add_cancelled_tape(vx)
	_doors.append({"x": vx, "data": data, "cleared": cleared, "sign": sign})


## A little neon box sign: dark panel framed by a pink "tube" border, the
## text glowing inside via a heavy same-hue outline. Origin is the panel's
## center, so callers place it and bob it.
func _make_neon_sign(text: String, panel_w: float) -> Node2D:
	var sign := Node2D.new()
	sign.z_index = -4

	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.12, 0.92)
	style.border_color = SIGN_NEON
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	panel.size = Vector2(panel_w, 24)
	panel.position = Vector2(-panel_w / 2.0, -12)
	sign.add_child(panel)

	var txt := Label.new()
	txt.text = text
	txt.set_anchors_preset(Control.PRESET_FULL_RECT)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.add_theme_font_size_override("font_size", 10)
	txt.add_theme_color_override("font_color", SIGN_TEXT)
	txt.add_theme_color_override("font_outline_color", SIGN_NEON)
	txt.add_theme_constant_override("outline_size", 4)
	panel.add_child(txt)
	return sign


func _make_enter_sign() -> Node2D:
	var sign := _make_neon_sign("ENTER", 76.0)
	# Arrow under the box pointing down at the door: a pink tube triangle
	# with the same hot core the lettering has. Children of the sign, so it
	# bobs and dims/brightens with it.
	var tube := Polygon2D.new()
	tube.polygon = PackedVector2Array([Vector2(-9, 14), Vector2(9, 14), Vector2(0, 26)])
	tube.color = SIGN_NEON
	sign.add_child(tube)
	var core := Polygon2D.new()
	core.polygon = PackedVector2Array([Vector2(-5, 16), Vector2(5, 16), Vector2(0, 22)])
	core.color = SIGN_TEXT
	sign.add_child(core)
	return sign


## The run-start goal hint, wearing the exact ENTER-sign look (same neon
## panel recipe, same bob) with the arrow tube pointing right, down the
## street toward the first venue. World-fixed in the opening camera view at
## the venue signs' height; fades out after HINT_S.
func _spawn_hint_sign() -> void:
	_hint_sign = _make_neon_sign("FIND A VENUE", 144.0)
	var half_w := 72.0
	var tube := Polygon2D.new()
	tube.polygon = PackedVector2Array([
		Vector2(half_w + 4, -9), Vector2(half_w + 4, 9), Vector2(half_w + 16, 0)])
	tube.color = SIGN_NEON
	_hint_sign.add_child(tube)
	var core := Polygon2D.new()
	core.polygon = PackedVector2Array([
		Vector2(half_w + 6, -5), Vector2(half_w + 6, 5), Vector2(half_w + 12, 0)])
	core.color = SIGN_TEXT
	_hint_sign.add_child(core)
	_hint_sign.position = Vector2(320.0, SIGN_Y)
	add_child(_hint_sign)
	# Captured as a local: the player can enter a venue (freeing this scene)
	# before the timer fires, and the lambda must not touch freed members.
	var sign := _hint_sign
	get_tree().create_timer(HINT_S).timeout.connect(func():
		if is_instance_valid(sign):
			var tw: Tween = sign.create_tween()
			tw.tween_property(sign, "modulate:a", 0.0, 0.4)
			tw.tween_callback(sign.queue_free))


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


## Bob every active venue's sign up and down (phase-offset by its x so
## neighbours don't march in lockstep) and brighten the one whose door the
## player is standing at — the proximity cue the old hint label used to give.
func _update_door_signs() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	# The hint sign bobs on the same wave as the venue signs (always at full
	# ENTER-sign brightness — it IS the call to action, no door to be near).
	if is_instance_valid(_hint_sign):
		_hint_sign.position.y = SIGN_Y + sin(t * 4.0 + _hint_sign.position.x) * SIGN_BOB
	for d in _doors:
		var sign: Node2D = d.sign
		if d.cleared:
			sign.visible = false
			continue
		sign.position.y = SIGN_Y + sin(t * 4.0 + float(d.x)) * SIGN_BOB
		var near: bool = is_instance_valid(player) \
				and absf(player.position.x - d.x) <= DOOR_HALF_WIDTH
		sign.modulate = sign.modulate.lerp(Color.WHITE if near else SIGN_DIM, 0.2)


# ---------------------------------------------------------------- spawns
func _spawn_player(pos: Vector2) -> void:
	player = Player.new()
	player.configure(GameState.selected_character_data())
	player.size_scale = FIGHTER_SCALE
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
	e.size_scale = FIGHTER_SCALE
	# Once the first boss is down the street turns on you: more hecklers
	# start fights (40% -> 60%) and they walk 10% faster.
	var post_boss := GameState.bosses_defeated > 0
	e.aggressive = randf() < (0.6 if post_boss else 0.4)
	if _first_heckler:
		e.aggressive = true
		_first_heckler = false
	e.move_speed = randf_range(60.0, 95.0) * (1.1 if post_boss else 1.0)
	e.score_value = 100
	# Each boss cleared toughens the mob by 10% (health + damage).
	var mult := GameState.enemy_strength_mult()
	e.max_health *= mult
	e.damage_scale *= mult
	e.target = player
	# Just past the LIVE right edge (the camera is centered): aspect="expand"
	# makes phones wider than the 640 design, so a fixed +380 offset (design
	# half-width 320 + 60) landed hecklers ON-SCREEN there, right of middle.
	e.position = Vector2(
			camera.position.x + get_viewport_rect().size.x / 2.0 + 60.0, GROUND_Y)
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
	# Same live-edge rule as the heckler spawn: 20-140px past whatever the
	# phone's real right edge is, so bottles never pop into view either.
	pickup.position = Vector2(
			camera.position.x + get_viewport_rect().size.x / 2.0 + randf_range(20.0, 140.0),
			BEER_GROUND_Y)
	add_child(pickup)


## One plane at a time, in world space (so player movement never alters its
## flight) and freed with the street: plane + engine drone vanish on entering
## a venue.
func _maybe_spawn_plane(delta: float) -> void:
	if is_instance_valid(_plane):
		return
	_plane_timer -= delta
	if _plane_timer > 0.0:
		return
	_plane_timer = randf_range(PLANE_WAIT_MIN, PLANE_WAIT_MAX)
	var banners: Array = GameState.plane_banners()
	if banners.is_empty():
		return
	_plane = PlaneFlyby.new()
	_plane.banner_text = String(banners.pick_random())
	_plane.camera = camera
	add_child(_plane)


func _cull_stragglers() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.position.x < camera.position.x - 700.0:
			e.queue_free()
	for b in get_tree().get_nodes_in_group("beer_pickups"):
		if b.position.x < camera.position.x - 700.0:
			b.queue_free()


## Screen shake: MUST tween camera.offset, never camera.position — _process
## overwrites position with the camera-follow code every frame. If a second
## shake arrives mid-shake the new tween simply wins; both end at ZERO.
func _on_shake(px: float) -> void:
	var tw := create_tween()
	for i in 4:
		tw.tween_property(camera, "offset",
				Vector2(randf_range(-px, px), randf_range(-px, px)), 0.04)
	tw.tween_property(camera, "offset", Vector2.ZERO, 0.04)


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
