extends MenuBase
## FLAPPY MIC: the second mini game — a Flappy Bird clone flown by the
## comedian you picked next door. The bird is a pigeon BODY wearing that
## comedian's HEAD, the same trick the plane's pilot pulls (plane_flyby.gd).
##
## NOTHING IS SCORED YET — not the pipes cleared, and not the SETUPs,
## PUNCHLINEs and TAGs floating between the stacks. Like the slot machine this
## is a shelf game: it never touches score, lives or the clock (see
## GameState.change_scene), so there is nothing here a client could hand
## itself. That matters most for the components, because the crafter's points
## are SERVER-owned (Leaderboard/jokeCrafterState) — the day these count, they
## count through an endpoint, not through GameState.add_component() from here.
##
## WHOSE HEAD. GameState.fight_character_index() decides, which is the same
## call FIGHT! makes: the persisted pick normally, and a FRESH random comedian
## every time the "?" card is the active selection — including on every retry,
## so the mystery survives a crash.
##
## LAYOUT. Everything is measured in the 640x360 design frame but pinned to
## the BOTTOM of the real viewport (stretch aspect is "expand", so the frame
## can be taller than 360). The backdrop is the game's own parallax stack —
## the same strips the street scrolls — which is why this screen matches
## whichever edition the build ships and costs no new art.

## The bird's two frames. Authored on one shared 84x94 canvas with the
## comedian's head landing on the SAME point in both, so a flap swaps one
## texture and nothing else moves.
const BODY_UP_ART := "res://shared/assets/minigames/flappy_body_up.png"
const BODY_DOWN_ART := "res://shared/assets/minigames/flappy_body_down.png"
## Where the head's CENTRE sits on that canvas. Also the rig's origin, so the
## whole bird tilts around its head rather than around a corner.
const HEAD_ANCHOR := Vector2(58, 40)
## Head files run from 48px pixel art to 2176px photos, so every head is
## normalized to one on-screen width — the same fix plane_flyby.gd applies to
## its pilot, including the roster's HeadScale zoom for tight crops. Big
## enough that the face is the thing you read at a glance — this is the whole
## joke, and at 30 it was a detail on a pigeon rather than a comedian flying.
const HEAD_PX := 45.0
## The bird's collision box in canvas pixels: the head and the trunk under it,
## sized off HEAD_PX (a 45px head centred on HEAD_ANCHOR spans 36..81). Wing
## tips and tail are deliberately OUTSIDE it — clipping a feather on a speaker
## cabinet reads as a near miss, and dying to one feels like a cheat.
const HIT_BOX := Rect2(36, 22, 42, 40)

## The obstacle: a stack of PA cabinets under a flared, bulb-lit cap.
##
## Every number below was MEASURED off flappy_pipe.png and is in that
## texture's own pixels, which are drawn 1:1 in the design frame. The texture
## is one cap plus one cabinet: PIPE_CAP is the slice drawn unstretched at the
## mouth, and everything under it is the single cabinet the NinePatch TILES,
## so a pipe of any length is whole cabinets and never a smeared one.
## Re-measure these if the art is ever regenerated.
const PIPE_ART := "res://shared/assets/minigames/flappy_pipe.png"
const PIPE_W := 74.0
const PIPE_CAP := 46.0
## The flared disc alone — the only part as wide as the texture. Below it the
## column is just the cabinet stack, which is narrower on both sides.
const PIPE_FLARE := 23.0
const PIPE_SHAFT_INSET := 13.0

## FLIGHT. Tuned so one flap climbs ~55px and a full gap takes about two of
## them: enough air to correct a bad tap, not enough to coast.
const GRAVITY := 1250.0
const FLAP_V := -370.0
const MAX_FALL := 560.0
## How fast the world comes at you, and how far apart the stacks stand.
## SPACING was 232 and is 15% wider now: 2.0s between stacks at SCROLL
## instead of 1.76s.
const SCROLL := 132.0
const SPACING := 267.0
## The hole between the two caps, and the dial the difficulty actually turns
## on: 116 was ~2.9 bird-heights and played tight once the head grew to 45px,
## so it is 20% taller at 139 — about 3.5 of them.
const GAP := 139.0
## Keep the hole off both edges so no gap opens against the sky or the floor.
const GAP_MARGIN := 62.0
## The bird flies at this fraction of the screen width, always.
const BIRD_X_FRAC := 0.28

## COLLECTIBLES. The JOKE CRAFTER's own components, and ComponentPickup is
## reused WHOLE for them — same art, same per-kind tints, same fake-3D spin and
## glint — so a SETUP looks like a SETUP wherever you meet it. Its Area2D never
## fires in this scene (nothing here carries the `fighter` meta it looks for),
## which is exactly what is wanted: collection is the same AABB test as
## everything else here, and nothing is tallied. See the header.
const COMPONENT_KINDS := ["setups", "punchlines", "tags"]
## How often a pair of columns gets one floating between it.
const COMPONENT_CHANCE := 0.75
## Its collect box — the street pickup's own 40x40 shape. Deliberately NOT
## narrowed as the sprite spins edge-on, for the reason component_pickup.gd
## gives: collecting one should never be a timing test.
const COMPONENT_BOX := Vector2(40, 40)
## How far off the line between two holes one may drift.
const COMPONENT_JITTER := 26.0
## Swell-and-fade when one is taken.
const COMPONENT_POP := 0.18

## The pavement in the street strip: its top edge is 60px up from the art's
## bottom, and the art is bottom-pinned, so this is the floor in any viewport.
const FLOOR_INSET := 60.0

## Nose-up while climbing, nose-down while dropping, lerped between the two.
const TILT_UP := -0.30
const TILT_DOWN := 1.15
const TILT_RATE := 7.0
## How long the wings stay raised after a flap before falling back down.
const FLAP_HOLD := 0.13
## Idle bob before the first tap, so the screen is never dead still.
const BOB_AMP := 6.0
const BOB_SPEED := 2.2
## A crash cannot be retried for this long: a tap already in flight when you
## hit a speaker should not skip the crash it just caused.
const RETRY_LOCK := 0.45
## THE FLAP BUTTON. Most people play this on a phone, so the one control gets
## the main game's own UP art at the main game's own size — and it is pulled
## from TouchControls rather than copied, so retuning the D-pad retunes this.
## It sits low on the left, where that D-pad lives, and its bottom edge lands
## on the safe line clear of the Android nav bar. Tapping ANYWHERE still flaps;
## the button is the affordance that says so on a screen with no keyboard.
const FLAP_BTN_ART := "res://shared/assets/ui/btn_up.png"
const FLAP_BTN_POS := Vector2(43, 313)

## Touch is emulated from mouse (and mouse from touch), so ONE press can
## arrive twice. Anything this close behind the last tap is that echo — no
## human double-taps inside 60ms.
const TAP_DEBOUNCE := 0.06

const GOLD := Color(1.0, 0.85, 0.4)

enum { READY, FLY, DEAD }

var _state := READY
var _bird_y := 0.0
var _vel := 0.0
var _tilt := 0.0
var _flap_t := 0.0
var _bob_t := 0.0
var _dead_t := 0.0
var _last_tap := -1.0
## Distance the world has travelled, which is all the parallax needs.
var _scroll := 0.0

## [{root: Control, tiles: Array[TextureRect], tex: Texture2D, w, h, factor}] —
## one repeating strip per parallax layer, furthest first.
var _layers: Array = []
## [{x, gap_y, top: NinePatchRect, bot: NinePatchRect, comp, comp_dx}] — gap_y
## is the TOP of the hole; `comp` is the component floating BEHIND this pair
## (null once taken or never rolled) and `comp_dx` its offset from this pair's
## x, so one number moves both. Oldest first; recycled off the left edge.
var _pipes: Array = []
var _pipes_root: Control
var _bird: Node2D
var _body: Sprite2D
var _head: Sprite2D
var _prompt: Label
var _flap_btn: TouchScreenButton
var _pipe_tex: Texture2D
var _pipe_tex_flipped: Texture2D
var _floor_y := 300.0
var _bird_x := 180.0


func _ready() -> void:
	# The play field must not eat taps: with the default filter the root Control
	# swallows every click before _unhandled_input ever sees it. Children (the
	# back button) still get theirs.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sky := ColorRect.new()
	sky.color = Color(0.08, 0.07, 0.12)
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	_build_layers()

	_pipes_root = Control.new()
	_pipes_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pipes_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pipes_root)

	_pipe_tex = load(PIPE_ART)
	# The top pipe is the same column hanging from the ceiling. Flipping the
	# IMAGE once beats flipping a Control every frame: a NinePatch with a
	# negative scale still lays its patches out the original way round.
	var img := _pipe_tex.get_image()
	img.flip_y()
	_pipe_tex_flipped = ImageTexture.create_from_image(img)

	_build_bird()

	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_prompt.offset_top = 46
	_prompt.offset_bottom = 74
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_font_size_override("font_size", 12)
	_prompt.add_theme_color_override("font_color", GOLD)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 6)
	add_child(_prompt)

	_build_flap_button()

	var back := add_back_button(func(): GameState.change_scene(GameState.SCENE_MINI_GAMES))
	# Never let the button take focus: a focused Button eats SPACE, which is
	# the same key that flaps.
	back.focus_mode = Control.FOCUS_NONE

	resized.connect(_layout)
	_layout()
	_reset()
	# The root Control has no size until the first layout pass, which can land
	# after _ready — so measure the frame once more when it does.
	call_deferred("_layout")


# ---------------------------------------------------------------- world
## The backdrop is the active game's own parallax stack — stars, twinkles,
## skyline, street — so this screen looks like the city the run walks through
## and needs no art of its own. A game without advancedParallax resolves to
## its single street tile, which scrolls just the same.
func _build_layers() -> void:
	for cfg in GameState.parallax_layers():
		var path := String(cfg["path"])
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		if tex == null:
			continue
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)
		_layers.append({
			"root": root,
			"tiles": [],
			"w": float(tex.get_width()),
			"h": float(tex.get_height()),
			"tex": tex,
			"factor": float(cfg["factor"]),
		})


## Enough copies of each strip to cover the viewport plus one spare on each
## side, bottom-pinned so the pavement always sits on the frame's floor no
## matter how tall the real viewport turned out.
func _layout() -> void:
	_floor_y = size.y - FLOOR_INSET
	_bird_x = floorf(size.x * BIRD_X_FRAC)
	for layer in _layers:
		var root: Control = layer["root"]
		var w: float = layer["w"]
		var want := int(ceilf(size.x / w)) + 2
		var tiles: Array = layer["tiles"]
		while tiles.size() > want:
			var extra: TextureRect = tiles.pop_back()
			extra.queue_free()
		while tiles.size() < want:
			var t := TextureRect.new()
			t.texture = layer["tex"]
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			t.size = Vector2(w, layer["h"])
			root.add_child(t)
			tiles.append(t)
		for t in tiles:
			t.position.y = size.y - layer["h"]
	for p in _pipes:
		_size_pipe(p)
	_place_layers()
	_place_flap_button()
	if _bird != null:
		_bird.position.x = _bird_x


## One strip's tiles are laid out as a ribbon and slid by the scrolled
## distance, wrapped into a single tile width. No per-tile recycling: the
## modulo IS the recycling, and it cannot drift.
func _place_layers() -> void:
	for layer in _layers:
		var w: float = layer["w"]
		var shift := fmod(_scroll * float(layer["factor"]), w)
		var tiles: Array = layer["tiles"]
		for i in tiles.size():
			tiles[i].position.x = i * w - shift - w


# ---------------------------------------------------------------- the bird
func _build_bird() -> void:
	_bird = Node2D.new()
	add_child(_bird)

	_body = Sprite2D.new()
	_body.centered = false
	_body.position = -HEAD_ANCHOR
	_bird.add_child(_body)

	_head = Sprite2D.new()
	_bird.add_child(_head)  # after the body, so the face is never behind a wing


## Load the head of whoever is flying. Called on every reset, because with the
## "?" card active fight_character_index() rolls a new comedian each time.
func _pick_pilot() -> void:
	var cfg: Dictionary = {}
	if not GameState.characters.is_empty():
		var idx := GameState.fight_character_index()
		cfg = GameState.characters[clampi(idx, 0, GameState.characters.size() - 1)]
	_head.texture = CharacterFactory.head_texture(String(cfg.get("HeadSpritePath", "")))
	var zoom := maxf(float(cfg.get("HeadScale", 1.0)), 0.1)
	var s := zoom * HEAD_PX / maxf(_head.texture.get_width(), 1.0)
	_head.scale = Vector2(s, s)


func _set_wings(up: bool) -> void:
	_body.texture = load(BODY_UP_ART if up else BODY_DOWN_ART)


# ---------------------------------------------------------------- run state
func _reset() -> void:
	for p in _pipes:
		p["top"].queue_free()
		p["bot"].queue_free()
		_free_component(p)
	_pipes.clear()
	_state = READY
	_vel = 0.0
	_tilt = 0.0
	_flap_t = 0.0
	_bob_t = 0.0
	_dead_t = 0.0
	_bird_y = size.y * 0.42
	_pick_pilot()
	_set_wings(false)
	_prompt.text = "TAP TO FLAP"
	_prompt.visible = true
	_sync_bird()


func _start() -> void:
	_state = FLY
	_prompt.visible = false
	# Two stacks already standing when the first flap lands, so the run opens
	# with something to aim at rather than a few seconds of empty sky.
	_spawn_pipe(size.x + 60.0)
	_spawn_pipe(size.x + 60.0 + SPACING)
	_flap()


func _flap() -> void:
	_vel = FLAP_V
	_flap_t = FLAP_HOLD
	_set_wings(true)
	GameState.play_sfx("swing")


func _crash() -> void:
	_state = DEAD
	_dead_t = 0.0
	_vel = minf(_vel, -120.0)  # a small bounce off whatever was hit
	_set_wings(false)
	GameState.play_sfx("smash")
	_prompt.text = "TAP TO TRY AGAIN"
	_prompt.visible = true


# ---------------------------------------------------------------- input
## A TouchScreenButton, like the main game's controls — not a Button — so a
## finger presses it the moment it lands rather than on release. Its press
## goes through the SAME debounced _tap() as a bare screen tap, which is what
## keeps the tap it also registers as a screen tap from flapping twice.
func _build_flap_button() -> void:
	if not ResourceLoader.exists(FLAP_BTN_ART):
		return
	_flap_btn = TouchScreenButton.new()
	_flap_btn.texture_normal = load(FLAP_BTN_ART)
	_flap_btn.scale = Vector2(TouchControls.SCALE, TouchControls.SCALE)
	_flap_btn.pressed.connect(_tap)
	add_child(_flap_btn)


func _place_flap_button() -> void:
	if _flap_btn == null:
		return
	# Same arithmetic as TouchControls._screen_pos for a left-hand button:
	# scaled out from the left edge, hung off the LIVE bottom edge.
	_flap_btn.position = Vector2(
			FLAP_BTN_POS.x * TouchControls.SCALE,
			size.y - GameState.SAFE_BOTTOM
					- (TouchControls.DESIGN_H - FLAP_BTN_POS.y) * TouchControls.SCALE)


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed
					and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventKey and event.pressed and not event.echo
					and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_UP, KEY_W])
	if not pressed:
		return
	_tap()


## One entry point for every way of saying "flap", debounced.
func _tap() -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now - _last_tap < TAP_DEBOUNCE:
		return
	_last_tap = now
	match _state:
		READY:
			_start()
		FLY:
			_flap()
		DEAD:
			if _dead_t >= RETRY_LOCK:
				GameState.play_sfx("click")
				_reset()


# ---------------------------------------------------------------- frame
func _process(delta: float) -> void:
	if _state != DEAD:
		_scroll += SCROLL * delta
		_place_layers()
	if _state == FLY:
		_advance_pipes(delta)
		_collect_components()
	_advance_bird(delta)
	_sync_bird()


func _advance_bird(delta: float) -> void:
	if _flap_t > 0.0:
		_flap_t -= delta
		if _flap_t <= 0.0:
			_set_wings(false)

	if _state == READY:
		_bob_t += delta
		_bird_y = size.y * 0.42 + sin(_bob_t * BOB_SPEED * TAU) * BOB_AMP
		return

	_vel = minf(_vel + GRAVITY * delta, MAX_FALL)
	_bird_y += _vel * delta

	if _state == DEAD:
		_dead_t += delta
		# Dead birds nose over and stay down once they land.
		_tilt = minf(_tilt + TILT_RATE * delta, PI * 0.5)
		var rest := _floor_y + 6.0 + HEAD_ANCHOR.y - HIT_BOX.position.y - HIT_BOX.size.y
		if _bird_y >= rest:
			_bird_y = rest
			_vel = 0.0
		return

	# A ceiling you bump rather than die on, the way the original plays.
	var top := HEAD_ANCHOR.y - HIT_BOX.position.y
	if _bird_y < top:
		_bird_y = top
		_vel = maxf(_vel, 0.0)

	var want := lerpf(TILT_UP, TILT_DOWN, clampf(_vel / MAX_FALL, 0.0, 1.0)) \
			if _vel > 0.0 else TILT_UP
	_tilt = lerpf(_tilt, want, clampf(TILT_RATE * delta, 0.0, 1.0))

	if _hit_anything():
		_crash()


func _sync_bird() -> void:
	_bird.position = Vector2(_bird_x, _bird_y)
	_bird.rotation = _tilt


## The bird's box in screen space. Rotation is deliberately NOT applied: a
## tilting hitbox makes a fair-looking gap unfair at the extremes, and every
## flappy clone worth playing collides the upright box.
func _bird_rect() -> Rect2:
	return Rect2(Vector2(_bird_x, _bird_y) - HEAD_ANCHOR + HIT_BOX.position, HIT_BOX.size)


func _hit_anything() -> bool:
	var box := _bird_rect()
	if box.position.y + box.size.y >= _floor_y:
		return true
	for p in _pipes:
		for r in _pipe_rects(p):
			if box.intersects(r):
				return true
	return false


# ---------------------------------------------------------------- pickups
## Fly through one and it pops. It is taken off its pair's record rather than
## freed on the spot, so the swell-and-fade can finish on a node nothing is
## still testing against.
func _collect_components() -> void:
	var box := _bird_rect()
	for p in _pipes:
		# Typed, not inferred: these come out of an untyped Dictionary, and a
		# Variant has no create_tween() for the parser to infer a Tween from.
		var comp: Node2D = p["comp"]
		if comp == null or not is_instance_valid(comp):
			continue
		if not box.intersects(Rect2(comp.position - COMPONENT_BOX / 2.0, COMPONENT_BOX)):
			continue
		p["comp"] = null
		GameState.play_sfx("clear")
		# The tween is created ON the pickup, so it dies with the scene rather
		# than outliving it holding a freed node.
		var tw: Tween = comp.create_tween().set_parallel()
		tw.tween_property(comp, "scale", Vector2(1.7, 1.7), COMPONENT_POP)
		tw.tween_property(comp, "modulate:a", 0.0, COMPONENT_POP)
		tw.chain().tween_callback(comp.queue_free)


func _free_component(p: Dictionary) -> void:
	var comp: Node2D = p.get("comp")
	if comp != null and is_instance_valid(comp):
		comp.queue_free()
	p["comp"] = null


# ---------------------------------------------------------------- pipes
func _spawn_pipe(at_x: float) -> void:
	var lo := GAP_MARGIN
	var hi := _floor_y - GAP - GAP_MARGIN
	var gap_y := randf_range(lo, maxf(lo, hi))

	var top := NinePatchRect.new()
	top.texture = _pipe_tex_flipped
	top.patch_margin_bottom = int(PIPE_CAP)
	top.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.position = Vector2(at_x, gap_y - PIPE_CAP)
	top.size = Vector2(PIPE_W, 0)
	_pipes_root.add_child(top)

	var bot := NinePatchRect.new()
	bot.texture = _pipe_tex
	bot.patch_margin_top = int(PIPE_CAP)
	bot.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot.position = Vector2(at_x, gap_y + GAP)
	bot.size = Vector2(PIPE_W, 0)
	_pipes_root.add_child(bot)

	var rec := {"x": at_x, "gap_y": gap_y, "top": top, "bot": bot,
			"comp": null, "comp_dx": 0.0}
	_size_pipe(rec)
	_pipes.append(rec)
	_maybe_add_component(rec)


## One component floating midway between the PREVIOUS pair of columns and this
## one, at the midpoint of the two holes — i.e. sitting on the line the bird
## already has to fly to get from one to the other, so taking it is a nudge
## rather than a detour. It is placed when the second pipe spawns precisely
## because that is the first moment both ends of that line are known.
func _maybe_add_component(rec: Dictionary) -> void:
	if _pipes.size() < 2 or randf() > COMPONENT_CHANCE:
		return
	var prev: Dictionary = _pipes[_pipes.size() - 2]
	var x := (float(prev["x"]) + float(rec["x"])) / 2.0 + PIPE_W / 2.0
	var y := (float(prev["gap_y"]) + float(rec["gap_y"])) / 2.0 + GAP / 2.0
	y = clampf(y + randf_range(-COMPONENT_JITTER, COMPONENT_JITTER),
			GAP_MARGIN, _floor_y - GAP_MARGIN)
	var comp := ComponentPickup.new()
	comp.kind = COMPONENT_KINDS[randi() % COMPONENT_KINDS.size()]
	comp.position = Vector2(x, y)
	_pipes_root.add_child(comp)
	rec["comp"] = comp
	rec["comp_dx"] = x - float(rec["x"])


## Both columns run off their own edge of the screen, so their lengths depend
## on where the hole sits and how tall the viewport is.
func _size_pipe(p: Dictionary) -> void:
	var gap_y: float = p["gap_y"]
	var top: NinePatchRect = p["top"]
	var bot: NinePatchRect = p["bot"]
	# Both are at least one cap tall: a NinePatch shorter than its margins
	# squashes the cap, and a squashed cap is the one part you aim at.
	top.size = Vector2(PIPE_W, maxf(gap_y, PIPE_CAP))
	top.position = Vector2(p["x"], gap_y - top.size.y)
	bot.position = Vector2(p["x"], gap_y + GAP)
	bot.size = Vector2(PIPE_W, maxf(size.y - (gap_y + GAP), PIPE_CAP))


## The two boxes a column is worth: the flared cap at full texture width, and
## the narrower cabinet stack behind it. Splitting them is what lets a bird
## tuck in close to the stack without being killed by the overhang above it.
func _pipe_rects(p: Dictionary) -> Array:
	var x: float = p["x"]
	var gap_y: float = p["gap_y"]
	var sx := x + PIPE_SHAFT_INSET
	var sw := PIPE_W - PIPE_SHAFT_INSET * 2.0
	var bot_y := gap_y + GAP
	return [
		# top column: stack hanging from the ceiling, then its cap
		Rect2(sx, 0.0, sw, maxf(gap_y - PIPE_FLARE, 0.0)),
		Rect2(x, maxf(gap_y - PIPE_FLARE, 0.0), PIPE_W, minf(PIPE_FLARE, gap_y)),
		# bottom column: cap, then the stack down to the floor
		Rect2(x, bot_y, PIPE_W, PIPE_FLARE),
		Rect2(sx, bot_y + PIPE_FLARE, sw, maxf(size.y - bot_y - PIPE_FLARE, 0.0)),
	]


func _advance_pipes(delta: float) -> void:
	var step := SCROLL * delta
	var right := -INF
	for p in _pipes:
		p["x"] -= step
		p["top"].position.x = p["x"]
		p["bot"].position.x = p["x"]
		var comp: Node2D = p["comp"]
		if comp != null and is_instance_valid(comp):
			comp.position.x = p["x"] + p["comp_dx"]
		right = maxf(right, p["x"])

	while not _pipes.is_empty() and _pipes[0]["x"] + PIPE_W < -20.0:
		var gone: Dictionary = _pipes.pop_front()
		gone["top"].queue_free()
		gone["bot"].queue_free()
		_free_component(gone)

	if _pipes.is_empty():
		_spawn_pipe(size.x + 60.0)
	elif right < size.x - SPACING:
		_spawn_pipe(right + SPACING)
