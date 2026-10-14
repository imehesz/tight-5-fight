extends Node
## STICKERS — the achievement book behind the JOKE BOOK's BADGES spread.
##
## Data-driven end to end: every sticker is one row in
## shared/data/achievements.json — {id, stat, goal, name, desc} — and its art
## is shared/assets/stickers/<id>.png. A new sticker is a new row and a new
## PNG; a new TIER of an existing one is the same stat with a bigger goal.
## Nothing here or in the book's layout needs touching for either.
##
## Stats are lifetime counters ("kos", "bombs", ...) bumped by the game through
## add(), or high-water marks ("best_streak", "daily_streak") through best().
## A sticker is earned the moment its stat reaches its goal, and stays earned:
## the unlock is stored with its own timestamp, so retuning a goal later never
## takes a sticker back off anyone.
##
## Saved locally in user://<game>_achievements.json, per edition like the high
## scores, and backed up to the server (POST /stickers) at boot and after every
## run. The server keeps the highest value it has ever seen for each stat, so a
## sync can only ever ADD to a book. It is keyed on this device's player id,
## which is itself local: clearing site data still loses the book until there
## is a way to carry that id to a new device.

signal unlocked(id: String)

const DEFS_PATH := "res://shared/data/achievements.json"
const SAVE_PATH := "user://%s_achievements.json"
const STICKER_PATH := "res://shared/assets/stickers/%s.png"

## In file order, which is also book order.
var stickers: Array = []
var _stats := {}
## id -> unix time of the unlock.
var _unlocked := {}
var _file := ""
## Counters move on every KO; they reach disk at game over (and on any unlock),
## not per hit — a web save is an IndexedDB write.
var _dirty := false
## One sync in flight at a time; a second would only post the same book again.
var _syncing := false


func _ready() -> void:
	# GameState is the earlier autoload, so the edition is already resolved.
	_file = SAVE_PATH % GameState.active_game
	_load_defs()
	_load()
	if Leaderboard.JOKE_BOOK_ENABLED:
		Leaderboard.jokebook_loaded.connect(_on_jokebook_loaded)
	# Not awaited: boot must not wait on the network.
	sync()


func _load_defs() -> void:
	var f := FileAccess.open(DEFS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		stickers = parsed.get("stickers", [])


func _load() -> void:
	if not FileAccess.file_exists(_file):
		return
	var f := FileAccess.open(_file, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_stats = parsed.get("stats", {})
		_unlocked = parsed.get("unlocked", {})


func save() -> void:
	if not _dirty:
		return
	_dirty = false
	var f := FileAccess.open(_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"stats": _stats, "unlocked": _unlocked}, "  "))


## Bump a lifetime counter.
func add(stat: String, n := 1) -> void:
	if n <= 0:
		return
	_stats[stat] = stat_value(stat) + n
	_dirty = true
	_check(stat)


## Raise a high-water mark; a lower value is ignored.
func best(stat: String, value: int) -> void:
	if value <= stat_value(stat):
		return
	_stats[stat] = value
	_dirty = true
	_check(stat)


func stat_value(stat: String) -> int:
	return int(_stats.get(stat, 0))


func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)


func unlocked_count() -> int:
	return _unlocked.size()


func texture_path(id: String) -> String:
	return STICKER_PATH % id


func _check(stat: String) -> void:
	var value := stat_value(stat)
	var earned := false
	for s in stickers:
		var id := String(s.get("id", ""))
		if String(s.get("stat", "")) != stat or _unlocked.has(id):
			continue
		if value >= int(s.get("goal", 0)):
			_unlocked[id] = int(Time.get_unix_time_from_system())
			earned = true
			unlocked.emit(id)
	# An unlock is written straight away: a sticker must survive the tab being
	# closed mid-run even though the counters around it may not.
	if earned:
		save()


func _on_jokebook_loaded(_data: Dictionary) -> void:
	best("daily_streak", Leaderboard.streak_days())


## Back the book up and adopt anything the server knows that this device
## doesn't. Best-effort like every other network call: offline, an old server,
## or a device that has never been given a player id just means no sync.
func sync() -> void:
	if _syncing:
		return
	_syncing = true
	var res: Dictionary = await Leaderboard.sync_stickers(_stats, _unlocked)
	_syncing = false
	if bool(res.get("ok", false)):
		_merge(res.get("data", {}))


## Take the higher of each stat and every unlock we don't already have (with
## the server's timestamp, i.e. when it was first earned).
func _merge(server: Dictionary) -> void:
	var stats: Dictionary = server.get("stats", {})
	for stat in stats:
		var value := int(stats[stat])
		if value > stat_value(stat):
			_stats[stat] = value
			_dirty = true
	var unlocks: Dictionary = server.get("unlocked", {})
	for id in unlocks:
		if not _unlocked.has(id):
			_unlocked[id] = int(unlocks[id])
			_dirty = true
	# A raised stat can cross a goal this book has never checked against.
	for stat in _stats.keys():
		_check(stat)
	save()
