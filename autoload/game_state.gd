extends Node
## Global game state singleton (registered as "GameState" in Project Settings > Globals).
## Tracks score, lives, selected character, venue difficulty, high scores and settings.

signal score_changed(new_score: int)
signal lives_changed(new_lives: int)
signal bottles_changed(new_count: int)
signal bosses_changed(new_count: int)

const SCENE_SPLASH := "res://scenes/splash.tscn"
const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"
const SCENE_CHARACTER_SELECT := "res://scenes/character_select.tscn"
const SCENE_SETTINGS := "res://scenes/settings_menu.tscn"
const SCENE_SCOREBOARD := "res://scenes/scoreboard.tscn"
const SCENE_ABOUT := "res://scenes/about.tscn"
const SCENE_STREET := "res://scenes/street.tscn"
const SCENE_VENUE := "res://scenes/venue.tscn"
const SCENE_GAME_OVER := "res://scenes/game_over.tscn"

## Names the game this build ships (see games/<id>/). The build step writes it;
## for local dev you may hand-edit it to switch which game you're testing.
const ACTIVE_GAME_PATH := "res://data/active_game.json"

## App version. The build stamp after it is baked into VERSION_PATH at deploy.
const APP_VERSION := "1.0"
const VERSION_PATH := "res://data/version.txt"

## Shared engine fallbacks, used when a game manifest omits an optional asset.
const DEFAULT_BODY := {
	"M": "res://shared/assets/bodies/body_male.png",
	"F": "res://shared/assets/bodies/body_female.png",
}

## Save files are namespaced per active game (%s = active game id) so two games
## deployed under one origin never stomp each other's high scores/settings.
const SCORES_PATH := "user://%s_highscores.json"
const SETTINGS_PATH := "user://%s_settings.json"

## The local board keeps a deep history (paged 10 at a time on the
## scoreboard); only cracking the top few is worth a fanfare on game over.
const MAX_HIGH_SCORES := 50
const CELEBRATED_HIGH_SCORES := 10
## Every 3rd venue is a boss (was 5 — pulled in 2026-07-10 so a first-time
## player meets the signature moment, and the beer unlock behind it, within
## one casual session).
const BOSS_EVERY := 3
## Beer bottles the player can carry (unlocked after the first boss). They
## are picked up on the street and thrown at hecklers; venues bar them at
## the door but the carried count is kept for when the player comes back out.
const MAX_BOTTLES := 3
## Each boss cleared makes every future enemy 10% stronger (health + damage).
const STRENGTH_PER_BOSS := 0.10

## Looping background tracks come from the active game's manifest (main +
## venue). SFX are shared engine chrome. See _music_tracks()/_setup_audio().
const SFX_BASE := "res://shared/assets/sfx/sfx_"
const SFX_NAMES := ["punch", "kick", "hurt", "defeat", "smash", "clear", "click", "throw"]
const SFX_POOL_SIZE := 6

## The active game id and its parsed game.json manifest. Loaded first in
## _ready() from data/active_game.json; everything game-specific reads from here.
var active_game := "tight5"
var manifest: Dictionary = {}
var _scores_file := ""
var _settings_file := ""

var characters: Array = []
var venues: Array = []
var selected_character := 0
var score := 0
var lives := 1
var venues_entered := 0
## Bosses cleared so far, and beer bottles currently carried (0..MAX_BOTTLES).
var bosses_defeated := 0
var beer_bottles := 0
var pending_venue: Dictionary = {}
## Street layout persisted across venue visits (see street.gd) and the index
## of the door being entered, so it can be marked CANCELLED once cleared.
var street_state: Dictionary = {}
var pending_door := -1
var high_scores: Array = []
var last_run_rank := -1
## Enemies KO'd this run, roster name -> count. Shipped with the play at game
## over (Leaderboard.record_play) to feed the global MOST BEAT UP board.
var run_kos: Dictionary = {}
## Venues entered this run, venue name -> count. Ships alongside run_kos to
## feed the global VENUES board. The same name can recur: the street cycles
## the venue list, so a deep run walks past The Giggle Shack more than once.
var run_venues: Dictionary = {}
var music_volume := 0.8
var sfx_volume := 0.8
## Player's chosen outfit color (index into CharacterFactory.OUTFITS). Worn on
## whichever body the picked comedian has; NPCs keep their baked colors.
var outfit := 0

var _music_player: AudioStreamPlayer
var _music_streams := {}
var _music_track := ""
var _sfx_streams := {}
var _sfx_pool: Array = []
var _sfx_next := 0


func _ready() -> void:
	randomize()
	_register_input_actions()
	_load_active_game()
	get_window().title = game_title()
	_load_roster()
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_load_settings()
	_load_scores()
	_setup_audio()


# ---------------------------------------------------------------- active game
## Resolve which game this build is, load its manifest, and derive save paths.
func _load_active_game() -> void:
	active_game = String(_load_json(ACTIVE_GAME_PATH).get("active", "tight5"))
	manifest = _load_json(game_path("game.json"))
	_scores_file = SCORES_PATH % active_game
	_settings_file = SETTINGS_PATH % active_game


## Prefix a game-relative path (as stored in game.json / characters.json /
## venues.json) with this build's game folder. The one place game ids turn into
## res:// paths — engine code never hardcodes res://games/... itself.
func game_path(rel: String) -> String:
	return "res://games/%s/%s" % [active_game, rel]


## Load roster + venues, resolving their game-relative sprite paths to absolute
## res:// paths up front so every downstream consumer keeps working unchanged.
func _load_roster() -> void:
	var chars: Array = _load_json(game_path(String(manifest.get("characters", "characters.json")))).get("characters", [])
	for c in chars:
		if String(c.get("HeadSpritePath", "")) != "":
			c["HeadSpritePath"] = game_path(String(c["HeadSpritePath"]))
	characters = chars
	var vs: Array = _load_json(game_path(String(manifest.get("venues", "venues.json")))).get("venues", [])
	for v in vs:
		for k in ["ExteriorSpritePath", "InteriorSpritePath"]:
			if String(v.get(k, "")) != "":
				v[k] = game_path(String(v[k]))
	venues = vs


# ---------------------------------------------------------------- manifest resolvers
## Manifest value if present (resolved game-relative), else the shared default.
func _bg_path(key: String, fallback_rel: String) -> String:
	var bgs: Dictionary = manifest.get("backgrounds", {})
	return game_path(String(bgs.get(key, fallback_rel)))


func game_title() -> String:
	return String(manifest.get("title", "Beat the Streets"))


func menu_title() -> String:
	return String(manifest.get("menuTitle", game_title()))


## "v.1.0.<build stamp>" shown faintly in Settings. In the editor the stamp is
## the current time (you're running live code); in an exported/deployed build
## it's the timestamp the deploy script bakes into data/version.txt, so you can
## confirm at a glance that a build is fresh and not a cached old one.
func version_string() -> String:
	var stamp := ""
	if OS.has_feature("editor"):
		var t := Time.get_datetime_dict_from_system()
		stamp = "%04d%02d%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute]
	elif FileAccess.file_exists(VERSION_PATH):
		var f := FileAccess.open(VERSION_PATH, FileAccess.READ)
		if f:
			stamp = f.get_as_text().strip_edges()
	if stamp == "":
		stamp = "dev"
	return "v.%s.%s" % [APP_VERSION, stamp]


func splash_path() -> String:
	return _bg_path("splash", "assets/backgrounds/splash.png")


func menu_bg_path() -> String:
	return _bg_path("menu", "assets/backgrounds/menu_bg.png")


func street_tile_path() -> String:
	return _bg_path("streetTile", "assets/backgrounds/street_tile.png")


## Optional assets: empty string means "no override" — the consumer applies its
## own placeholder (boss/projectile) rather than crashing on a missing file.
func boss_head_path() -> String:
	var boss: Dictionary = manifest.get("boss", {})
	var p = boss.get("headSprite", null)
	return game_path(String(p)) if p != null and String(p) != "" else ""


func projectile_path() -> String:
	var p = manifest.get("projectileSprite", null)
	return game_path(String(p)) if p != null and String(p) != "" else ""


## Body sheet for M/F, honouring a manifest override, else the shared default.
func body_path(body_type: String) -> String:
	var ov: Dictionary = manifest.get("overrides", {})
	var key := "bodyMale" if body_type == "M" else "bodyFemale"
	var p = ov.get(key, null)
	if p != null and String(p) != "":
		return game_path(String(p))
	return DEFAULT_BODY.get(body_type, DEFAULT_BODY["M"])


## Looping tracks from the manifest; a game may omit either (or both).
func _music_tracks() -> Dictionary:
	var audio: Dictionary = manifest.get("audio", {})
	var tracks := {}
	if String(audio.get("musicMain", "")) != "":
		tracks["main"] = game_path(String(audio["musicMain"]))
	if String(audio.get("musicVenue", "")) != "":
		tracks["venue"] = game_path(String(audio["musicVenue"]))
	return tracks


# ---------------------------------------------------------------- run lifecycle
func start_new_game(character_index: int) -> void:
	set_selected_character(character_index)
	score = 0
	venues_entered = 0
	bosses_defeated = 0
	lives = lives_cap()  # after bosses_defeated resets, so a run starts at 1
	set_bottles(0)
	pending_venue = {}
	street_state = {}
	pending_door = -1
	last_run_rank = -1
	run_kos = {}
	run_venues = {}
	change_scene(SCENE_STREET)


func enter_venue() -> void:
	venues_entered += 1
	var venue_name := String(pending_venue.get("VenueName", ""))
	if venue_name != "":
		run_venues[venue_name] = int(run_venues.get(venue_name, 0)) + 1
	change_scene(SCENE_VENUE)


func is_boss_venue() -> bool:
	return venues_entered > 0 and venues_entered % BOSS_EVERY == 0


# ---------------------------------------------------------------- beer bottles
## The beer-throwing mechanic unlocks once the first boss has been beaten.
func beer_unlocked() -> bool:
	return bosses_defeated > 0


## Lives are earned, not given: a run opens with 1, surviving the first boss
## raises the ceiling to 2, the second boss to 3 — and it stays 3 from there.
## Death comes fast early (game over IS the show), depth is the reward.
func lives_cap() -> int:
	if bosses_defeated < 1:
		return 1
	if bosses_defeated < 2:
		return 2
	return 3


## Called by the venue when a boss is survived: banks the win so the beer
## mechanic unlocks and every future enemy gets tougher, and grants ONE life
## if under the (possibly just-raised) ceiling — lives lost on the way to a
## boss stay lost; a win is a reward, not a reset. Returns true when a life
## was granted, so the venue can celebrate it on the HUD.
func on_boss_defeated() -> bool:
	bosses_defeated += 1
	bosses_changed.emit(bosses_defeated)
	if lives < lives_cap():
		lives += 1
		lives_changed.emit(lives)
		return true
	return false


## Enemy health/damage multiplier: +10% per boss cleared (1.0, 1.1, 1.21…).
func enemy_strength_mult() -> float:
	return pow(1.0 + STRENGTH_PER_BOSS, bosses_defeated)


func set_bottles(n: int) -> void:
	var clamped := clampi(n, 0, MAX_BOTTLES)
	if clamped == beer_bottles:
		return
	beer_bottles = clamped
	bottles_changed.emit(beer_bottles)


## Try to pick one up; returns false (leave it on the ground) when already full.
func add_bottle() -> bool:
	if beer_bottles >= MAX_BOTTLES:
		return false
	set_bottles(beer_bottles + 1)
	return true


func use_bottle() -> bool:
	if beer_bottles <= 0:
		return false
	set_bottles(beer_bottles - 1)
	return true


## Called by the venue scene on victory: the door the player entered through
## gets taped over and can't be entered again.
func mark_pending_venue_cleared() -> void:
	var doors: Array = street_state.get("doors", [])
	if pending_door >= 0 and pending_door < doors.size():
		doors[pending_door]["cleared"] = true
	pending_door = -1


func add_score(points: int) -> void:
	score += points
	score_changed.emit(score)


## Bank one KO for the beaten-up comedian. Enemy._die() calls this; a fighter
## never configured from the roster has no name and is not counted.
func count_ko(char_name: String) -> void:
	if char_name != "":
		run_kos[char_name] = int(run_kos.get(char_name, 0)) + 1


## Returns true when the run is over (no lives left).
func lose_life() -> bool:
	lives -= 1
	lives_changed.emit(lives)
	return lives <= 0


func finish_run() -> void:
	last_run_rank = _record_score()
	# Banks this character's play on the global board. Deliberately not
	# awaited: it outlives the scene change (Leaderboard is an autoload) and
	# a failure must never stall or block game over.
	Leaderboard.record_play()
	change_scene(SCENE_GAME_OVER)


func change_scene(path: String) -> void:
	play_music("venue" if path == SCENE_VENUE else "main")
	get_tree().call_deferred("change_scene_to_file", path)


# ---------------------------------------------------------------- data access
func selected_character_data() -> Dictionary:
	if characters.is_empty():
		return {"CharacterName": "Nobody", "HeadSpritePath": "", "BodyType": "M"}
	return characters[clampi(selected_character, 0, characters.size() - 1)]


## Roster position of a comedian by name, or 0 — the first — when the name is
## unknown. That covers a player who has never picked, and a saved favorite
## since renamed or dropped from characters.json.
func character_index_by_name(char_name: String) -> int:
	for i in characters.size():
		if String(characters[i].get("CharacterName", "")) == char_name:
			return i
	return 0


## Random enemy configs pulled from the roster, excluding the player's pick.
func enemy_characters(count: int) -> Array:
	var pool: Array = []
	for i in characters.size():
		if i != selected_character:
			pool.append(characters[i])
	if pool.is_empty():
		pool = [selected_character_data()]
	var picks: Array = []
	for i in count:
		picks.append(pool[randi() % pool.size()])
	return picks


func venue_data_for_index(i: int) -> Dictionary:
	if venues.is_empty():
		return {"VenueName": "The Void", "ExteriorSpritePath": "", "InteriorSpritePath": ""}
	return venues[i % venues.size()]


func current_venue_data() -> Dictionary:
	return venue_data_for_index(maxi(venues_entered - 1, 0))


# ---------------------------------------------------------------- audio
func _setup_audio() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	var tracks := _music_tracks()
	for track in tracks:
		var s := _load_stream(tracks[track])
		if s:
			_set_looping(s)
			_music_streams[track] = s
	play_music("main")
	for sfx_name in SFX_NAMES:
		var s := _load_stream(SFX_BASE + sfx_name)
		if s:
			_sfx_streams[sfx_name] = s
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)


## Swap the looping background track; no-op if it's already playing (so
## menu-to-menu transitions never restart the tune) or the file is missing.
func play_music(track: String) -> void:
	if track == _music_track or not _music_streams.has(track):
		return
	_music_track = track
	_music_player.stream = _music_streams[track]
	_music_player.play()


func play_sfx(sfx_name: String) -> void:
	if not _sfx_streams.has(sfx_name):
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = _sfx_streams[sfx_name]
	p.play()


func _load_stream(base_path: String) -> AudioStream:
	for ext in [".ogg", ".mp3", ".wav"]:
		if ResourceLoader.exists(base_path + ext):
			return load(base_path + ext)
	return null


func _set_looping(s: AudioStream) -> void:
	if s is AudioStreamMP3 or s is AudioStreamOggVorbis:
		s.loop = true
	elif s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.data.size() / (2.0 * (2 if s.stereo else 1)))


# ---------------------------------------------------------------- settings
func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_volume("Music", music_volume)
	_save_settings()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_volume("SFX", sfx_volume)
	_save_settings()


## Remembered across reloads, so the roster opens on your usual comedian.
func set_selected_character(idx: int) -> void:
	var i := clampi(idx, 0, maxi(characters.size() - 1, 0))
	if i == selected_character:
		return  # don't rewrite the save file just for opening a menu
	selected_character = i
	_save_settings()


func set_outfit(idx: int) -> void:
	# Never OUTFIT_BAKED: the player always wears a color they picked.
	outfit = clampi(idx, 0, CharacterFactory.OUTFITS.size() - 1)
	_save_settings()


## A random outfit for an NPC — never the player's, so you can always pick
## yourself out of the brawl.
func random_enemy_outfit() -> int:
	var n: int = CharacterFactory.OUTFITS.size()
	if n <= 1:
		return 0
	# Draw from the n-1 colors that aren't the player's, then step over theirs.
	var i := randi() % (n - 1)
	return i if i < outfit else i + 1


func _apply_volume(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))
	AudioServer.set_bus_mute(idx, v <= 0.001)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func _load_settings() -> void:
	var d := _load_json(_settings_file)
	music_volume = clampf(float(d.get("music", 0.8)), 0.0, 1.0)
	sfx_volume = clampf(float(d.get("sfx", 0.8)), 0.0, 1.0)
	outfit = clampi(int(d.get("outfit", 0)), 0, CharacterFactory.OUTFITS.size() - 1)
	# Stored by name, not position, so the favorite survives characters.json
	# being reordered — or the roster being shuffled again. Older saves held a
	# roster index here; those orderings are gone, so anything but a name
	# falls back to the first comedian (and is rewritten on the next save).
	var saved_name: Variant = d.get("character", "")
	selected_character = character_index_by_name(saved_name) if saved_name is String else 0
	_apply_volume("Music", music_volume)
	_apply_volume("SFX", sfx_volume)


func _save_settings() -> void:
	_save_json(_settings_file, {
		"music": music_volume,
		"sfx": sfx_volume,
		"outfit": outfit,
		"character": "" if characters.is_empty() \
				else String(selected_character_data().get("CharacterName", "")),
	})


# ---------------------------------------------------------------- high scores
func _record_score() -> int:
	var entry := {
		"score": score,
		"venue": venues_entered,
		"character": String(selected_character_data().get("CharacterName", "?")),
		"date": Time.get_date_string_from_system(),
	}
	high_scores.append(entry)
	high_scores.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	var rank := high_scores.find(entry)
	if high_scores.size() > MAX_HIGH_SCORES:
		high_scores.resize(MAX_HIGH_SCORES)
	_save_scores()
	return rank if rank < MAX_HIGH_SCORES else -1


func _load_scores() -> void:
	high_scores = _load_json(_scores_file).get("scores", [])


func _save_scores() -> void:
	_save_json(_scores_file, {"scores": high_scores})


# ---------------------------------------------------------------- json helpers
func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _save_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


# ---------------------------------------------------------------- input map
## Actions are registered in code so touch buttons and keyboard share one map
## (keyboard bindings are for desktop testing).
func _register_input_actions() -> void:
	var actions := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"duck": [KEY_S, KEY_DOWN],
		"interact": [KEY_W, KEY_UP],
		"punch": [KEY_J, KEY_Z],
		"kick": [KEY_K, KEY_X],
		"throw": [KEY_I, KEY_L, KEY_C],
	}
	for action in actions:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in actions[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
