extends Node
## Flight recorder for the iPhone-only "the game restarts itself" bug
## (registered as "CrashDiag" in Project Settings > Globals).
##
## The web shell (web/shell.html) does the surviving-the-crash half: it mirrors
## our snapshots into localStorage and, on the next boot, works out whether the
## page went down mid-play or the player simply left. This half feeds it engine
## numbers and ships whatever the previous life left behind.
##
## Everything here is best-effort and silent. A recorder that costs a frame, an
## error, or a single moment of the player's attention is worse than no
## recorder at all — on any failure it just stops.
##
## NOT a telemetry stream: the heartbeat never leaves the device. Exactly one
## request is made, at boot, and only when the last session actually died.

## How often we hand a snapshot to the shell. The record is ~400 bytes and
## localStorage writes are synchronous, so this is deliberately lazy — we are
## looking for a trend over minutes, not a frame-accurate trace.
const BEAT_SEC := 2.0

## Let the boot settle before spending anything on a crash report. Loading is
## the single heaviest moment in the session and the report has waited this
## long already; it can wait three seconds more.
const REPORT_DELAY_SEC := 3.0

var _iface: JavaScriptObject
var _timer := 0.0


func _ready() -> void:
	# Web-only by construction: there is no localStorage anywhere else, and
	# the bug is a browser bug.
	if not OS.has_feature("web"):
		set_process(false)
		return
	_iface = JavaScriptBridge.get_interface("__t5diag")
	if _iface == null:
		# An older cached index.html without the shell half. The game plays
		# exactly as before; we just have nothing to write to.
		set_process(false)
		return
	_report_pending.call_deferred()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = BEAT_SEC
	_iface.beat(JSON.stringify(_snapshot()))


## What the engine knows about itself right now. Node/object/orphan counts are
## the leak canaries — if the crash reports show them climbing run-long, the
## memory theory is confirmed and we know which side is growing.
func _snapshot() -> Dictionary:
	var scene := ""
	var current := get_tree().current_scene
	if current != null and current.scene_file_path != "":
		scene = current.scene_file_path.get_file().get_basename()
	return {
		"game": GameState.active_game,
		"scene": scene,
		"fps": int(Performance.get_monitor(Performance.TIME_FPS)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"memStatic": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		# The Compatibility renderer does not always account these; a zero here
		# means "not reported", not "no textures".
		"texMem": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		"venues": GameState.venues_entered,
	}


## Ship the previous life's final snapshot, once, then forget it. Failure is a
## normal outcome (offline, server down, rate limited) and costs nothing: the
## record is deleted either way, because a crash we couldn't report is not
## worth carrying into every future boot.
func _report_pending() -> void:
	var raw := str(_iface.pending())
	if raw == "":
		return
	_iface.clearPending()

	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return
	var body: Dictionary = parsed
	body["gameId"] = GameState.active_game
	# Only if this device already has one. Minting an id for a crash report
	# would spend the player's per-IP mint budget on diagnostics.
	var uuid := Leaderboard.known_player_id()
	if uuid != "":
		body["uuid"] = uuid

	await get_tree().create_timer(REPORT_DELAY_SEC).timeout
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	var err := http.request(
		Leaderboard.base_url() + "/crash",
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	if err != OK:
		http.queue_free()
		return
	await http.request_completed
	http.queue_free()
