class_name TouchControls
extends CanvasLayer
## Virtual on-screen controls for mobile landscape: D-pad on the left
## (up = enter doors, down = duck), punch/kick/throw/swing buttons on the
## right. Buttons emit the same input actions as the keyboard bindings.

const SCALE := 1.95
## Movement and attack clusters run the SAME size. They used to differ (the
## D-pad at 1.5, attacks 1.3x bigger on the theory that thumbs hunt for the
## attack cluster mid-brawl) but on a real phone that left the D-pad too
## small to hit reliably, which is the one control you are holding constantly.
## Kept as its own name so the two clusters can diverge again without
## re-touching every entry in BUTTONS.
const ACTION_SCALE := SCALE
## Positions are the original 1x layout for 40px buttons on the 640x360
## viewport; _ready() scales each corner cluster outward from its screen
## corner so margins grow proportionally and nothing hangs off-screen.
## Both clusters were shoved 13px further out toward their own screen edge —
## the whole group, one shared offset, so the spacing WITHIN each cluster is
## untouched. 13 is where "80% closer to the edge" lands: each cluster used to
## keep a 16px design margin (31px on screen at SCALE), and 16 - 13 = 3 leaves
## a fifth of it, about 6px on screen.
##
## Two things that buys, worth knowing before shoving them out any further:
## the right cluster's halo is _GLOW_PAD (6px) wide, so its outer edge now
## falls off-screen and the glow is clipped on that side; and the D-pad now
## sits inside the strip where iOS reads a drag from the edge as a back-swipe.
const BUTTONS := [
	# LEFT/RIGHT are pulled 4px in from their old 12/100 so the D-pad reads as
	# one cluster. 4 is the most they can close up: their inner edges land
	# exactly on UP/DOWN's column, and any tighter would overlap it —
	# TouchScreenButton falls back to its texture RECT for hit
	# testing, so overlapping buttons would both fire on a corner tap.
	{"action": "move_left", "tex": "res://shared/assets/ui/btn_left.png", "pos": Vector2(3, 284), "scale": SCALE},
	{"action": "move_right", "tex": "res://shared/assets/ui/btn_right.png", "pos": Vector2(83, 284), "scale": SCALE},
	# UP dropped from its old 240 to close the cluster up vertically. It now
	# hangs 8px past LEFT/RIGHT's 284 row, which is fine only because their
	# columns merely touch: overlap in ONE axis is not an overlapping rect.
	{"action": "interact", "tex": "res://shared/assets/ui/btn_up.png", "pos": Vector2(43, 252), "scale": SCALE},
	{"action": "duck", "tex": "res://shared/assets/ui/btn_down.png", "pos": Vector2(43, 316), "scale": SCALE},
	{"action": "punch", "tex": "res://shared/assets/ui/btn_punch.png", "pos": Vector2(549, 296), "scale": ACTION_SCALE},
	{"action": "kick", "tex": "res://shared/assets/ui/btn_kick.png", "pos": Vector2(597, 248), "scale": ACTION_SCALE},
	# Beer under kick, swing above punch — the four make a 2x2 grid.
	{"action": "throw", "tex": "res://shared/assets/ui/btn_beer.png", "pos": Vector2(597, 296), "scale": ACTION_SCALE},
	{"action": "swing", "tex": "res://shared/assets/ui/btn_swing.png", "pos": Vector2(549, 248), "scale": ACTION_SCALE},
]
const BUTTON_PX := 40.0  # source texture size, before SCALE

const DESIGN_W := 640.0
const DESIGN_H := 360.0

var _buttons: Array = []  # [{node, pos}]
var _throw_btn: TouchScreenButton
var _throw_pos := Vector2.ZERO
var _throw_badge: Label
var _swing_btn: TouchScreenButton
## {true: green-bordered texture, false: stock gray} for the two gated
## buttons, built once in _ready() so a refresh is just a swap.
var _throw_tex := {}
var _swing_tex := {}
## Halo sprites behind the two gated buttons, hidden while the move is not
## available. Punch and kick keep theirs lit for the whole run.
var _throw_glow: Sprite2D
var _swing_glow: Sprite2D
## Buttons that blink on their own action firing (PUNCH, KICK):
## [{action, node, lit, stock, glow, gen}]. See _register_flash().
var _flash: Array = []


func _ready() -> void:
	layer = 90
	for b in BUTTONS:
		var btn := TouchScreenButton.new()
		# The stock (gray-bordered) art. Everything green — the tinted border
		# and the halo alike — is derived from it, so keep it around.
		var base := _swing_texture() if b.action == "swing" else _load_tex(b.tex)
		btn.texture_normal = base
		btn.action = b.action
		btn.scale = Vector2(b.scale, b.scale)
		btn.passby_press = true
		add_child(btn)
		_buttons.append({"node": btn, "pos": b.pos, "scale": b.scale})
		match b.action:
			"punch", "kick":
				# No gate on these two, so they wear the ready border for the
				# whole run — and drop out of it for a beat on every tap,
				# which is the only acknowledgement they can give.
				var lit := _border_variants(base)
				btn.texture_normal = lit[true]
				_register_flash(btn, b.action, lit[true], lit[false],
						_add_glow(btn, base))
			"throw":
				_throw_btn = btn
				_throw_pos = b.pos
				_throw_tex = _border_variants(base)
				_throw_glow = _add_glow(btn, base)
			"swing":
				_swing_btn = btn
				_swing_tex = _border_variants(base)
				_swing_glow = _add_glow(btn, base)
	_build_throw_badge()
	_layout()
	GameState.bottles_changed.connect(_refresh_throw)
	_refresh_throw(GameState.beer_bottles)
	GameState.swing_ready_changed.connect(_refresh_swing)
	# The swing cooldown starts at zero, so the run opens with it available.
	_refresh_swing(true)
	# The OS/browser can report the real window size a frame (or a rotation)
	# after _ready, so re-anchor whenever the viewport changes.
	get_viewport().size_changed.connect(_layout)


## A small count badge pinned to the throw button's top-right corner.
func _build_throw_badge() -> void:
	_throw_badge = Label.new()
	_throw_badge.add_theme_font_size_override("font_size", 13)
	_throw_badge.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	_throw_badge.add_theme_color_override("font_outline_color", Color.BLACK)
	_throw_badge.add_theme_constant_override("outline_size", 5)
	add_child(_throw_badge)  # after the buttons, so it draws on top


## Dim + badge reflect how many bottles the player is carrying (throwable
## anywhere — street and venue alike).
func _refresh_throw(count: int) -> void:
	if _throw_btn == null:
		return
	var usable := count > 0
	_throw_btn.texture_normal = _throw_tex.get(usable, _throw_btn.texture_normal)
	_throw_btn.modulate.a = 1.0 if usable else 0.35
	if _throw_glow:
		_throw_glow.visible = usable
	_throw_badge.visible = usable
	_throw_badge.text = str(count)


## Dim the mic-swing button while its cooldown runs (the player script is
## the real gate — this is only the visual).
func _refresh_swing(ready: bool) -> void:
	if _swing_btn:
		_swing_btn.texture_normal = _swing_tex.get(ready, _swing_btn.texture_normal)
		_swing_btn.modulate.a = 1.0 if ready else 0.35
	if _swing_glow:
		_swing_glow.visible = ready


func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	for b in _buttons:
		b.node.position = _screen_pos(b.pos, b.scale, view)
	if _throw_badge:
		var tp := _screen_pos(_throw_pos, ACTION_SCALE, view)
		# Hug the button's top-right corner.
		_throw_badge.position = tp + Vector2(BUTTON_PX * ACTION_SCALE - 12.0, -8.0)


## Scale a DESIGN-space button offset from its corner, then hang it off the
## corresponding LIVE screen corner — on wider-than-design screens the right
## cluster must follow the real edge.
func _screen_pos(pos: Vector2, btn_scale: float, view: Vector2) -> Vector2:
	var x := pos.x * btn_scale if pos.x < DESIGN_W / 2.0 \
			else view.x - (DESIGN_W - pos.x) * btn_scale
	# Lifted clear of the Android nav bar: DUCK is the low one, and at 1x it
	# sat with its bottom edge 6px off the screen edge — right under the
	# gesture pill.
	var y := view.y - GameState.SAFE_BOTTOM - (DESIGN_H - pos.y) * btn_scale
	return Vector2(x, y)


## Load a button texture, falling back to the punch icon if a new asset (e.g.
## btn_beer.png) hasn't been imported by the Godot editor yet.
func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return load("res://shared/assets/ui/btn_punch.png")


## btn_swing.png's two structural colors: the rounded 50%-white border and the
## translucent dark fill. Everything else in the PNG is the baked mic glyph.
const _BTN_BORDER := Color(255 / 255.0, 255 / 255.0, 255 / 255.0, 128 / 255.0)
const _BTN_FILL := Color(25 / 255.0, 25 / 255.0, 38 / 255.0, 150 / 255.0)
## Weapon art must fit inside the chrome with a little breathing room.
const _BTN_ART_BOX := Vector2(26.0, 30.0)
## Ready-state border for the right-hand action cluster. The stock
## _BTN_BORDER gray now means "you can't do this right now": the mic is on
## cooldown, or you're out of bottles.
const _BORDER_READY := Color(64 / 255.0, 230 / 255.0, 98 / 255.0, 200 / 255.0)
## Halo geometry and breathing. _GLOW_PAD is in SOURCE pixels (the button art
## is 40px before ACTION_SCALE), and is deliberately smaller than the 8px gap
## between neighbours in the 2x2 grid so the four halos don't pile up on each
## other. Set _GLOW_PULSE_TIME to 0.0 for a steady, non-pulsing glow.
const _GLOW_PAD := 6
const _GLOW_BLUR := 4  # halo softness: bigger = blurrier, via a smaller mip
const _GLOW_ALPHA := 0.85
const _GLOW_DIM_ALPHA := 0.5
const _GLOW_PULSE_TIME := 0.8  # seconds per half-cycle


## The swing button wears the weapon actually carried this run: the stock art
## for the mic stand (its glyph IS the mic), otherwise the chrome is rebuilt
## from the same PNG — border and fill kept, glyph pixels painted over with
## the fill — and the equipped weapon's sprite is drawn upright in its place.
## Built once in _ready(): the weapon can only change in Settings, never
## mid-run, and every scene instantiates fresh touch controls. Any failure
## (missing art, compressed image surprise) falls back to the stock button.
func _swing_texture() -> Texture2D:
	var stock := _load_tex("res://shared/assets/ui/btn_swing.png")
	if Weapons.id_of(GameState.weapon) == "mic":
		return stock
	var wtex := Weapons.texture(GameState.weapon)
	if wtex == null:
		return stock
	var base := stock.get_image()
	var art := wtex.get_image()
	if base == null or art == null:
		return stock
	if base.is_compressed():
		base.decompress()
	if art.is_compressed():
		art.decompress()
	base.convert(Image.FORMAT_RGBA8)
	art.convert(Image.FORMAT_RGBA8)
	# Erase the glyph: keep transparent corners and border pixels, repaint the
	# rest with the flat fill.
	for y in base.get_height():
		for x in base.get_width():
			var p := base.get_pixel(x, y)
			if p.a8 != 0 and not p.is_equal_approx(_BTN_BORDER):
				base.set_pixel(x, y, _BTN_FILL)
	# Crop the weapon's shared 302x900 canvas to the art itself, then scale to
	# fit the chrome. Striking end stays up, like the mic glyph it replaces.
	var used := art.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return stock
	var glyph := art.get_region(used)
	var s := minf(_BTN_ART_BOX.x / glyph.get_width(), _BTN_ART_BOX.y / glyph.get_height())
	glyph.resize(maxi(1, roundi(glyph.get_width() * s)),
			maxi(1, roundi(glyph.get_height() * s)), Image.INTERPOLATE_LANCZOS)
	base.blend_rect(glyph, Rect2i(Vector2i.ZERO, glyph.get_size()),
			Vector2i(floori((base.get_width() - glyph.get_width()) / 2.0),
					floori((base.get_height() - glyph.get_height()) / 2.0)))
	return ImageTexture.create_from_image(base)


## {true: ready-colored, false: stock} for a gated button's texture.
func _border_variants(tex: Texture2D) -> Dictionary:
	return {true: _tint_border(tex, _BORDER_READY), false: tex}


## Repaint only the button's outer ring, leaving the glyph alone — which
## matters because on punch/kick/beer the glyph is drawn in the SAME 50%
## white as the border.
func _tint_border(src: Texture2D, color: Color) -> Texture2D:
	var img := _decoded(src)
	if img == null:
		return src
	for p in _ring_pixels(img):
		img.set_pixelv(p, color)
	return ImageTexture.create_from_image(img)


## A soft green halo sitting behind one button, sized to the art plus
## _GLOW_PAD on every side. Returns null if the art has no ring to trace.
func _glow_texture(src: Texture2D) -> Texture2D:
	var img := _decoded(src)
	if img == null:
		return null
	var ring := _ring_pixels(img)
	if ring.is_empty():
		return null
	var w := img.get_width() + _GLOW_PAD * 2
	var h := img.get_height() + _GLOW_PAD * 2
	var glow := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# Fill with the glow color at ZERO alpha rather than transparent black:
	# the blur below interpolates RGB as well as alpha, and a black backdrop
	# would bleed a dirty rim into the halo. This way only alpha varies.
	var lit := Color(_BORDER_READY.r, _BORDER_READY.g, _BORDER_READY.b, 1.0)
	glow.fill(Color(lit.r, lit.g, lit.b, 0.0))
	var pad := Vector2i(_GLOW_PAD, _GLOW_PAD)
	for p in ring:
		glow.set_pixelv(p + pad, lit)
	# Blur by round-tripping through a small mip. Image.resize is C++ and a
	# down/up bilinear pair is a cheap stand-in for a gaussian at this size.
	glow.resize(maxi(1, w / _GLOW_BLUR), maxi(1, h / _GLOW_BLUR), Image.INTERPOLATE_BILINEAR)
	glow.resize(w, h, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(glow)


## Hang the halo off the button itself, so it inherits the button's position
## and ACTION_SCALE for free and _layout() never has to know it exists.
## show_behind_parent keeps it under the art instead of washing the glyph out.
func _add_glow(btn: TouchScreenButton, base: Texture2D) -> Sprite2D:
	var tex := _glow_texture(base)
	if tex == null:
		return null
	var glow := Sprite2D.new()
	glow.texture = tex
	glow.centered = false
	glow.position = Vector2(-_GLOW_PAD, -_GLOW_PAD)
	glow.show_behind_parent = true
	glow.material = _glow_material()
	btn.add_child(glow)
	if _GLOW_PULSE_TIME > 0.0:
		var tw := glow.create_tween().set_loops()
		tw.tween_property(glow, "modulate:a", _GLOW_ALPHA, _GLOW_PULSE_TIME) \
				.from(_GLOW_DIM_ALPHA).set_trans(Tween.TRANS_SINE)
		tw.tween_property(glow, "modulate:a", _GLOW_DIM_ALPHA, _GLOW_PULSE_TIME) \
				.set_trans(Tween.TRANS_SINE)
	else:
		glow.modulate.a = _GLOW_ALPHA
	return glow


## How long PUNCH and KICK drop back to the gray, unlit chrome when used.
## Short enough to read as a button depressing rather than as a cooldown —
## SWING and BEER have real gates to show, these two have nothing, and the
## point is that the player sees SOMETHING change on the button.
const _TAP_FLASH_TIME := 0.12


## Register an always-available button to blink back to its stock chrome
## whenever its action fires.
##
## Driven off the INPUT ACTION, not TouchScreenButton's `pressed` signal.
## That signal only fires for a touch or a mouse press landing on the button
## itself, so on a keyboard it never fired at all and the flash was invisible
## on desktop. TouchScreenButton feeds its taps through Input.action_press(),
## so watching the action catches the on-screen button too — one path for
## thumb and keyboard both, and no double-trigger from wiring up both.
func _register_flash(btn: TouchScreenButton, action: String, lit: Texture2D,
		stock: Texture2D, glow: Sprite2D) -> void:
	_flash.append({
		"action": action, "node": btn, "lit": lit, "stock": stock,
		"glow": glow, "gen": 0,
	})


func _process(_delta: float) -> void:
	for f in _flash:
		if Input.is_action_just_pressed(f.action):
			_flash_button(f)


## Timer-driven rather than waiting on the action's release: a finger sliding
## off a passby_press button, or a scene torn down mid-press, can cost you the
## release, and a button stuck gray forever is worse than a flash that ends a
## hair early. The generation counter is for mashing — a press landing while
## the button is still dark takes ownership, so the earlier press's timer
## cannot re-light a button that is being pressed again.
func _flash_button(f: Dictionary) -> void:
	f.gen += 1
	var mine: int = f.gen
	var btn: TouchScreenButton = f.node
	btn.texture_normal = f.stock
	if is_instance_valid(f.glow):
		f.glow.visible = false
	# process_always, so a popup opening on the same frame as the punch does
	# not leave the button gray behind it.
	await get_tree().create_timer(_TAP_FLASH_TIME, true, false, true).timeout
	if f.gen != mine or not is_instance_valid(btn):
		return
	btn.texture_normal = f.lit
	if is_instance_valid(f.glow):
		f.glow.visible = true


## One shared additive material for every halo: the buttons sit over dark
## street/venue art, so adding light reads as a glow where alpha-blending
## just reads as a green smudge.
var _glow_mat: CanvasItemMaterial

func _glow_material() -> CanvasItemMaterial:
	if _glow_mat == null:
		_glow_mat = CanvasItemMaterial.new()
		_glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _glow_mat


## Decode a texture into a writable RGBA8 image.
func _decoded(src: Texture2D) -> Image:
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## The button's outer ring, as image coordinates. It is the only opaque run
## reachable from outside the image without crossing the dark fill, so a
## flood fill inward from the edges through transparent-and-border pixels
## finds it and stops before the glyph.
func _ring_pixels(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var seen := {}
	var ring: Array[Vector2i] = []
	var stack: Array[Vector2i] = []
	for x in w:
		stack.append(Vector2i(x, 0))
		stack.append(Vector2i(x, h - 1))
	for y in h:
		stack.append(Vector2i(0, y))
		stack.append(Vector2i(w - 1, y))
	const NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h or seen.has(p):
			continue
		var c := img.get_pixelv(p)
		var is_border := c.is_equal_approx(_BTN_BORDER)
		if c.a8 != 0 and not is_border:
			continue  # fill or glyph: the flood stops here
		seen[p] = true
		if is_border:
			ring.append(p)
		for d in NEIGHBORS:
			stack.append(p + d)
	return ring
