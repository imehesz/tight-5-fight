extends Node2D
## The Venue Phase: a static bar interior. Normal venues pit the player
## against N rival comedians (N = venues entered, max 3 at once). Every 5th
## venue is a Boss Stage: survive the club owner's bottle barrage.

const GROUND_Y := 310.0
const MAX_CONCURRENT := 3
const CLEAR_BONUS_PER_LEVEL := 250
## Venue fighters (player + comedians) are drawn bigger than on the street;
## the boss keeps its own scale.
const FIGHTER_SCALE := 1.3

var player: Player
var hud: Hud

var _level := 1
var _boss_stage := false
var _boss: Boss
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
	var banner := "%s — VENUE %d" % [String(data.get("VenueName", "???")).to_upper(), _level]
	hud.set_venue_text(banner + ("  !! BOSS !!" if _boss_stage else ""))
	add_child(TouchControls.new())
	_spawn_player()

	if _boss_stage:
		_survive_left = 18.0 + 2.0 * float(_level / GameState.BOSS_EVERY)
		_boss = Boss.new()
		_boss.position = Vector2(540, GROUND_Y)
		_boss.target = player
		_boss.throw_interval = maxf(1.5 - 0.08 * _level, 0.6)
		add_child(_boss)
	else:
		_to_spawn = GameState.enemy_characters(_level)
		for i in mini(MAX_CONCURRENT, _to_spawn.size()):
			_spawn_next_enemy()


func _process(delta: float) -> void:
	if is_instance_valid(player):
		player.position.x = clampf(player.position.x, 30.0, 610.0)
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
	player.position = Vector2(100, GROUND_Y)
	player.died.connect(_on_player_died)
	add_child(player)
	hud.bind_player(player)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.target = player
	if is_instance_valid(_boss):
		_boss.target = player


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
	e.position = Vector2(660 if _spawned % 2 == 0 else -20, GROUND_Y)
	e.died.connect(_on_enemy_died)
	add_child(e)
	_alive += 1
	_spawned += 1


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
	hud.set_center_text("VENUE CLEARED!  +%d" % bonus)
	await get_tree().create_timer(2.0).timeout
	GameState.change_scene(GameState.SCENE_STREET)


func _boss_survived() -> void:
	if _finished:
		return
	_finished = true
	GameState.mark_pending_venue_cleared()
	GameState.on_boss_defeated()  # unlocks beer & toughens the mob by 10%
	GameState.play_sfx("clear")
	if is_instance_valid(_boss):
		_boss.active = false
	for p in get_tree().get_nodes_in_group("projectiles"):
		p.queue_free()
	var bonus := 2 * CLEAR_BONUS_PER_LEVEL * _level
	GameState.add_score(bonus)
	hud.set_center_text("YOU SURVIVED!  +%d" % bonus)
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
