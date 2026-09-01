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

## ?showfps=1 — how often the on-screen readout redraws. Four times a second
## is enough to read and slow enough to cost nothing.
const HUD_REFRESH_SEC := 0.25

var _iface: JavaScriptObject
var _timer := 0.0
## ?showfps=1 overlay, or null when the flag is absent (the normal case).
var _hud: Label
var _hud_timer := 0.0


func _ready() -> void:
	# The HUD is set up before the web/localStorage checks below, because it
	# has to work on a build where __t5diag is missing — a stale cached
	# index.html is exactly when you most want to see what the engine is doing.
	_setup_hud()
	# Web-only by construction: there is no localStorage anywhere else, and
	# the bug is a browser bug.
	if not OS.has_feature("web"):
		set_process(_hud != null)
		return
	_iface = JavaScriptBridge.get_interface("__t5diag")
	if _iface == null:
		# An older cached index.html without the shell half. The game plays
		# exactly as before; we just have nothing to write to.
		set_process(_hud != null)
		return
	_report_pending.call_deferred()


func _process(delta: float) -> void:
	if _hud != null:
		_hud_timer -= delta
		if _hud_timer <= 0.0:
			_hud_timer = HUD_REFRESH_SEC
			_hud.text = _hud_line()
	if _iface == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = BEAT_SEC
	_iface.beat(JSON.stringify(_snapshot()))


## ?showfps=1 — a corner readout of the two numbers the choppy-audio work
## turns on, because neither can be checked on a phone any other way.
##
## `application/run/max_fps=60` (project.godot) is the uncertain half of that
## fix: this web build has no ASYNCIFY, so Godot's frame limiter has no sleep
## primitive to throttle with and the setting may simply be inert here. On a
## 120Hz phone this readout settles the question in five seconds — ~60 means
## the cap works, ~120 means it is a no-op and the rAF throttle in the shell
## is the fallback. The dpr pair (real>effective) confirms the cap in
## shell.html took, since a stale cached shell would silently undo it.
##
## Best-effort like the rest of this file: any failure leaves _hud null and
## the game plays exactly as it does without the flag.
func _setup_hud() -> void:
	if not OS.has_feature("web"):
		return
	var search := ""
	var raw = JavaScriptBridge.eval("window.location.search", true)
	if raw != null:
		search = str(raw)
	if not search.contains("showfps=1"):
		return
	var layer := CanvasLayer.new()
	# Above everything the game draws, including the pause/HUD layers.
	layer.layer = 128
	var label := Label.new()
	label.position = Vector2(4, 2)
	# The project theme font is PressStart2P at story sizes; force it small so
	# the readout never covers anything that matters.
	var settings := LabelSettings.new()
	settings.font_size = 8
	settings.font_color = Color(0.6, 1.0, 0.6)
	settings.outline_size = 4
	settings.outline_color = Color(0, 0, 0, 0.9)
	label.label_settings = settings
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	add_child(layer)
	_hud = label


## One line of the ?showfps=1 readout. Reads:
##
##     60 fps  dpr 2.625>2  buf 85ms drop 3.2% hitch 210ms
##
## `fps`/`dpr` verify the two settings that cannot be checked on a phone.
## `buf`/`drop`/`hitch` are the crackle meter from web/shell.html — see the
## long comment there for how to read them. In short: drop 0% means underrun
## is NOT the cause and the diagnosis needs rethinking; buf well under the
## configured output_latency.web means that setting never landed; hitch bigger
## than buf means the main thread stalls longer than the buffer can cover.
##
## Caveat: backgrounding the tab suspends playback while wall-clock keeps
## running, so `drop` inflates after a tab switch. Reload to reset it.
func _hud_line() -> String:
	var fps := int(Performance.get_monitor(Performance.TIME_FPS))
	var dpr := "?"
	var raw = JavaScriptBridge.eval(
			"(function(){var r=window.__t5dpr;"
			+ "return r?((r.real||0)+'>'+(r.effective||0)):'n/a';}())", true)
	if raw != null:
		dpr = str(raw)
	var mix := ""
	var raw_mix = JavaScriptBridge.eval(
			"(function(){var a=window.__t5audio;"
			+ "return (a&&a.mix)?a.mix():'';}())", true)
	if raw_mix != null:
		mix = str(raw_mix)
	# Which playback mode this device resolved to (sample/stream/default).
	# Without this the per-platform split is invisible on the phone, and a UA
	# that fails to match would look exactly like a fix that did not work.
	return "%d fps  dpr %s  %s  pb %s" % [
			fps, dpr, mix, GameState.playback_mode_name()]


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
