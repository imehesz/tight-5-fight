extends Node
## Global game state singleton (registered as "GameState" in Project Settings > Globals).
## Tracks score, lives, selected character, venue difficulty, high scores and settings.

signal score_changed(new_score: int)
signal lives_changed(new_lives: int)
signal bottles_changed(new_count: int)
## Mic-stand swing cooldown gate; the touch button dims while not ready.
signal swing_ready_changed(ready: bool)
signal bosses_changed(new_count: int)
signal streak_changed(count: int, mult: int)
## Combat juice: gameplay scenes listen and bump their camera/root by this
## many pixels (see street.gd / venue.gd). Scenes own their cameras, so shake
## is requested through the singleton rather than reaching into the scene.
signal shake_requested(pixels: float)
## Venue-crowd visual reactions, mirrored on the audience silhouette row
## (see crowd_row.gd). kind is one of "boo", "laugh", "cheer" (per KO) or
## "celebrate" (venue cleared). Broadcast from the fight call sites alongside
## the crowd SFX; scenes with no CrowdRow just ignore it.
signal crowd_reaction(kind: String)
## The run clock hit 0:00. Whichever scene is up drops the player where they
## stand; the ordinary death flow carries it to game over from there.
signal time_expired

## Dead zone along the bottom edge, in design pixels (the viewport is 360
## tall, so this is also roughly CSS pixels on a phone in landscape). Android
## draws its gesture pill / nav bar over the bottom of the browser viewport,
## and taps there go to the system, not to us — so anything tappable has to
## stay above this line. Menus lift their whole column by it (menu_base.gd)
## and the on-screen controls lift their clusters (touch_controls.gd). Bump
## it if a device still swallows the bottom row.
const SAFE_BOTTOM := 16.0

const SCENE_SPLASH := "res://scenes/splash.tscn"
const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"
const SCENE_CHARACTER_SELECT := "res://scenes/character_select.tscn"
const SCENE_SETTINGS := "res://scenes/settings_menu.tscn"
const SCENE_SCOREBOARD := "res://scenes/scoreboard.tscn"
const SCENE_ABOUT := "res://scenes/about.tscn"
const SCENE_SPONSORS := "res://scenes/sponsors_menu.tscn"
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
## KO streak: consecutive KOs within STREAK_WINDOW_MS of each other multiply
## KO score, up to x STREAK_MAX_MULT. Taking a hit resets it. Applies ONLY to
## KO score — venue clear and boss survival bonuses stay on plain add_score().
const STREAK_WINDOW_MS := 5000
const STREAK_MAX_MULT := 5
## THE TIGHT 5: a run is five minutes, full stop. The clock starts with the
## run and keeps ticking through venues, doors and boss fights alike — the
## street is not a place to farm points forever, it is the walk between sets.
## At 0:00 the player collapses where they stand and the run is over, however
## many lives are banked (see lose_life()).
const RUN_TIME := 300.0

## Looping background tracks come from the active game's manifest (main +
## venue). SFX are shared engine chrome. See _music_tracks()/_setup_audio().
const SFX_BASE := "res://shared/assets/sfx/sfx_"
const SFX_NAMES := ["punch", "kick", "hurt", "defeat", "smash", "clear", "click", "throw", "swing"]
const SFX_POOL_SIZE := 6
## Logical sound names that borrow another sample until a file of their own
## exists. The mic-stand swing has no sfx_swing file and plays the throw
## sample — but it is its OWN action, fired on every swing input, where the
## throw is occasional. play_sfx() resolves the alias AFTER the mute check, so
## "swing" can be silenced without silencing the bottle throw it borrows from.
const SFX_ALIASES := {"swing": "throw"}
## EVERY sound effect, silenced on iOS — music keeps playing. This is the one
## configuration testers proved survives on device (?nosfx=1 never crashed,
## ?nomusic=1 with SFX on always did). A narrower attempt at just the player's
## attack sounds was tried first and did NOT stop the crashes, so this is the
## deliberate blunt instrument until the real cause is found.
##
## Silenced by SAMPLE, so an ENEMY's punch is quiet too — that is exactly the
## configuration that was proven, since ?sfxoff= suppresses by name and not by
## who acted.
##
## ─── TESTING SOUNDS ONE BY ONE ───────────────────────────────────────────
## Easiest, NO rebuild needed: open the game with ?sfxonly=punch (any name
## below). That lets exactly one sound through and silences the rest, on any
## device. website-for-all/iphonetest.html lists a ready-made link per sound.
## By hand: comment out a line below and re-export to let that one through.
## Whole mitigation off: ?iosaudio=1 · force it on a non-iPhone: ?iosmute=1
## ─────────────────────────────────────────────────────────────────────────
##
## Keep in sync with SFX_NAMES + CROWD_NAMES + STINGER_NAMES above, plus the
## two self-managed sounds (plane, bomb-drop). Music is deliberately absent.
const IOS_SILENT_SFX := [
	# player + fighter actions — the original (wrong) suspects
	"punch",
	"kick",
	"swing",
	"throw",
	# other combat
	"hurt",
	"defeat",
	"smash",
	"clear",
	# menus
	"click",
	# crowd reactions
	"boo",
	"cheer",
	"laugh",
	# death stingers
	"cricket",
	"curb",
	# airplane — these two use their own players, not the shared pool
	"plane",
	"bomb-drop",
]
## User-supplied crowd sounds use hyphen filenames (sfx-cricket.wav) —
## deliberately outside the sfx_ pool naming above.
const HYPHEN_SFX_BASE := "res://shared/assets/sfx/sfx-"
## Death stingers: one plays at random on the FINAL death (finish_run());
## the music pauses underneath so the joke lands, then resumes when the
## stinger ends.
const STINGER_NAMES := ["cricket", "curb"]
## Venue-fight-only crowd reactions (play_crowd): boo = player knocked down
## with a respawn coming, cheer = 20% on an NPC KO, laugh = 25% on the player
## taking a bottle. The chance rolls live at the call sites.
const CROWD_NAMES := ["boo", "cheer", "laugh"]
const CROWD_GAP_MS := 1500

## The active game id and its parsed game.json manifest. Loaded first in
## _ready() from data/active_game.json; everything game-specific reads from here.
var active_game := "tight5"
var manifest: Dictionary = {}
var _scores_file := ""
var _settings_file := ""

var characters: Array = []
## Roster indices (into `characters`) of everyone a player may actually meet:
## every entry whose characters.json record doesn't say `"isDisabled": true`.
## Disabled comedians stay in `characters` on purpose — the leaderboards look
## their name up there for the head sprite, so old stats keep their face — they
## are only kept out of the roster grid, random picks, hecklers and pilots.
## Seasonal characters (a Santa in December) live and die by this flag, no
## database edit required.
var playable: Array = []
## Venues a run can spawn doors for: every venues.json entry not marked
## `"isDisabled": true`. Benched venues never enter this array (see
## _load_roster for why that's safe here but not for characters).
var venues: Array = []
## Per-run shuffled indices into `venues`: every run deals the venue list in
## a fresh random order (fair exposure for every venue — ad space included —
## instead of the json order always winning). Street door spawns walk this
## via venue_data_for_index; it must stay stable within a run, because the
## street's door index is saved/restored across venue visits.
var _venue_order: Array = []
var selected_character := 0
## True when the roster's "?" card is the active pick — FIGHT! rolls a
## random comedian. Persisted so character select reopens on the "?".
var random_select := false
var score := 0
var lives := 1
var venues_entered := 0
## Bosses cleared so far, and beer bottles currently carried (0..MAX_BOTTLES).
var bosses_defeated := 0
var beer_bottles := 0
## Seconds left on the run clock, and whether it is ticking. Only gameplay
## scenes run it (see change_scene) — menus, character select and game over
## leave it frozen. The HUD polls run_time_left rather than listening on a
## per-second signal: it redraws every frame anyway.
var run_time_left := RUN_TIME
var _clock_running := false
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
## Sponsor billboards actually SEEN this run (scrolled into view, not merely
## spawned), sponsorId -> count. Ships alongside run_kos so sponsor reports
## bill real eyeballs. Lost if the tab closes mid-run — same accepted
## trade-off as the other run tallies.
var run_billboards: Dictionary = {}
## KOs dealt INSIDE each venue this run, venue name -> count ("fights" on the
## TOP VENUES board). Street KOs are deliberately unattributed — only KOs
## landed while current_venue_name is set count. Ships alongside run_kos.
var run_venue_kos: Dictionary = {}
## The venue the player is currently inside; "" on the street and in menus.
## Set by enter_venue(), cleared by any change_scene() away from the venue.
var current_venue_name := ""
## Current KO streak and the tick (Time.get_ticks_msec, unaffected by
## hitstop's Engine.time_scale) the window closes at; expired lazily in
## bank_ko_score()/streak_active(), so no timer to manage.
var streak := 0
var _streak_deadline_ms := 0
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
## Keyed by stinger name (not a bare Array) so ?sfxoff=cricket can drop one
## without dropping the other.
var _stinger_streams := {}
var _stinger_player: AudioStreamPlayer
var _stinger_active := false
## The music player's own volume, saved across a stinger. Player-level, NOT
## the "Music" bus — the bus carries the player's volume setting, and this
## must not fight with it.
var _music_volume_db := 0.0
## Bumped on every stinger start AND end, so a late safety timer from an
## older stinger can tell it has been superseded and do nothing.
var _stinger_token := 0
var _crowd_streams := {}
var _crowd_last_ms := {}
## Web only: whether the first user gesture has been seen. See unlock_audio().
var _audio_unlocked := false

## TEMPORARY diagnostic kill switches for the iPhone reload-in-place hunt
## (2026-07-25). Set from the page URL on web builds only, so one deployed
## build can be A/B'd on a borrowed device with no redeploy between runs:
##
##   ?noaudio=1   no music, no SFX, no crowd, no stinger
##   ?nosfx=1     no SFX/crowd/stinger, music still plays
##   ?nomusic=1   music off, SFX still play
##   ?noshake=1   no screen shake
##
## Every switch is a guard at a single funnel, so nothing else in the game
## needs to know these exist. Delete the whole block once the cause is found.
var _no_sfx := false
var _no_music := false
var _no_shake := false
## Names suppressed by ?sfxoff=punch,hurt — lets a single sound (or a group
## sharing a sample rate) be bisected on a borrowed device with no redeploy.
## Covers EVERY non-music sound in the game by name: play_sfx names, play_crowd
## names, the death stingers (cricket, curb), and the two sounds that build
## their own players outside this autoload (plane, bomb-drop — see
## is_sfx_muted(), which plane_flyby.gd and plane_drop.gd call).
var _sfx_off: PackedStringArray = []
## Tracks suppressed by ?musicoff=main,venue — the per-track counterpart to
## ?nomusic=1, so the menu tune and the venue tune can be bisected separately.
var _music_off: PackedStringArray = []
## Whether IOS_SILENT_SFX is in force: set at boot on iOS web builds only.
var _ios_silence := false
## ?iosaudio=1 — opt back INTO the attack sounds on iOS, for working on a
## real fix. Read before _ios_silence is decided.
var _ios_audio_forced := false
## ?iosmute=1 — apply the iOS mitigation on ANY device. The owner has no
## iPhone, so this is the only way to hear what the mitigation does without
## borrowing one. Detection itself still needs a real device.
var _ios_mute_forced := false
## ?sfxonly=punch — let exactly ONE sound through and silence every other,
## overriding even the iOS mitigation. Built for testing the silenced sounds
## back in one at a time on a borrowed iPhone, with no rebuild between runs.
## Music is unaffected: it is proven safe and confirms audio is alive at all.
var _sfx_only := ""
## ?fighter=<CharacterId> — a shared comedian link, produced by the SHARE
## button on the roster. NOT a debug switch: it is the one query flag real
## players see. Captured raw at boot because flags are read before the roster
## exists; resolved (and consumed) by start_deeplink_fight().
var _deeplink_fighter := ""
## The player's OWN pick, parked here while a shared link borrows the slot, so
## their favorite is restored the moment they open the roster and is never
## written over in the save file.
var _pick_before_deeplink := -1
var _random_before_deeplink := false
## ?nopool=1 — give every sound its OWN player with its stream assigned once at
## load, instead of six shared players whose `stream` is reassigned (often
## mid-playback) several times a second during a fight. Tests whether the churn
## is the problem rather than the decoding. Trade-off while it is on: a sound
## cannot overlap itself, it restarts.
var _no_pool := false
var _sfx_players := {}


func _ready() -> void:
	randomize()
	_read_debug_flags()
	_register_input_actions()
	_load_active_game()
	get_window().title = game_title()
	_load_roster()
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_load_settings()
	_load_scores()
	_setup_audio()
	# Only the Web build needs the gesture handshake; everywhere else the
	# boot-time play_music() is already audible.
	set_process_input(OS.has_feature("web"))


## First real user gesture of the session — hand it straight to unlock_audio()
## and then stop listening. Lives on the autoload rather than on splash.gd so
## it fires no matter which scene the player happens to be looking at.
func _input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventKey and event.pressed)
	if pressed:
		unlock_audio()


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
	playable = []
	for i in characters.size():
		if not bool(characters[i].get("isDisabled", false)):
			playable.append(i)
	var vs: Array = _load_json(game_path(String(manifest.get("venues", "venues.json")))).get("venues", [])
	venues = []
	for v in vs:
		# Unlike disabled comedians, disabled venues can drop out of the array
		# entirely: nothing in the client looks venue art up by name — the
		# scoreboard's venue rows are text-only, and the public stats pages read
		# their own synced copy of venues.json. The DB keeps the visit rows, so
		# a benched venue still ranks on the boards; it just spawns no door.
		if bool(v.get("isDisabled", false)):
			continue
		for k in ["ExteriorSpritePath", "InteriorSpritePath"]:
			if String(v.get(k, "")) != "":
				v[k] = game_path(String(v[k]))
		venues.append(v)


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


## Sentences the street's banner plane can tow; empty (the default) means the
## game has no flybys at all.
func plane_banners() -> Array:
	return manifest.get("planeBanners", [])


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
## The roster index a new run should start as: the persisted pick — or a
## fresh roll every time while the "?" (random) card is the active pick, so
## FIGHT! and PLAY AGAIN both keep the mystery.
func fight_character_index() -> int:
	if random_select and not playable.is_empty():
		return playable[randi() % playable.size()]
	return selected_character


## `remember` false starts the run WITHOUT persisting the pick — used by a
## shared ?fighter= link, where the comedian is borrowed for one run and the
## player's own saved favorite has to survive it untouched.
func start_new_game(character_index: int, remember := true) -> void:
	if remember:
		set_selected_character(character_index)
	else:
		selected_character = clampi(character_index, 0, maxi(characters.size() - 1, 0))
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
	run_billboards = {}
	run_venue_kos = {}
	_shuffle_venues()  # every run sees the venues in a fresh order
	reset_streak()  # a new run never inherits a streak
	start_clock()  # the tight 5 starts here and runs until 0:00
	change_scene(SCENE_STREET)


func enter_venue() -> void:
	venues_entered += 1
	var venue_name := String(pending_venue.get("VenueName", ""))
	if venue_name != "":
		run_venues[venue_name] = int(run_venues.get(venue_name, 0)) + 1
	current_venue_name = venue_name
	change_scene(SCENE_VENUE)


func is_boss_venue() -> bool:
	return venues_entered > 0 and venues_entered % BOSS_EVERY == 0


## One billboard scrolled into view (Billboard._on_seen fires this exactly
## once per instance; the counted flag survives street restores).
func count_billboard_impression(sponsor_id: String) -> void:
	run_billboards[sponsor_id] = int(run_billboards.get(sponsor_id, 0)) + 1


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


# ---------------------------------------------------------------- KO streak
func streak_mult() -> int:
	return clampi(streak, 1, STREAK_MAX_MULT)


## True while a streak worth showing is alive (used by the HUD chip).
func streak_active() -> bool:
	return streak >= 2 and Time.get_ticks_msec() <= _streak_deadline_ms


## Bank one KO: lazily expire the window, grow the streak, pay the
## multiplied score. Returns the multiplier used so the caller can celebrate.
func bank_ko_score(base_points: int) -> int:
	var now := Time.get_ticks_msec()
	if now > _streak_deadline_ms:
		streak = 0
	streak += 1
	_streak_deadline_ms = now + STREAK_WINDOW_MS
	var mult := streak_mult()
	add_score(base_points * mult)
	streak_changed.emit(streak, mult)
	return mult


func reset_streak() -> void:
	if streak == 0:
		return
	streak = 0
	streak_changed.emit(0, 1)


## Bank one KO for the beaten-up comedian. Enemy._die() calls this; a fighter
## never configured from the roster has no name and is not counted.
func count_ko(char_name: String) -> void:
	if char_name != "":
		run_kos[char_name] = int(run_kos.get(char_name, 0)) + 1
	# A nameless fighter is still a fight: the venue tally counts the KO even
	# when the roster tally above can't.
	if current_venue_name != "":
		run_venue_kos[current_venue_name] = \
				int(run_venue_kos.get(current_venue_name, 0)) + 1


# ------------------------------------------------------------------ run clock
## Ticks on the scaled delta on purpose: hitstop (and any future pause) freezes
## the clock exactly like it freezes the fight.
func _process(delta: float) -> void:
	if not _clock_running:
		return
	run_time_left = maxf(run_time_left - delta, 0.0)
	if run_time_left > 0.0:
		return
	_clock_running = false
	time_expired.emit()


func start_clock() -> void:
	run_time_left = RUN_TIME
	_clock_running = true


func time_up() -> bool:
	return run_time_left <= 0.0


## How long this run lasted, in whole seconds — the clock read backwards.
## Banked with the play at game over (Leaderboard.record_play), so the stats
## can tell a run that went the distance (RUN_TIME exactly, the player was
## still standing at 0:00) from one that ended early.
func run_seconds() -> int:
	return int(roundf(clampf(RUN_TIME - run_time_left, 0.0, RUN_TIME)))


## "4:07" for the HUD. Rounds UP, so a fresh run reads 5:00 on its first frame
## instead of 4:59, and 0:00 appears only when the time is genuinely gone.
func time_text() -> String:
	var secs := int(ceilf(run_time_left))
	return "%d:%02d" % [secs / 60, secs % 60]


## Returns true when the run is over — out of lives, OR the clock ran out.
## A timeout ends the run outright: banked lives buy nothing once time's up.
func lose_life() -> bool:
	if time_up():
		return true
	lives -= 1
	lives_changed.emit(lives)
	return lives <= 0


func finish_run() -> void:
	play_death_stinger()
	last_run_rank = _record_score()
	# Banks this character's play on the global board. Deliberately not
	# awaited: it outlives the scene change (Leaderboard is an autoload) and
	# a failure must never stall or block game over.
	Leaderboard.record_play()
	change_scene(SCENE_GAME_OVER)


func change_scene(path: String) -> void:
	# Leaving the venue (street, game over, menu) ends venue-KO attribution.
	if path != SCENE_VENUE:
		current_venue_name = ""
	# The clock runs in gameplay only, so game over / menus freeze it — and an
	# already-expired clock is never restarted here: it would emit time_expired
	# into the gap before the incoming scene has connected. Scenes handle that
	# case themselves on _ready (see street.gd/venue.gd _on_time_expired).
	_clock_running = not time_up() \
			and (path == SCENE_STREET or path == SCENE_VENUE)
	play_music("venue" if path == SCENE_VENUE else "main")
	get_tree().call_deferred("change_scene_to_file", path)


# ---------------------------------------------------------------- combat feel
## Hitstop tuning: how long a normal hit freezes the game (real seconds) and
## how far time slows during the freeze. Killing blows pass a longer duration
## from the call site (see fighter.gd).
const HITSTOP_TIME := 0.05
const HITSTOP_SCALE := 0.05

var _in_hitstop := false


## Freeze the whole game briefly on a solid hit. Uses Engine.time_scale, so
## physics, animations and tweens all pause together; the restore timer runs
## on real time (ignore_time_scale) or it would never fire. The _in_hitstop
## guard stops overlapping hits (two enemies hit at once) from stacking or
## leaving time_scale broken.
func hitstop(duration := HITSTOP_TIME, frozen_scale := HITSTOP_SCALE) -> void:
	if _in_hitstop:
		return
	_in_hitstop = true
	Engine.time_scale = frozen_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_in_hitstop = false


func request_shake(pixels := 3.0) -> void:
	if _no_shake:
		return
	shake_requested.emit(pixels)


## Read the temporary ?noaudio/?nosfx/?nomusic/?noshake switches off the page
## URL. Web only — desktop and the editor have no location to read, and the
## flags stay false there, so nothing changes for normal play. Deliberately
## tolerant: an unparseable query string simply leaves every switch off.
func _read_debug_flags() -> void:
	if not OS.has_feature("web"):
		return
	var raw: Variant = JavaScriptBridge.eval("window.location.search || ''", true)
	if raw != null:
		_apply_debug_flags(str(raw))
	# Decided AFTER the flags, so ?iosaudio=1 can opt back in. Runs even when
	# the query string is unreadable — the mitigation must not depend on it.
	_ios_silence = not _ios_audio_forced and (_ios_mute_forced or _is_ios_browser())
	if _ios_silence:
		print("[audio] attack SFX disabled (%s): %s" % [
				"forced" if _ios_mute_forced else "iOS detected", IOS_SILENT_SFX])


## iPhone/iPad/iPod, including iPadOS 13+, which reports itself as "MacIntel"
## and is only distinguishable from a real Mac by having touch points. iPads
## share the WebKit audio path the crash lives in, so they get the mitigation
## too even though every report came from an iPhone.
func _is_ios_browser() -> bool:
	var js := "(/iPad|iPhone|iPod/.test(navigator.userAgent)" \
			+ " || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1))" \
			+ " ? 1 : 0"
	var r: Variant = JavaScriptBridge.eval(js, true)
	return r != null and int(r) == 1


## Split out from _read_debug_flags purely so the parsing can be exercised
## headlessly, with no browser and no JavaScriptBridge.
func _apply_debug_flags(search: String) -> void:
	if search == "":
		return
	var flags := {}
	for part in search.lstrip("?").split("&", false):
		var kv := part.split("=", true, 1)
		if kv.size() > 0 and kv[0] != "":
			flags[kv[0]] = "1" if kv.size() < 2 else kv[1]
	var all_off: bool = str(flags.get("noaudio", "")) == "1"
	_no_sfx = all_off or str(flags.get("nosfx", "")) == "1"
	_no_music = all_off or str(flags.get("nomusic", "")) == "1"
	_no_shake = str(flags.get("noshake", "")) == "1"
	var off := str(flags.get("sfxoff", ""))
	if off != "":
		_sfx_off = off.split(",", false)
	var moff := str(flags.get("musicoff", ""))
	if moff != "":
		_music_off = moff.split(",", false)
	_no_pool = str(flags.get("nopool", "")) == "1"
	_ios_audio_forced = str(flags.get("iosaudio", "")) == "1"
	_ios_mute_forced = str(flags.get("iosmute", "")) == "1"
	_sfx_only = str(flags.get("sfxonly", ""))
	# Decoded because it is the one flag a stranger's link supplies. Ids are
	# plain ASCII so this is normally a no-op, but a hand-mangled %2D should
	# still find its comedian.
	_deeplink_fighter = str(flags.get("fighter", "")).uri_decode()
	if _no_sfx or _no_music or _no_shake or not _sfx_off.is_empty() \
			or not _music_off.is_empty():
		print("[diag] sfx_off=%s music_off=%s shake_off=%s suppressed=%s tracks_off=%s" % [
				_no_sfx, _no_music, _no_shake, _sfx_off, _music_off])


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


## Roster position of a CharacterId, or -1 when nothing matches. Unlike
## character_index_by_name, callers here MUST be able to tell "no such
## comedian" apart from "the first comedian", so this does not fall back.
func character_index_by_id(id: String) -> int:
	if id == "":
		return -1
	for i in characters.size():
		if String(characters[i].get("CharacterId", "")) == id:
			return i
	return -1


# ---------------------------------------------------------------- share links
## Where this game lives in the public URL. Almost always the game id — the
## exception is tight5, which ships at /jax/. Only the desktop and editor
## fallback needs it; on web the page's own address is the authority.
func public_folder() -> String:
	return String(manifest.get("publicFolder", active_game))


## Prefix for the composed (non-web) share link. Web never uses this.
const SHARE_BASE := "https://games.imstandup.com/tight5fight/"

## The link the SHARE button hands out. On web it is derived from the page's
## OWN url, so a LAN playtest shares a LAN link, prod shares prod, and the
## jax/tight5 folder mismatch cannot produce a 404. Everywhere else it is
## composed from SHARE_BASE + public_folder().
func share_url(character_id: String) -> String:
	var base := SHARE_BASE + public_folder() + "/"
	if OS.has_feature("web"):
		# Strip whatever follows the last slash (index.html, or nothing) so the
		# result is always the directory the build is served from.
		var here: Variant = JavaScriptBridge.eval(
				"location.origin + location.pathname.replace(/[^\\/]*$/, '')", true)
		if here != null and str(here) != "":
			base = str(here)
	return "%s?fighter=%s" % [base, character_id.uri_encode()]


## Outcome of share_link() — the caller only needs to say something when the
## link went somewhere invisible.
enum { SHARE_FAILED = 0, SHARE_NATIVE = 1, SHARE_COPIED = 2 }

## Push a share link at the OS: the native share sheet where there is one
## (every phone, which is the case that matters), the clipboard otherwise.
##
## navigator.share needs transient user activation. Godot handles input on its
## own frame rather than inside the DOM event handler, but the activation
## window is seconds wide, so a button press still qualifies — the same reason
## the audio unlock tap works. Deliberately NOT awaited: the promise settles
## long after eval() returns, and a player dismissing the sheet is not an
## error worth reporting.
func share_link(url: String, text: String) -> int:
	if not OS.has_feature("web"):
		DisplayServer.clipboard_set(url)
		return SHARE_COPIED
	var js := """(function (u, t, title) {
		try {
			if (navigator.share) {
				navigator.share({title: title, text: t, url: u}).catch(function () {});
				return 1;
			}
		} catch (e) {}
		try {
			if (navigator.clipboard && navigator.clipboard.writeText) {
				navigator.clipboard.writeText(t + " " + u).catch(function () {});
				return 2;
			}
		} catch (e) {}
		try {
			var ta = document.createElement('textarea');
			ta.value = t + " " + u;
			ta.style.position = 'fixed';
			ta.style.opacity = '0';
			document.body.appendChild(ta);
			ta.select();
			var ok = document.execCommand('copy');
			document.body.removeChild(ta);
			return ok ? 2 : 0;
		} catch (e) {}
		return 0;
	})(%s, %s, %s)""" % [JSON.stringify(url), JSON.stringify(text), JSON.stringify(game_title())]
	var r: Variant = JavaScriptBridge.eval(js, true)
	return int(r) if r != null else SHARE_FAILED


## True while a ?fighter= link from this page load is still unspent. Splash
## checks it to decide between the main menu and going straight to the fight.
func has_deeplink_fighter() -> bool:
	return _deeplink_fighter != ""


## Resolve the pending ?fighter= id and start its run, CONSUMING the link so
## it fires exactly once per page load — otherwise CHANGE COMEDIAN would keep
## yanking the player back into the shared fighter. An id matching nothing, or
## matching a benched comedian, rolls a random one rather than failing: a dead
## link should still open a game.
func start_deeplink_fight() -> void:
	var id := _deeplink_fighter
	_deeplink_fighter = ""
	if playable.is_empty():
		change_scene(SCENE_MAIN_MENU)
		return
	var idx := character_index_by_id(id)
	if idx == -1 or not playable.has(idx):
		idx = playable[randi() % playable.size()]
		print("[share] fighter '%s' is unknown or benched — rolled %s instead" % [
				id, characters[idx].get("CharacterName", "?")])
	# The shared comedian is BORROWED for this run: stashed here, handed back
	# by the roster screen, never written to the save file.
	_pick_before_deeplink = selected_character
	_random_before_deeplink = random_select
	random_select = false
	start_new_game(idx, false)


## Give the player their own comedian back after a shared link borrowed the
## slot. Called by the roster screen, so the pick it opens on is the one they
## actually chose. A no-op when no link was followed.
func restore_own_pick() -> void:
	if _pick_before_deeplink == -1:
		return
	selected_character = _pick_before_deeplink
	random_select = _random_before_deeplink
	_pick_before_deeplink = -1


## Random enemy configs pulled from the roster, excluding the player's pick.
func enemy_characters(count: int) -> Array:
	var pool: Array = []
	for i in playable:
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
	# Guard for any path that reaches here without start_new_game (and for a
	# reloaded venue list changing size): deal a fresh order rather than crash.
	if _venue_order.size() != venues.size():
		_shuffle_venues()
	return venues[_venue_order[i % venues.size()]]


func _shuffle_venues() -> void:
	_venue_order = range(venues.size())
	_venue_order.shuffle()


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
	for stinger_name in STINGER_NAMES:
		var s := _load_stream(HYPHEN_SFX_BASE + stinger_name)
		if s:
			_stinger_streams[stinger_name] = s
	for crowd_name in CROWD_NAMES:
		var s := _load_stream(HYPHEN_SFX_BASE + crowd_name)
		if s:
			_crowd_streams[crowd_name] = s
	# ?nopool only: one player per sound, stream assigned ONCE here so that
	# playing a sound is nothing but a play() call.
	if _no_pool:
		for source in [_sfx_streams, _crowd_streams]:
			for sound_name in source:
				var p := AudioStreamPlayer.new()
				p.bus = "SFX"
				p.stream = source[sound_name]
				add_child(p)
				_sfx_players[sound_name] = p
	# Dedicated player, not the pool: pool voices get recycled by combat SFX,
	# which would cut the stinger short and strand the music paused.
	_stinger_player = AudioStreamPlayer.new()
	_stinger_player.bus = "SFX"
	add_child(_stinger_player)
	_stinger_player.finished.connect(_on_stinger_finished)


## Mobile browsers keep the WebAudio context suspended until the first user
## gesture, and anything play()ed while it is suspended is dropped on the
## floor rather than queued. _setup_audio() runs at autoload time — long
## before any tap — so on the Web the boot-time play_music("main") is lost.
## Android/Chrome papers over it; iOS Safari does not, which is why the iPhone
## build was silent (reported 2026-07-23) while Android and desktop were fine.
##
## Worse, play_music() no-ops when the requested track is already current, so
## nothing would ever re-issue it and the music stayed dead for the whole
## session. Hence the `force` flag.
##
## The retry exists because resume() is asynchronous: the engine asks the
## browser to resume the context from inside the same browser event that
## produced this input, but the context may still be suspended a frame later
## when we call play(). If the playhead has not moved by then, we try once
## more. get_playback_position() advances only as frames are actually mixed
## out, so it is a real "is sound flowing" check, not a guess.
## How long to wait before checking whether the unlock actually took.
const AUDIO_UNLOCK_RETRY_SEC := 0.5


func unlock_audio() -> void:
	if _audio_unlocked:
		return
	_audio_unlocked = true
	set_process_input(false)
	if _music_track == "":
		return
	play_music(_music_track, true)
	await get_tree().create_timer(AUDIO_UNLOCK_RETRY_SEC).timeout
	if not is_instance_valid(_music_player) or _music_player.stream_paused:
		return
	if _music_player.get_playback_position() <= 0.0:
		play_music(_music_track, true)


## Swap the looping background track; no-op if it's already playing (so
## menu-to-menu transitions never restart the tune) or the file is missing.
## `force` re-issues the play() even for the current track — only unlock_audio()
## needs it, see the note there.
func play_music(track: String, force: bool = false) -> void:
	if _no_music or _music_off.has(track):
		return
	if not _music_streams.has(track):
		return
	if track == _music_track and not force:
		return
	_music_track = track
	_music_player.stream = _music_streams[track]
	_music_player.play()
	# A venue death swaps venue->main mid-stinger (change_scene calls this);
	# the fresh play() must not undo the stinger's pause. The stinger's volume
	# duck needs no re-applying — volume_db is a property of the player, not
	# of the stream, so swapping streams leaves it muted.
	_music_player.stream_paused = _stinger_active


## Whether a named sound actually loaded — lets callers pick a stand-in
## (e.g. the swing reuses "throw" until a real sfx_swing.wav exists).
func has_sfx(sfx_name: String) -> bool:
	return _sfx_streams.has(sfx_name)


## Diagnostic check for the two sounds that build their own AudioStreamPlayer
## instead of going through play_sfx() — the plane engine loop and the bomb
## whistle. They are the only sounds this autoload cannot gate itself, and
## they are prime suspects (extra players, created mid-fight), so ?sfxoff=
## has to reach them too. See _sfx_off.
## The ONE funnel every sound suppression goes through: the ?nosfx/?sfxoff
## diagnostics and the standing iOS attack-sound mitigation.
func is_sfx_muted(sfx_name: String) -> bool:
	# ?sfxonly= wins over everything, including the iOS mitigation — its whole
	# job is letting a silenced sound back in for one test run.
	if _sfx_only != "":
		return sfx_name != _sfx_only
	if _ios_silence and IOS_SILENT_SFX.has(sfx_name):
		return true
	return _no_sfx or _sfx_off.has(sfx_name)


func play_sfx(sfx_name: String) -> void:
	if is_sfx_muted(sfx_name):
		return
	# Alias resolution happens HERE, after the mute check, so a borrowed sample
	# can be silenced for one action without silencing the other. See
	# SFX_ALIASES; a real sfx_swing file would take over automatically.
	var stream_name := sfx_name
	if not _sfx_streams.has(stream_name):
		stream_name = str(SFX_ALIASES.get(sfx_name, sfx_name))
	if not _sfx_streams.has(stream_name):
		return
	if _no_pool:
		_sfx_players[stream_name].play()
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = _sfx_streams[stream_name]
	p.play()


## Venue-crowd one-shot, rate-limited per name so e.g. a double KO whose
## rolls both pass can't stack two cheers. Missing files no-op like play_sfx.
func play_crowd(crowd_name: String) -> void:
	if is_sfx_muted(crowd_name):
		return
	if not _crowd_streams.has(crowd_name):
		return
	var now := Time.get_ticks_msec()
	if now - int(_crowd_last_ms.get(crowd_name, -CROWD_GAP_MS)) < CROWD_GAP_MS:
		return
	_crowd_last_ms[crowd_name] = now
	if _no_pool:
		_sfx_players[crowd_name].play()
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = _crowd_streams[crowd_name]
	p.play()


## Final-death gag: duck the music, play a random stinger (crickets, curb),
## bring it back when the stinger ends. Missing files = silent no-op, like
## play_sfx.
##
## Silenced TWO ways on purpose. `stream_paused` alone was the original
## implementation and it works on desktop, but on Android the music played
## straight through the stinger (reported 2026-07-23) — so the volume is
## dropped as well, which no platform has ever ignored. On desktop the pause
## still wins, so the track resumes where it left off; where the pause is
## ignored the music keeps rolling silently and comes back further along.
## That trade is deliberate: audible-but-wrong-position beats never ducking.
##
## Never stop() the stinger player elsewhere — stop() doesn't emit finished.
## That used to strand the music paused; now the safety timer below unwinds
## it either way.
const MUTED_DB := -80.0
## Longest stinger is ~2.7s. If `finished` never lands (a real risk on mobile
## web, which is what this whole workaround is about), restore anyway rather
## than leave the game silent forever.
const STINGER_MAX_SEC := 6.0


func play_death_stinger() -> void:
	# Skipped whole under ?nosfx: the music duck it performs is only there to
	# make room for a stinger that will not be playing.
	if _no_sfx:
		return
	if _stinger_streams.is_empty() or _stinger_active:
		return
	# Pick from the stingers ?sfxoff= has left alive. Done BEFORE the music
	# duck below: suppressing every stinger must skip the whole routine, not
	# duck the music for a stinger that will never play and then wait out the
	# safety timer to bring it back.
	var choices: Array = []
	for stinger_name in _stinger_streams:
		if not is_sfx_muted(stinger_name):
			choices.append(_stinger_streams[stinger_name])
	if choices.is_empty():
		return
	_stinger_active = true
	_stinger_token += 1
	var token := _stinger_token
	_music_volume_db = _music_player.volume_db
	_music_player.volume_db = MUTED_DB
	_music_player.stream_paused = true
	_stinger_player.stream = choices.pick_random()
	_stinger_player.play()
	get_tree().create_timer(STINGER_MAX_SEC).timeout.connect(
			func() -> void:
				if token == _stinger_token:
					_end_death_stinger())


func _on_stinger_finished() -> void:
	_end_death_stinger()


## Idempotent: the finished signal and the safety timer both land here, and
## whichever arrives first invalidates the other (via the token).
func _end_death_stinger() -> void:
	if not _stinger_active:
		return
	_stinger_active = false
	_stinger_token += 1
	_music_player.stream_paused = false
	_music_player.volume_db = _music_volume_db


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


func set_random_select(on: bool) -> void:
	if on == random_select:
		return  # don't rewrite the save file just for opening a menu
	random_select = on
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
	# A favorite who has since been disabled (a seasonal character out of
	# season) can't stay the pick: fall back to the first one still playable.
	if not playable.is_empty() and not playable.has(selected_character):
		selected_character = playable[0]
	random_select = bool(d.get("random", false))
	_apply_volume("Music", music_volume)
	_apply_volume("SFX", sfx_volume)


func _save_settings() -> void:
	# A comedian borrowed from a ?fighter= link must never reach the save file,
	# no matter what triggers the write — nudging the volume between a shared
	# run and opening the roster would otherwise adopt someone else's pick.
	var borrowed := _pick_before_deeplink != -1
	var own := _pick_before_deeplink if borrowed else selected_character
	_save_json(_settings_file, {
		"music": music_volume,
		"sfx": sfx_volume,
		"outfit": outfit,
		"character": "" if characters.is_empty() \
				else String(characters[clampi(own, 0, characters.size() - 1)].get("CharacterName", "")),
		"random": _random_before_deeplink if borrowed else random_select,
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
		"swing": [KEY_U],
	}
	for action in actions:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in actions[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
