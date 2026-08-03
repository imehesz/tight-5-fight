class_name TouchControls
extends CanvasLayer
## Virtual on-screen controls for mobile landscape: D-pad on the left
## (up = enter doors, down = duck), punch/kick/throw/swing buttons on the
## right. Buttons emit the same input actions as the keyboard bindings.

const SCALE := 1.5
## The attack cluster runs 1.3x the D-pad — thumbs hunt for it mid-brawl.
const ACTION_SCALE := SCALE * 1.3
## Positions are the original 1x layout for 40px buttons on the 640x360
## viewport; _ready() scales each corner cluster outward from its screen
## corner so margins grow proportionally and nothing hangs off-screen.
const BUTTONS := [
	{"action": "move_left", "tex": "res://shared/assets/ui/btn_left.png", "pos": Vector2(12, 284), "scale": SCALE},
	{"action": "move_right", "tex": "res://shared/assets/ui/btn_right.png", "pos": Vector2(100, 284), "scale": SCALE},
	{"action": "interact", "tex": "res://shared/assets/ui/btn_up.png", "pos": Vector2(56, 240), "scale": SCALE},
	{"action": "duck", "tex": "res://shared/assets/ui/btn_down.png", "pos": Vector2(56, 316), "scale": SCALE},
	{"action": "punch", "tex": "res://shared/assets/ui/btn_punch.png", "pos": Vector2(536, 296), "scale": ACTION_SCALE},
	{"action": "kick", "tex": "res://shared/assets/ui/btn_kick.png", "pos": Vector2(584, 248), "scale": ACTION_SCALE},
	# Beer under kick, swing above punch — the four make a 2x2 grid.
	{"action": "throw", "tex": "res://shared/assets/ui/btn_beer.png", "pos": Vector2(584, 296), "scale": ACTION_SCALE},
	{"action": "swing", "tex": "res://shared/assets/ui/btn_swing.png", "pos": Vector2(536, 248), "scale": ACTION_SCALE},
]
const BUTTON_PX := 40.0  # source texture size, before SCALE

const DESIGN_W := 640.0
const DESIGN_H := 360.0

var _buttons: Array = []  # [{node, pos}]
var _throw_btn: TouchScreenButton
var _throw_pos := Vector2.ZERO
var _throw_badge: Label
var _swing_btn: TouchScreenButton


func _ready() -> void:
	layer = 90
	for b in BUTTONS:
		var btn := TouchScreenButton.new()
		btn.texture_normal = _swing_texture() if b.action == "swing" else _load_tex(b.tex)
		btn.action = b.action
		btn.scale = Vector2(b.scale, b.scale)
		btn.passby_press = true
		add_child(btn)
		_buttons.append({"node": btn, "pos": b.pos, "scale": b.scale})
		if b.action == "throw":
			_throw_btn = btn
			_throw_pos = b.pos
		elif b.action == "swing":
			_swing_btn = btn
	_build_throw_badge()
	_layout()
	GameState.bottles_changed.connect(_refresh_throw)
	_refresh_throw(GameState.beer_bottles)
	GameState.swing_ready_changed.connect(_refresh_swing)
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
	_throw_btn.modulate.a = 1.0 if usable else 0.35
	_throw_badge.visible = usable
	_throw_badge.text = str(count)


## Dim the mic-swing button while its cooldown runs (the player script is
## the real gate — this is only the visual).
func _refresh_swing(ready: bool) -> void:
	if _swing_btn:
		_swing_btn.modulate.a = 1.0 if ready else 0.35


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
