extends Node2D
## The Venue Phase: a static bar interior. Normal venues pit the player
## against N rival comedians (N = venues entered, max 3 at once). Every 3rd
## venue is a Boss Stage: survive the club owner's bottle barrage.

const GROUND_Y := 310.0
const MAX_CONCURRENT := 3
const CLEAR_BONUS_PER_LEVEL := 250
## Venue fighters (player + comedians) are drawn bigger than on the street;
## the boss keeps its own scale. 1.495 = the old 1.3 bumped 15% for phone
## readability — safe for the boss fastball, whose height and duck clearance
## derive from the player's live scale (see Boss._fastball_y).
const FIGHTER_SCALE := 1.495

var player: Player
var hud: Hud

var _level := 1
var _boss_stage := false
## One boss on the right through the first two boss fights; from the third
## on, a second owner joins from the LEFT so bottles fly in from both sides.
var _bosses: Array[Boss] = []
var _to_spawn: Array = []
var _alive := 0
var _spawned := 0
var _survive_left := 0.0
var _finished := false


func _ready() -> void:
	_level = maxi(GameState.venues_entered, 1)
	_boss_stage = GameState.is_boss_venue()
	var data: Dictionary = GameState.pending_venue \
			if not GameState.pending_venue.is_empty() else GameState.current_venue_data()
	GameState.pending_venue = {}

	_build_background(data)
	hud = Hud.new()
	add_child(hud)
	# No venue name: the interior art has it painted on already.
	var banner := "VENUE %d" % _level
	hud.set_venue_text(banner + ("  !! BOSS !!" if _boss_stage else ""))
	add_child(TouchControls.new())
	# Auto-disconnected when this scene is freed; no manual cleanup needed.
	GameState.shake_requested.connect(_on_shake)
	_spawn_player()

	if _boss_stage:
		var ordinal := _level / GameState.BOSS_EVERY
		# 15s for the first boss, +2s per boss after (was 20s — too long).
		_survive_left = 13.0 + 2.0 * float(ordinal)
		# 100px in from the live right edge (640-540 in the design layout).
		_spawn_boss(get_viewport().get_visible_rect().size.x - 100.0, 2.0)
		if ordinal >= 3:
			# Second thrower, offset timers so the pair don't fire in sync.
			_spawn_boss(100.0, 3.2)
	else:
		_to_spawn = GameState.enemy_characters(_level)
		for i in mini(MAX_CONCURRENT, _to_spawn.size()):
			_spawn_next_enemy()


func _process(delta: float) -> void:
	if is_instance_valid(player):
		# The room spans the LIVE view width (the bg stretches to it), not the
		# 640 design width — clamping to 610 walled off wide phones mid-screen.
		var right := get_viewport().get_visible_rect().size.x - 30.0
		player.position.x = clampf(player.position.x, 30.0, right)
	if _boss_stage and not _finished:
		_survive_left -= delta
		hud.set_center_text("SURVIVE %d" % maxi(ceili(_survive_left), 0))
		if _survive_left <= 0.0:
			_boss_survived()


# ---------------------------------------------------------------- setup
func _build_background(data: Dictionary) -> void:
	var view := get_viewport().get_visible_rect().size
	var path := String(data.get("InteriorSpritePath", ""))
	if ResourceLoader.exists(path):
		var bg := Sprite2D.new()
		bg.texture = load(path)
		bg.centered = false
		# Stretch the 640x360 art to the device's visible size — phones wider
		# than 16:9 expand the viewport (stretch/aspect="expand").
		bg.scale = view / bg.texture.get_size()
		bg.z_index = -10
		add_child(bg)
	else:
		var rect := ColorRect.new()
		rect.color = Color(0.2, 0.1, 0.15)
		rect.size = view
		rect.z_index = -10
		add_child(rect)


func _spawn_player() -> void:
	player = Player.new()
	player.configure(GameState.selected_character_data())
	player.size_scale = FIGHTER_SCALE
	# Double-boss stages have a thrower at x=100, so spawn (and respawn)
	# mid-floor there instead of inside him.
	var px := 100.0
	if _boss_stage and _level / GameState.BOSS_EVERY >= 3:
		px = get_viewport().get_visible_rect().size.x / 2.0
	player.position = Vector2(px, GROUND_Y)
	player.died.connect(_on_player_died)
	add_child(player)
	hud.bind_player(player)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.target = player
	for b in _bosses:
		if is_instance_valid(b):
			b.target = player


func _spawn_boss(x: float, first_throw: float) -> void:
	var boss := Boss.new()
	boss.position = Vector2(x, GROUND_Y)
	boss.target = player
	boss.throw_interval = maxf(1.5 - 0.08 * _level, 0.6)
	# Stagger the opening throw (and taunt) per boss: Boss defaults both
	# timers, so a same-frame pair would fire in lockstep all fight.
	boss._throw_left = first_throw
	boss._taunt_left = first_throw + 1.0
	add_child(boss)
	_bosses.append(boss)


func _spawn_next_enemy() -> void:
	if _to_spawn.is_empty():
		return
	var e := Enemy.new()
	e.configure(_to_spawn.pop_front())
	e.size_scale = FIGHTER_SCALE
	e.aggressive = true  # venue comedians always attack immediately
	# Base venue scaling, then +10% per boss already cleared.
	var mult := GameState.enemy_strength_mult()
	e.max_health = (55.0 + 12.0 * (_level - 1)) * mult
	e.damage_scale = (0.6 + 0.08 * (_level - 1)) * mult
	e.move_speed = minf(85.0 + 4.0 * _level, 130.0)
	e.attack_cooldown = maxf(1.3 - 0.05 * _level, 0.6)
	e.score_value = 250 + 50 * _level
	e.target = player
	# Just past the LIVE right edge, so wide phones don't see enemies pop in.
	var off_right := get_viewport().get_visible_rect().size.x + 20.0
	e.position = Vector2(off_right if _spawned % 2 == 0 else -20, GROUND_Y)
	e.died.connect(_on_enemy_died)
	add_child(e)
	_alive += 1
	_spawned += 1


## Screen shake: no Camera2D in the venue (static room), so bump the scene
## root instead. The HUD and touch controls are CanvasLayers and correctly
## stay still. A second shake mid-shake just wins; both end at ZERO.
func _on_shake(px: float) -> void:
	var tw := create_tween()
	for i in 4:
		tw.tween_property(self, "position",
				Vector2(randf_range(-px, px), randf_range(-px, px)), 0.04)
	tw.tween_property(self, "position", Vector2.ZERO, 0.04)


# ---------------------------------------------------------------- outcomes
func _on_enemy_died(_f: Fighter) -> void:
	_alive -= 1
	if not _to_spawn.is_empty():
		await get_tree().create_timer(1.0).timeout
		if not _finished:
			_spawn_next_enemy()
	elif _alive <= 0:
		_venue_cleared()


func _venue_cleared() -> void:
	if _finished:
		return
	_finished = true
	GameState.mark_pending_venue_cleared()
	GameState.play_sfx("clear")
	var bonus := CLEAR_BONUS_PER_LEVEL * _level
	GameState.add_score(bonus)
	hud.set_center_text("VENUE BATTLED!  +%d" % bonus)
	await get_tree().create_timer(2.0).timeout
	GameState.change_scene(GameState.SCENE_STREET)


func _boss_survived() -> void:
	if _finished:
		return
	_finished = true
	GameState.mark_pending_venue_cleared()
	# One defeat banked PER BOSS in the room — a double-boss stage counts 2
	# (BOSSES tally, +10% mob toughness each, and up to one life each).
	var lives_granted := 0
	for b in _bosses:
		if GameState.on_boss_defeated():
			lives_granted += 1
	GameState.play_sfx("clear")
	for b in _bosses:
		if is_instance_valid(b):
			b.active = false
	for p in get_tree().get_nodes_in_group("projectiles"):
		p.queue_free()
	var bonus := 2 * CLEAR_BONUS_PER_LEVEL * _level
	GameState.add_score(bonus)
	var life_note := ""
	if lives_granted == 1:
		life_note = "  +1 LIFE"
	elif lives_granted > 1:
		life_note = "  +%d LIVES" % lives_granted
	hud.set_center_text("YOU SURVIVED!  +%d%s" % [bonus, life_note])
	await get_tree().create_timer(2.0).timeout
	GameState.change_scene(GameState.SCENE_STREET)


func _on_player_died(_f: Fighter) -> void:
	await get_tree().create_timer(1.4).timeout
	if _finished:
		return
	var corpse := player
	if GameState.lose_life():
		GameState.finish_run()
		return
	if is_instance_valid(corpse):
		corpse.queue_free()
	_spawn_player()
