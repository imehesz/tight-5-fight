extends Node2D
## The Street Phase: infinite scrolling street with random hecklers and
## periodically spawning venues. Walk to a venue door and press up to enter.

const GROUND_Y := 310.0
## Copies of each background layer kept alive. Five of the old 320px street
## tile has always covered the view (±480) with a tile spare at either end;
## wider layer art only ever covers more, so one count fits every layer.
const TILE_COUNT := 5
## How far past the camera a tile may sit before it wraps to the far end of
## its own strip.
const TILE_MARGIN := 480.0
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
## Chance that any given venue gap grows a sponsor billboard (when the hosted
## sponsor roster has anyone active for this game). WHICH sponsor fills the
## slot is Sponsors.pick_weighted().
const BILLBOARD_CHANCE := 0.75
## FOREGROUND DRESSING (StreetDecor): the strip between the fighters' feet
## (GROUND_Y) and the bottom of the 640x360 frame. Everything here is in front
## of the fighters because it is nearer the camera, and none of it collides
## with anything — it exists to stop the pavement reading as empty.
##
## The band stops short of the very bottom on purpose: on a phone the last
## dozen-odd pixels sit under the Android nav bar, and a rat that scurries
## through there is a rat nobody sees.
const DECOR_Y_MIN := 320.0
const DECOR_Y_MAX := 342.0
## Litter dropped into each venue gap as it is generated: a count roll, so most
## stretches get a piece or two and some get none.
const LITTER_PER_GAP_MAX := 3
## Critters (rats) come through on a timer, one at a time. Rare enough to stay
## a detail you notice rather than an infestation.
const CRITTER_WAIT_MIN := 7.0
const CRITTER_WAIT_MAX := 18.0
const CRITTER_MAX_ON_SCREEN := 1
## Where a critter enters, as a distance from the camera — just past the
## +/-320 the camera sees, so one is never seen popping into existence.
const CRITTER_EDGE_X := 370.0
## And where it stops existing, same measure. This is CAMERA-relative on
## purpose. An exit at a fixed world x looks right until the player walks the
## same way a rat is leaving: the camera keeps pace with the rat, the rat
## reaches its world-space exit while still in frame, and vanishes in plain
## sight. Freeing on distance-from-camera instead means the removal is always
## off-screen, whatever the player does. Must stay comfortably above
## CRITTER_EDGE_X or a critter would be culled the frame it spawned.
const CRITTER_GONE_X := 430.0
## How far off-camera venue and billboard NODES are allowed to live.
##
## The street never ends, so anything built per-venue and kept forever grows
## without bound for as long as the player keeps walking — and on iOS Safari,
## which kills a tab on its memory footprint, "without bound" eventually means
## the whole page dies and restarts itself. So the records (where a venue is,
## which one it is, whether it's been cleared) are kept for the entire run —
## they are a few bytes each — while the nodes behind them are built on
## approach and freed on the way out. A marathon run now costs the same as the
## first minute.
##
## The gap between the two is hysteresis: with a single threshold, standing
## exactly on the line would rebuild and free the same venue every frame. The
## camera sees ±320, so even STREAM_IN_X is well out of sight.
const STREAM_IN_X := 640.0
const STREAM_OUT_X := 900.0

var player: Player
var camera: Camera2D
var hud: Hud

## [{root: Node2D, tiles: Array, w: float, factor: float}] — one repeating
## strip per parallax layer, furthest first. Legacy games have exactly one.
var _layers: Array = []
## [{x, data, cleared, ext, sign, tape}] — the node fields are null whenever
## the venue is streamed out. Never pruned: the player can always walk back.
var _doors: Array = []
## [{x, id, sponsor, counted, variant, tilt, node}] — same contract, node null
## while streamed out.
var _billboards: Array = []
## [{x, y, id, flip, node}] — foreground litter. Same records-plus-streaming
## contract as the billboards, and saved with the street, so the trash stays
## put across a venue visit instead of being re-scattered on the way out.
var _litter: Array = []
var _next_venue_x := FIRST_VENUE_X
var _venue_index := 0
var _spawn_timer := 2.0
## The run's opening heckler is guaranteed hostile, so combat gets
## demonstrated immediately; cleared once spent (or on a restored street).
var _first_heckler := true
var _beer_timer := 3.0
var _plane_timer := randf_range(4.0, PLANE_FIRST_WAIT_MAX)
var _critter_timer := randf_range(3.0, CRITTER_WAIT_MAX)
var _plane: PlaneFlyby
var _hint_sign: Node2D
## Whichever teaching popup is up — the welcome one on the run's first frame,
## or the doorway one later. Non-null means the game is frozen behind it,
## which is also what stops a second one being built every frame, and what
## keeps the doorway lesson from stacking on top of the welcome. The flag
## below is the doorway lesson's own "already spent this scene": without it,
## an editor run (where the lesson is always due) would pop it again the
## frame after it closes, since the player is still standing in the doorway.
var _hint_popup: HintPopup
var _hint_shown := false
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
	GameState.time_expired.connect(_on_time_expired)

	# Best-effort retry: a boot-time fetch failure (offline blip) shouldn't
	# cost the whole session its billboards.
	Sponsors.ensure_loaded()

	var saved: Dictionary = GameState.street_state
	if saved.has("doors"):
		# Returning from a venue: rebuild the street exactly as it was.
		_next_venue_x = float(saved.next_venue_x)
		_venue_index = int(saved.venue_index)
		# Records only — not one node. Whatever is actually near the player
		# gets built by the streaming pass at the end of _ready(), so coming
		# back out of the tenth venue costs the same as coming out of the
		# first (it used to rebuild every venue of the run, all at once).
		for d in saved.doors:
			_place_venue(float(d.x), d.data, bool(d.cleared))
		# Billboards restore with their counted flag, so a re-walk past a
		# restored board never bills a second impression.
		for b in saved.get("billboards", []):
			var sponsor: Dictionary = Sponsors.by_id(String(b.id))
			if not sponsor.is_empty():
				_place_billboard(float(b.x), sponsor, bool(b.counted),
						String(b.get("variant", "")), float(b.get("tilt", 0.0)))
		# Litter restores by id: a prop dropped from the roster mid-session
		# simply stops being scattered, it never leaves a hole to crash on.
		for l in saved.get("litter", []):
			if not StreetDecor.litter_by_id(String(l.id)).is_empty():
				_place_litter(float(l.x), float(l.y), String(l.id), bool(l.flip))
		_spawn_player(Vector2(float(saved.player_x), GROUND_Y))
		# Mid-run pacing is untouched: no fast spawn, no forced aggression.
		_first_heckler = false
	else:
		_spawn_player(Vector2(120, GROUND_Y))
		# Dress the opening stretch too. Litter is otherwise only scattered
		# into the gap behind each new venue, and the first venue is at
		# FIRST_VENUE_X — so without this the one piece of street every single
		# run begins on is the one piece with nothing on it.
		_scatter_litter(60.0, FIRST_VENUE_X)
		_spawn_timer = 0.5  # first heckler shows up almost immediately
		# Goal hint, only at the very start of a run — venues_entered, not
		# "fresh street", so walking back out of venue 1 stays hint-free.
		if GameState.venues_entered == 0:
			_spawn_hint_sign()
			_show_intro_hint()
	camera.position = Vector2(maxf(player.position.x, 320.0), 180.0)
	camera.reset_smoothing()
	# Before the first frame is drawn, so a restored street opens with its
	# scenery already standing instead of popping in a frame later. Same for
	# the background: the layer roots are built at x = 0, so without this a
	# street resumed deep into a run shows one frame of unscrolled sky.
	_recycle_tiles()
	_stream_props()
	# Walking back out of a venue with the clock already at 0:00 (it can expire
	# during the "YOU SURVIVED!" beat): the signal fired while this scene did
	# not exist yet, so collapse the player on arrival instead.
	if GameState.time_up():
		_on_time_expired()


func _process(delta: float) -> void:
	if is_instance_valid(player):
		player.position.x = maxf(player.position.x, 20.0)
		camera.position = Vector2(maxf(player.position.x, 320.0), 180.0)
	_recycle_tiles()
	_stream_props()
	_maybe_spawn_venue()
	_maybe_spawn_heckler(delta)
	_maybe_spawn_beer(delta)
	_maybe_spawn_plane(delta)
	_maybe_spawn_critter(delta)
	_cull_stragglers()
	_update_door_signs()
	_maybe_show_venue_hint()


# ---------------------------------------------------------------- world
## Build the scrolling background: one strip of repeating sprites per parallax
## layer, furthest first. A game without advancedParallax resolves to a single
## factor-1.0 layer, so the old look costs exactly the nodes it always did.
func _build_tiles() -> void:
	for cfg in GameState.parallax_layers():
		var tex: Texture2D = load(String(cfg["path"]))
		if tex == null:
			continue
		# One root per layer, because the parallax offset is applied to the
		# root — the sprites underneath only ever deal with their own strip.
		var root := Node2D.new()
		root.z_index = int(cfg["z"])
		add_child(root)
		var w := float(tex.get_width())
		var tiles: Array = []
		for i in TILE_COUNT:
			var t := Sprite2D.new()
			t.texture = tex
			t.centered = false
			t.position = Vector2(i * w, 0)
			root.add_child(t)
			tiles.append(t)
		_layers.append({"root": root, "tiles": tiles, "w": w, "factor": float(cfg["factor"])})
		var period := float(cfg.get("twinkle", 0.0))
		if period > 0.0:
			_start_twinkle(root, period, float(cfg.get("twinkle_min", 0.15)))


## Fade a whole strip out and back, forever.
##
## Only the twinkle strips get this, and they hold NOTHING but the stars that
## blink — the steady stars and the night sky itself are on the opaque layer
## underneath, which is what keeps a fade from dimming the sky along with them.
## Two strips running different periods read as a shimmer; one strip on its own
## reads as the whole sky pulsing, which is why the art comes in a pair.
##
## The tween is created ON the strip, so it dies with the scene when the player
## walks into a venue — no manual cleanup, and no tween left running against a
## freed node.
func _start_twinkle(root: Node2D, period: float, min_alpha: float) -> void:
	var half := period * 0.5
	root.modulate.a = min_alpha
	var tw := root.create_tween().set_loops()
	tw.tween_property(root, "modulate:a", 1.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(root, "modulate:a", min_alpha, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Scroll and wrap every background layer.
##
## A layer with factor f should drift past at f × the player's speed, which
## falls straight out of parking its root at cam × (1 - f): a tile then lands
## on screen at (local x - cam × f), so the strip is recycled against that same
## scaled camera position, in the layer's OWN tile width. The street layer is
## just the f = 1.0 case — root pinned at 0, tiles wrapped against the real
## camera, exactly what the single tile has always done.
##
## Note this reads the camera's RENDERED centre, not camera.position: smoothing
## is on (speed 6.0), so camera.position is merely the target the camera is
## still travelling toward, and driving parallax off the target makes the
## background lead the street on every start and stop.
func _recycle_tiles() -> void:
	var cam := camera.get_screen_center_position().x
	for layer in _layers:
		var f: float = layer["factor"]
		var w: float = layer["w"]
		var span := w * TILE_COUNT
		var eye := cam * f
		if f != 1.0:
			var root: Node2D = layer["root"]
			root.position.x = cam - eye
		for t in layer["tiles"]:
			while t.position.x + w < eye - TILE_MARGIN:
				t.position.x += span
			while t.position.x > eye + TILE_MARGIN:
				t.position.x -= span


func _maybe_spawn_venue() -> void:
	if camera.position.x + 700.0 < _next_venue_x:
		return
	var placed_x := _next_venue_x
	_place_venue(placed_x, GameState.venue_data_for_index(_venue_index), false)
	_venue_index += 1
	_next_venue_x += randf_range(VENUE_SPACING_MIN, VENUE_SPACING_MAX)
	_maybe_spawn_billboard(placed_x, _next_venue_x)
	_scatter_litter(placed_x, _next_venue_x)


## Roll a sponsor billboard into the gap that just opened between the venue
## placed at gap_start and the next one. Mid-gap ±80 keeps it clear of both
## exteriors (min gap 1100, exterior half-width ~160). Same-sponsor repeats
## across gaps are fine — the street cycles everything.
func _maybe_spawn_billboard(gap_start: float, gap_end: float) -> void:
	if randf() > BILLBOARD_CHANCE:
		return
	var sponsor: Dictionary = Sponsors.pick_weighted()
	if sponsor.is_empty():
		return
	_place_billboard((gap_start + gap_end) / 2.0 + randf_range(-80.0, 80.0), sponsor, false)


## Drop foreground litter across the gap that just opened between this venue
## and the next. Positions are rolled once, here, and then belong to the run:
## the nodes come and go with the camera but the trash never moves.
func _scatter_litter(gap_start: float, gap_end: float) -> void:
	for _i in randi() % (LITTER_PER_GAP_MAX + 1):
		var row: Dictionary = StreetDecor.pick_litter()
		if row.is_empty():
			return  # nothing in the roster has usable art; don't keep rolling
		_place_litter(randf_range(gap_start, gap_end),
				randf_range(DECOR_Y_MIN, DECOR_Y_MAX), String(row.id),
				randf() < 0.5)


## Record a piece of litter. Like the billboards, nothing is built until the
## camera comes near. `flip` is rolled once and kept so a piece that streams
## out and back in is the same piece, not a mirrored one.
func _place_litter(lx: float, ly: float, id: String, flip: bool) -> void:
	_litter.append({"x": lx, "y": ly, "id": id, "flip": flip, "node": null})


## Send a critter (a rat) across the foreground. Nothing is recorded and
## nothing is persisted: it runs in, stops to look around, heads back out and
## is culled the moment it clears the frame. A run's rats are not part of the
## street the way its trash is — they are weather.
func _maybe_spawn_critter(delta: float) -> void:
	_critter_timer -= delta
	if _critter_timer > 0.0:
		return
	_critter_timer = randf_range(CRITTER_WAIT_MIN, CRITTER_WAIT_MAX)
	if get_tree().get_nodes_in_group("street_critters").size() >= CRITTER_MAX_ON_SCREEN:
		return
	var row: Dictionary = StreetDecor.pick_critter()
	if row.is_empty():
		return
	var cam := camera.position.x
	var side := 1.0 if randf() < 0.5 else -1.0
	# Most of them duck back the way they came — a rat thinking better of it —
	# and the rest carry straight on across the frame.
	var exit_side := side if randf() < 0.65 else -side
	var critter := StreetCritter.new()
	critter.add_to_group("street_critters")
	critter.z_index = 5  # foreground: in front of the fighters (0), like the venue crowd
	add_child(critter)
	# The exit target only sets which way it heads out — far enough that it is
	# always the camera-relative cull below that actually frees it.
	critter.configure(row, randf_range(DECOR_Y_MIN, DECOR_Y_MAX),
			cam + side * CRITTER_EDGE_X,
			cam + randf_range(-220.0, 220.0),
			cam + exit_side * 900.0)


# ---------------------------------------------------------------- streaming
## Record a billboard's existence. Nothing is built until the camera nears it.
func _place_billboard(bx: float, sponsor: Dictionary, counted: bool,
		variant := "", tilt := 0.0) -> void:
	_billboards.append({
		"x": bx,
		"id": String(sponsor.get("id", "")),
		"sponsor": sponsor,
		"counted": counted,
		"variant": variant,
		"tilt": tilt,
		"node": null,
	})


## Record a venue's existence. Same deal — the door works off this record, so
## a venue the player can reach is never merely "not built yet".
func _place_venue(vx: float, data: Dictionary, cleared: bool) -> void:
	_doors.append({
		"x": vx, "data": data, "cleared": cleared,
		"ext": null, "sign": null, "tape": null,
	})


## Build and free scenery as the camera comes and goes. This is the whole
## point of the records above: node count on the street is now a function of
## how much is on screen, not of how far the player has walked.
func _stream_props() -> void:
	var cam := camera.position.x
	for d in _doors:
		var dist := absf(float(d.x) - cam)
		if dist <= STREAM_IN_X:
			if d.ext == null:
				_build_venue_nodes(d)
		elif dist > STREAM_OUT_X and d.ext != null:
			_free_venue_nodes(d)
	for b in _billboards:
		var dist := absf(float(b.x) - cam)
		if dist <= STREAM_IN_X:
			if b.node == null:
				_build_billboard_node(b)
		elif dist > STREAM_OUT_X and b.node != null:
			_free_billboard_node(b)
	for l in _litter:
		var dist := absf(float(l.x) - cam)
		if dist <= STREAM_IN_X:
			if l.node == null:
				_build_litter_node(l)
		elif dist > STREAM_OUT_X and l.node != null:
			l.node.queue_free()
			l.node = null


## Litter carries no live state (nothing counts it, nothing changes it), so
## unlike a billboard it can be thrown away and rebuilt from its record alone.
func _build_litter_node(l: Dictionary) -> void:
	var row: Dictionary = StreetDecor.litter_by_id(String(l.id))
	var tex: Texture2D = StreetDecor.texture(row) if not row.is_empty() else null
	if tex == null:
		return
	var sp := Sprite2D.new()
	sp.texture = tex
	var sc := float(row.scale)
	sp.scale = Vector2(sc, sc)
	sp.flip_h = bool(l.flip)
	# Sitting ON the pavement: the record's y is the ground line, so the sprite
	# centre goes half a (scaled) height above it.
	sp.position = Vector2(float(l.x), float(l.y) - tex.get_height() * sc * 0.5)
	sp.z_index = 4  # foreground, but under the critters — a rat runs OVER the paper
	add_child(sp)
	l.node = sp


func _build_billboard_node(b: Dictionary) -> void:
	var board := Billboard.new()
	board.configure(b.sponsor, bool(b.counted), String(b.variant), float(b.tilt))
	board.position = Vector2(float(b.x), GROUND_Y)
	add_child(board)
	# configure() rolls the variant and tilt itself the first time it sees a
	# board. Keep what it chose, or a billboard that streams out and back in
	# would be a different billboard every time.
	b.variant = board.variant
	b.tilt = board.tilt_deg
	b.node = board


func _free_billboard_node(b: Dictionary) -> void:
	var board: Billboard = b.node
	if is_instance_valid(board):
		# The impression flag lives on the node while it exists; take it back
		# before the node goes, or a re-streamed board would bill its sponsor
		# a second time for the same walk-by.
		b.counted = board.counted
		board.queue_free()
	b.node = null


func _build_venue_nodes(d: Dictionary) -> void:
	var vx := float(d.x)
	var data: Dictionary = d.data
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
	sign.visible = not d.cleared
	add_child(sign)

	d.ext = ext
	d.sign = sign
	d.tape = _make_cancelled_tape(vx) if d.cleared else null


func _free_venue_nodes(d: Dictionary) -> void:
	for key in ["ext", "sign", "tape"]:
		var node: Node = d[key]
		if is_instance_valid(node):
			node.queue_free()
		d[key] = null


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


## The CANCELLED banner across a venue the player has already cleared. Returns
## the node so the venue that owns it can free it when it streams out.
func _make_cancelled_tape(vx: float) -> Node2D:
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
	return tape


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
		# Streamed out: there is nothing to bob or brighten.
		if not is_instance_valid(sign):
			continue
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
	# This is how a critter normally leaves: it runs out of frame and is freed
	# once it is CRITTER_GONE_X from the camera. Doing it here rather than in
	# the critter itself is what keeps the removal off-screen no matter which
	# way the player walks (see CRITTER_GONE_X). It also mops up one the
	# player simply walked away from mid-scurry.
	for c in get_tree().get_nodes_in_group("street_critters"):
		if absf(c.position.x - camera.position.x) > CRITTER_GONE_X:
			c.queue_free()


## Screen shake: MUST tween camera.offset, never camera.position — _process
## overwrites position with the camera-follow code every frame. If a second
## shake arrives mid-shake the new tween simply wins; both end at ZERO.
func _on_shake(px: float) -> void:
	var tw := create_tween()
	for i in 4:
		tw.tween_property(camera, "offset",
				Vector2(randf_range(-px, px), randf_range(-px, px)), 0.04)
	tw.tween_property(camera, "offset", Vector2.ZERO, 0.04)


## The first time the player ever stands in a doorway, freeze the game and
## explain the key — nothing on screen says a door is enterable, and a
## first-timer can walk past every venue in the run without finding out.
## Shown once per save (GameState persists it), never during a fight, and
## never while the street is mid-transition.
## The welcome popup, shown once ever, on a player's very first run. Same
## freeze-and-explain treatment as the doorway lesson below, and the same
## "always due in the editor, once ever in a real build" rule
## (GameState.intro_hint_due(), plus ?hints=1 on the web).
##
## Called from _ready() on a FRESH street only, and only with no venue entered
## yet, so it can never interrupt a run in progress — walking back out of a
## venue, or restarting after game over, both leave it alone.
func _show_intro_hint() -> void:
	if not GameState.intro_hint_due():
		return
	_hint_popup = HintPopup.new()
	# menu_title(), not a literal: every edition of the game shares this scene
	# and each one has its own name in game.json.
	_hint_popup.title_text = "WELCOME TO %s" % GameState.menu_title()
	_hint_popup.body_text = "FIGHT HECKLERS AND RIVAL COMEDIANS" \
			+ "\nON THE STREET AND IN THE VENUES." \
			+ "\n(Use WASD and UIJK on PC)" \
			+ "\n\nGOOD LUCK!"
	# Paused BEFORE the popup enters the tree, so the run's very first frame
	# is already frozen: the clock does not tick and the opening heckler does
	# not close in while the player is still reading.
	GameState.set_paused(true)
	add_child(_hint_popup)
	# Only now is the greeting spent — marking it before the popup was really
	# up would burn the one showing it ever gets on any failure along the way.
	GameState.mark_intro_hint_seen()


## The first-run doorway lesson: freeze the game and explain the UP key.
## Deliberately as dumb as it can be — standing at an open door is the whole
## condition. Every extra guard this had (no heckler within 150px, then 70px,
## not mid-punch) looked sensible and, between them, kept the popup from ever
## appearing: hecklers spawn from the run's first half-second and follow the
## player, so one is nearly always near a door. Being frozen next to a heckler
## is a far smaller problem than a lesson that never fires. Shown once per
## street scene, so it does not re-fire while the player stands in the doorway
## reading it; whether it is owed at all is GameState.venue_hint_due()
## (always, in the editor — once ever, in a real build).
func _maybe_show_venue_hint() -> void:
	# is_instance_valid, not a null check: queue_free leaves the reference
	# pointing at a freed object rather than nulling it.
	if _busy or _hint_shown or is_instance_valid(_hint_popup) \
			or not GameState.venue_hint_due():
		return
	if not is_instance_valid(player) or not _at_open_door():
		return
	_hint_shown = true
	_hint_popup = HintPopup.new()
	_hint_popup.title_text = "THAT'S A VENUE"
	_hint_popup.body_text = "PRESS UP (OR W) TO STEP INSIDE." \
			+ "\n\nCLEARING A VENUE PAYS SCORE" \
			+ "\nAND GIVES YOU AN EXTRA 20 SECONDS \nTO BOMB :P"
	# Paused BEFORE the popup enters the tree, so the frame it appears on is
	# already frozen — no free step through the door underneath it.
	GameState.set_paused(true)
	add_child(_hint_popup)
	# Only now is the lesson spent. Marking it before the popup was really up
	# meant any failure on the way in burned the one showing it ever gets.
	GameState.mark_venue_hint_seen()
	# The on-screen D-pad is inert while the tree is paused, but it is still
	# drawn under the popup — and its UP button IS the "enter venue" control.
	# Hiding it while the lesson is up keeps a stray tap near it from reading
	# as "go inside" the instant the game resumes.
	for c in get_children():
		if c is TouchControls:
			c.visible = false
			_hint_popup.closed.connect(func():
				if is_instance_valid(c):
					c.visible = true)


func _at_open_door() -> bool:
	for d in _doors:
		if not d.cleared and absf(player.position.x - float(d.x)) <= DOOR_HALF_WIDTH:
			return true
	return false


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
	var billboards: Array = []
	for b in _billboards:
		# A streamed-in board's `counted` flag is live on the node; the record
		# only becomes authoritative again once the node is freed.
		var counted: bool = b.node.counted if is_instance_valid(b.node) else bool(b.counted)
		billboards.append({"x": b.x, "id": b.id, "counted": counted,
				"variant": b.variant, "tilt": b.tilt})
	var litter: Array = []
	for l in _litter:
		litter.append({"x": l.x, "y": l.y, "id": l.id, "flip": l.flip})
	return {
		"player_x": player.position.x,
		"next_venue_x": _next_venue_x,
		"venue_index": _venue_index,
		"doors": doors,
		"billboards": billboards,
		"litter": litter,
	}


## 0:00 — the player drops where they stand. Nothing else to do: `died` fires
## from kill(), _on_player_died() runs as usual and lose_life() reports the run
## over because the clock is out, so it lands on the normal game-over flow.
func _on_time_expired() -> void:
	if is_instance_valid(player):
		player.kill()


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
