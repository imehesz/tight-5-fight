extends Node
## Global game state singleton (registered as "Leaderboard" in Project
## Settings > Globals). Talks to server/server.js: mints this device's
## anonymous player id, banks a play when a run ends, and fetches pages of
## the global character-popularity board.
##
## Every call here is best-effort. The leaderboard is a garnish, not a
## dependency: if the server is down, unreachable, or rate-limiting us, the
## game plays exactly as before and the GLOBAL tab shows a friendly message.

## fetch_board() resolves into exactly one of these.
signal board_loaded(data: Dictionary)
signal board_failed(reason: String)

## fetch_venues() resolves into exactly one of these. Separate signals so a
## late character-board response can never be mistaken for a venue page.
signal venues_loaded(data: Dictionary)
signal venues_failed(reason: String)

## Production backend: Apache on games.imstandup.com proxies /tight5fight/api/
## to the node process (see server/README.md). The game is served from the same
## host (games.imstandup.com/tight5fight/<theme>), so this is a SAME-ORIGIN
## call. The server still sends CORS headers, which is what lets a build served
## from anywhere else (e.g. the mehesz.net hub) reach it too.
const PROD_HOST := "games.imstandup.com"
const PROD_API_PATH := "/tight5fight/api"
const DEV_PORT := 8770

## Rows per page. Must match `pageSize` in server/config.js — the server
## paginates, this constant only sizes the local board to match.
const PAGE_SIZE := 10

## Anonymous per-device id, minted by the server (never by us: a client that
## invents its own id can mint an unlimited supply of them). Namespaced per
## game like the other save files.
const PLAYER_PATH := "user://%s_player.json"

## Nobody should sit and stare at a spinner because a VPS is down.
const TIMEOUT_SEC := 8.0

var _player_uuid := ""
var _player_file := ""
## True while a record_play() is mid-flight. See record_play().
var _recording := false


func _ready() -> void:
	# GameState is registered first in project.godot, so active_game is set.
	_player_file = PLAYER_PATH % GameState.active_game
	_load_uuid()


# ---------------------------------------------------------------- endpoint
## The page's own hostname decides which backend we talk to, so one build
## works from the deployed site, a LAN box during playtests, and the editor.
static func _page_host() -> String:
	return str(JavaScriptBridge.eval("window.location.hostname"))


static func _page_secure() -> bool:
	return bool(JavaScriptBridge.eval("window.location.protocol == 'https:'"))


static func base_url() -> String:
	if OS.has_feature("web"):
		var host := _page_host()
		# Deployed: both the game's domain and the hub's own domain route to
		# the hub. Scheme follows the page — an https page may not call http.
		if host.ends_with("mehesz.net") or host.ends_with("imstandup.com"):
			return ("https://" if _page_secure() else "http://") + PROD_HOST + PROD_API_PATH
		# A web build served off a LAN box (phone testing): node is on the
		# same machine as the page.
		if host != "" and host != "localhost" and host != "127.0.0.1":
			return "http://%s:%d" % [host, DEV_PORT]
	return "http://127.0.0.1:%d" % DEV_PORT


# ---------------------------------------------------------------- public API
## Bank one play for the character the player just used. Called from
## GameState.finish_run(), i.e. when a run ENDS — a fabricated play therefore
## costs a real run's worth of time. Fire-and-forget: a refusal (offline, or
## the server's once-a-minute cooldown) is a normal outcome, not an error.
func record_play() -> void:
	# Read the character (and this run's KO tally) BEFORE the first await.
	# Minting an id can take a round trip, and PLAY AGAIN can land in the
	# meantime — resuming after that would read the newly chosen character
	# (and a freshly zeroed tally) and credit the wrong run.
	var character := String(GameState.selected_character_data().get("CharacterName", ""))
	var kos: Dictionary = GameState.run_kos.duplicate()
	var venues: Dictionary = GameState.run_venues.duplicate()
	var billboards: Dictionary = GameState.run_billboards.duplicate()
	var run_score := GameState.score
	var game_id := GameState.active_game
	if character == "":
		return
	# A second run can't finish before the first is banked, so an overlapping
	# call is a duplicate; dropping it also saves a redundant mint. (The
	# server's cooldown would refuse it a moment later anyway.)
	if _recording:
		return
	_recording = true
	if await _ensure_uuid():
		var body := {
			"gameId": game_id,
			"character": character,
			"uuid": _player_uuid,
			# This run's final score, for the TOP SCORE board (the server
			# keeps MAX(score) per character). Old servers just ignore it.
			"score": run_score,
		}
		# Who this run beat up, for the MOST BEAT UP board. Omitted when empty
		# so the payload (and the server's validation) stays the old shape.
		if not kos.is_empty():
			body["kos"] = kos
		# Which doors this run walked through, for the VENUES board. Same
		# omit-when-empty contract as kos.
		if not venues.is_empty():
			body["venues"] = venues
		# Sponsor billboards seen this run, for the impression reports. Same
		# omit-when-empty contract; old servers just ignore the field.
		if not billboards.is_empty():
			body["billboards"] = billboards
		await _request(HTTPClient.METHOD_POST, "/play", body)
	_recording = false


## Fetch one page (0-based) of the global board. Always resolves into either
## board_loaded or board_failed, so the UI never hangs on "Loading…".
func fetch_board(page: int) -> void:
	var res := await _request(
		HTTPClient.METHOD_GET,
		"/leaderboard?gameId=%s&page=%d" % [GameState.active_game.uri_encode(), maxi(page, 0)]
	)
	if bool(res.get("ok", false)):
		board_loaded.emit(res.get("data", {}))
	else:
		board_failed.emit(String(res.get("error", "unavailable")))


## Fetch one page (0-based) of the global most-entered-venues board. Same
## always-resolves contract as fetch_board().
func fetch_venues(page: int) -> void:
	var res := await _request(
		HTTPClient.METHOD_GET,
		"/venues?gameId=%s&page=%d" % [GameState.active_game.uri_encode(), maxi(page, 0)]
	)
	if bool(res.get("ok", false)):
		venues_loaded.emit(res.get("data", {}))
	else:
		venues_failed.emit(String(res.get("error", "unavailable")))


# ---------------------------------------------------------------- transport
## One HTTP round trip. Returns {ok: bool, data: Dictionary, error: String};
## never throws, never leaves the HTTPRequest node behind.
func _request(method: int, path: String, body: Dictionary = {}) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SEC
	add_child(http)

	var headers := PackedStringArray(["Content-Type: application/json"])
	var payload := JSON.stringify(body) if method == HTTPClient.METHOD_POST else ""
	var err := http.request(base_url() + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "offline"}

	var result: Array = await http.request_completed
	http.queue_free()

	# result = [result, response_code, headers, body]
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "offline"}

	var code := int(result[1])
	var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if code < 200 or code >= 300:
		return {"ok": false, "error": String(data.get("error", "server error"))}
	return {"ok": true, "data": data}


# ---------------------------------------------------------------- player id
## True once this device holds a server-minted id. Minting is capped per IP
## server-side, which is what stops a script from rotating ids to spam plays.
func _ensure_uuid() -> bool:
	if _player_uuid != "":
		return true
	var res := await _request(HTTPClient.METHOD_POST, "/player")
	if not bool(res.get("ok", false)):
		return false
	_player_uuid = String(res.get("data", {}).get("uuid", ""))
	if _player_uuid == "":
		return false
	_save_uuid()
	return true


func _load_uuid() -> void:
	if not FileAccess.file_exists(_player_file):
		return
	var f := FileAccess.open(_player_file, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_player_uuid = String(parsed.get("uuid", ""))


func _save_uuid() -> void:
	var f := FileAccess.open(_player_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"uuid": _player_uuid}))
