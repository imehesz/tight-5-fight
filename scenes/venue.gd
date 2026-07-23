extends Node2D
## The Venue Phase: a static bar interior. Normal venues pit the player
## against N rival comedians (N = venues entered, max 3 at once). Every 3rd
## venue is a Boss Stage: survive the club owner's bottle barrage.

const GROUND_Y := 310.0
const MAX_CONCURRENT := 3
## Entry lanes for same-side spawns. A venue fighter is ~72px wide at
## FIGHTER_SCALE, so 105px keeps bodies clearly apart as they walk in; 3 lanes
## covers the worst case (MAX_CONCURRENT all queued on one side) and cycles.
## (Gap tracks fighter width — bumped with FIGHTER_SCALE's ×1.5 so same-side
## spawns don't overlap into one blob.)
const SPAWN_LANE_GAP := 105.0
const SPAWN_LANES := 3
## Per-enemy walk-speed spread (±%), so a pack drifts apart instead of
## holding formation. Centered on the tuned speed — see _spawn_next_enemy.
const SPEED_VARIANCE := 0.12
const CLEAR_BONUS_PER_LEVEL := 250
## Venue fighters (player + comedians) are drawn bigger than on the street;
## the boss keeps its own scale. 2.2425 = the previous 1.495 bumped ×1.5 for
## readability on every platform (not a mobile-only tweak) — still safe for the
## boss fastball, whose height and duck clearance derive from the player's live
## scale (see Boss._fastball_y). Bigger bodies also grow the fist/kick/mic-stand
## and hurtboxes for free, since those are children of the fighter node.
const FIGHTER_SCALE := 2.2425

var player: Player
var hud: Hud

var _level := 1
var _boss_stage := false
## One boss on the right through the first two boss fights (#2 adds a rival
## comedian on the floor to fight while dodging); from the third on, a
## second owner joins from the LEFT so bottles fly in from both sides.
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
	# Audience silhouettes along the bottom edge; reshuffled each venue. Added
	# after the background (z=-10) and before the fighters so it reads as a
	# foreground crowd (it sets its own z_index). Reacts to GameState.crowd_reaction.
	add_child(CrowdRow.new())
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
		elif ordinal == 2:
			# Boss #2's twist: one rival comedian works the room, so the
			# player fights while dodging bottles. (#1 = pure dodge test,
			# #3+ = double throwers.) KOing them pays score but never ends
			# the stage — only the survive timer does (see _on_enemy_died).
			_to_spawn = GameState.enemy_characters(1)
			_spawn_next_enemy()
		# One bottle on the floor so the stagger is findable with empty
		# pockets. Boss #1 gets none (beer isn't unlocked yet) — that's the
		# designed curve: the first boss stays a pure dodge test.
		if GameState.beer_unlocked():
			var pickup := BeerPickup.new()
			# LIVE viewport width, never a hardcoded 640 (wide-phone rule).
			pickup.position = Vector2(
					get_viewport().get_visible_rect().size.x * 0.4, 300.0)
			add_child(pickup)
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
	e.crowd_cheers = true
	# Base venue scaling, then +10% per boss already cleared. Bases retuned
	# (+15% health, -20% attack cooldown) when the mic-stand swing gave the
	# player a third weapon: less free time inside the swing's 1.5s cooldown.
	var mult := GameState.enemy_strength_mult()
	e.max_health = (63.0 + 12.0 * (_level - 1)) * mult
	e.damage_scale = (0.6 + 0.08 * (_level - 1)) * mult
	# Centered variance, so the average pace (and the difficulty tuning built
	# on it) is unchanged — it only breaks the lockstep that made same-side
	# spawns march in as one blob.
	e.move_speed = minf(85.0 + 4.0 * _level, 130.0) \
			* randf_range(1.0 - SPEED_VARIANCE, 1.0 + SPEED_VARIANCE)
	e.attack_cooldown = maxf(1.05 - 0.05 * _level, 0.5)
	e.score_value = 250 + 50 * _level
	e.target = player
	# Just past the LIVE right edge, so wide phones don't see enemies pop in.
	var off_right := get_viewport().get_visible_rect().size.x + 20.0
	# Sides alternate, so a batch of 3 puts #1 and #3 on the SAME side. Give
	# each successive same-side spawn its own lane further out, or they share
	# an exact start x, walk in at the same speed and read as one fighter.
	var lane := float((_spawned / 2) % SPAWN_LANES) * SPAWN_LANE_GAP
	e.position = Vector2(
			off_right + lane if _spawned % 2 == 0 else -20.0 - lane, GROUND_Y)
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
	# Boss-stage comedian (boss #2): no respawn, and no "venue cleared" —
	# a boss stage only ends when the survive timer runs out.
	if _boss_stage:
		return
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
	GameState.crowd_reaction.emit("celebrate")
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
	GameState.crowd_reaction.emit("celebrate")
	for b in _bosses:
		if is_instance_valid(b):
			b.active = false
	# Boss #2's comedian, if still standing, stops fighting and just mills
	# around during the victory banner.
	for e in get_tree().get_nodes_in_group("enemies"):
		e.aggressive = false
		e.provoked = false
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
	# Boo the knockdown as the player collapses — but only when a respawn is
	# coming (lives > 1 here: lose_life() hasn't decremented yet). The FINAL
	# death gets the cricket/curb stinger instead, never a boo. Venue-only by
	# placement; street.gd's handler deliberately has no crowd.
	if GameState.lives > 1:
		GameState.play_crowd("boo")
		GameState.crowd_reaction.emit("boo")
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
