class_name MenuBase
extends Control
## Shared scaffolding for menu screens: dark backdrop, centered column,
## title/button helpers. Menus build their UI in code in _ready().


## The share glyph, drawn rather than imported — three nodes joined by two
## arms, the mark everyone already reads as "send this to someone". Sits on
## top of its Button and passes every click straight through to it.
class ShareIcon extends Control:
	const INK := Color(0.97, 0.92, 1.0)
	const DOT := 3.0
	const ARM := 1.6

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var left := c + Vector2(-7, 0)
		var top := c + Vector2(7, -6)
		var bottom := c + Vector2(7, 6)
		draw_line(left, top, INK, ARM, true)
		draw_line(left, bottom, INK, ARM, true)
		for p in [left, top, bottom]:
			draw_circle(p, DOT, INK)


## Square share target, sized for a thumb. Captionless: the glyph is the label.
const SHARE_SIZE := Vector2(44, 44)

var _toast_label: Label
var _toast_tween: Tween


## Passing "" (the default) uses the active game's menu background from the
## manifest, so every menu screen shares one per-game backdrop.
func build_backdrop(bg_path := "") -> VBoxContainer:
	if bg_path == "":
		bg_path = GameState.menu_bg_path()
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.07, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var art := TextureRect.new()
		art.texture = load(bg_path)
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(art)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.45)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Shift the whole centering rect up (not just shrink it) by the Android
	# nav-bar dead zone: shrinking would only lift the column by half the
	# inset, and does nothing at all once the column is taller than the
	# screen. Moving the rect lifts the bottom row by the full amount either
	# way, and any overflow lands at the TOP, where nothing is swallowed.
	center.offset_top = -GameState.SAFE_BOTTOM
	center.offset_bottom = -GameState.SAFE_BOTTOM
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	return box


func add_title(box: Container, text: String, size := 20, color := Color(1.0, 0.85, 0.4)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l


func add_text(box: Container, text: String, size := 8, color := Color(0.8, 0.8, 0.85)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l


func add_button(box: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 36)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(func(): GameState.play_sfx("click"))
	b.pressed.connect(cb)
	box.add_child(b)
	return b


## SHARE wears the same violet tube border as FIGHT! but stays hollow, so a
## primary button and this one read as a single control group without
## competing for the primary action. Character select and game over both use
## it, which is what keeps the two screens' share affordance identical.
func add_share_button(box: Container, cb: Callable) -> Button:
	var b := add_button(box, "", cb)
	b.custom_minimum_size = SHARE_SIZE
	set_tip(b, "Share this comedian")
	var fills := {
		"normal": Color(0.16, 0.10, 0.24),
		"hover": Color(0.30, 0.17, 0.45),
		"pressed": Color(0.12, 0.07, 0.18),
		"focus": Color(0.16, 0.10, 0.24),
	}
	for state in fills:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fills[state]
		sb.set_corner_radius_all(3)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.85, 0.6, 1.0)
		b.add_theme_stylebox_override(state, sb)
	var icon := ShareIcon.new()
	# anchors AND offsets — anchors alone leaves the old offsets behind.
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(icon)
	return b


## Buttons do not dim their children, so the glyph is faded by hand.
func set_share_enabled(b: Button, on: bool) -> void:
	b.disabled = not on
	for c in b.get_children():
		if c is ShareIcon:
			c.modulate.a = 1.0 if on else 0.3


## Reserved strip under the share button: always present, so confirming a copy
## never nudges the layout by appearing.
func add_share_toast(box: Container, width: float) -> Label:
	_toast_label = add_text(box, "", 8, Color(0.55, 1.0, 0.7))
	_toast_label.custom_minimum_size = Vector2(width, 12)
	_toast_label.modulate.a = 0.0
	return _toast_label


func flash_toast(msg: String, color: Color) -> void:
	if _toast_label == null:
		return
	_toast_label.text = msg
	_toast_label.add_theme_color_override("font_color", color)
	_toast_label.modulate.a = 1.0
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.2)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)


## The one place a comedian's share link is built and handed to the OS, so the
## toast wording is the same wherever sharing lives. `msg` is the screen's own
## pitch; false back means there was nothing shareable to send.
func share_character(cfg: Dictionary, msg: String) -> bool:
	var id := String(cfg.get("CharacterId", ""))
	if id == "":
		flash_toast("NO SHARE ID", Color(1.0, 0.6, 0.5))
		return false
	match GameState.share_link(GameState.share_url(id), msg):
		GameState.SHARE_NATIVE:
			pass  # the OS sheet is its own confirmation
		GameState.SHARE_COPIED:
			flash_toast("LINK COPIED!", Color(0.55, 1.0, 0.7))
		_:
			flash_toast("SHARE FAILED", Color(1.0, 0.6, 0.5))
	return true


## A row of square icon buttons that each open an external link — the social
## follow row on the main menu. Sized like every other thumb target in the app
## (SOCIAL_SIZE ~ the 44px SHARE button), wearing the plain gray skin so the
## coloured badges are the only thing shouting on the row.
##
## `links` is an array of {icon, url, tip} dictionaries; anything whose art
## hasn't been imported yet is skipped rather than drawn as an empty box.
const SOCIAL_SIZE := Vector2(46, 46)
const SOCIAL_INSET := 5


## A tooltip, but ONLY where a real pointer exists.
##
## On a touchscreen a Godot tooltip is a trap: it opens on the emulated hover
## and then never closes, because a finger that lifts produces no mouse-leave
## for it to close on — the virtual cursor just stays parked where you last
## tapped. That is the "Buy us a coffee" caption that sat on top of the main
## menu and would not go away.
##
## Static so hud.gd (not a MenuBase) can use it too. Desktop keeps its
## tooltips; touch builds simply never create one.
static func set_tip(c: Control, text: String) -> void:
	if DisplayServer.is_touchscreen_available():
		return
	c.tooltip_text = text


func add_link_row(box: Container, links: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for link in links:
		var path := String(link.get("icon", ""))
		if not ResourceLoader.exists(path):
			continue
		var url := String(link.get("url", ""))
		var b := Button.new()
		b.icon = load(path)
		# Badges are authored at 64px; let the Button scale them into the
		# smaller square instead of cropping to the top-left corner.
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		b.custom_minimum_size = SOCIAL_SIZE
		set_tip(b, String(link.get("tip", "")))
		style_gray_button(b)
		# The gray skin's default padding isn't symmetric; an even inset is
		# what keeps the badge centered inside its border.
		for state in ["normal", "hover", "pressed", "focus"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(state)
			sb.content_margin_left = SOCIAL_INSET
			sb.content_margin_right = SOCIAL_INSET
			sb.content_margin_top = SOCIAL_INSET
			sb.content_margin_bottom = SOCIAL_INSET
		b.pressed.connect(func():
			GameState.play_sfx("click")
			OS.shell_open(url))
		row.add_child(b)
	return row


func add_spacer(box: Container, h := 8) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	box.add_child(s)


## A small read-only caption pinned to the bottom of the menu root — the
## "PAGE x / y" counters live here. Nothing down here is tappable, so it can
## sit in the strip the buttons had to vacate; it still clears
## GameState.SAFE_BOTTOM so the nav bar doesn't cover the text itself.
const BOTTOM_LABEL_H := 16.0


func add_bottom_label(text := "") -> Label:
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	l.offset_top = -BOTTOM_LABEL_H - GameState.SAFE_BOTTOM
	l.offset_bottom = -GameState.SAFE_BOTTOM
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.68))
	add_child(l)
	return l


const EDGE_ARROW_MARGIN := 10.0

## A "<" / ">" pager pinned to the screen's left or right edge, vertically
## centred. Anchored to the menu root (not the content column), so the arrows
## stay put no matter how wide the names/rows between them get — muscle-memory
## tap targets. With aspect="expand" the anchors track the real screen edge.
## 1.5x the in-row arrows: edge targets are hit by feel, so they run big.
func add_edge_arrow(text: String, on_right: bool, cb: Callable, min_size := Vector2(45, 90)) -> Button:
	var b := make_arrow_button(text, guard_tap(cb), min_size)
	b.add_theme_font_size_override("font_size", 24)
	var ax := 1.0 if on_right else 0.0
	b.anchor_left = ax
	b.anchor_right = ax
	b.anchor_top = 0.5
	b.anchor_bottom = 0.5
	b.offset_top = -min_size.y / 2.0
	b.offset_bottom = min_size.y / 2.0
	if on_right:
		b.offset_right = -EDGE_ARROW_MARGIN
		b.offset_left = -EDGE_ARROW_MARGIN - min_size.x
		b.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	else:
		b.offset_left = EDGE_ARROW_MARGIN
		b.offset_right = EDGE_ARROW_MARGIN + min_size.x
		b.grow_horizontal = Control.GROW_DIRECTION_END
	add_child(b)
	return b


## Corner BACK button: red fill, white arrow, pinned to the TOP-LEFT of the
## menu root rather than sitting in the content column. Two reasons it lives
## up there — the bottom edge is Android nav-bar territory (see
## GameState.SAFE_BOTTOM), and taking it out of the column gives every screen
## back a full button row of vertical space.
##
## Styled like FIGHT! in character select (same radius/border language) so the
## menus read as one set; red because it is the one "leave" action on screen.
const BACK_SIZE := Vector2(48, 48)


## The app's plain GRAY button skin: same rounded corners (3) and 2px tube
## border as FIGHT!, SHARE and BACK, just without a colour shouting for
## attention. Static so non-menu screens can wear it too — the in-game PAUSE
## button in hud.gd does, which is what keeps it from looking like a stray
## default-theme control sitting on the HUD.
const BUTTON_RADIUS := 3
const BUTTON_BORDER := 2
const GRAY_BORDER := Color(0.72, 0.72, 0.80)
const PURPLE_BORDER := Color(0.85, 0.6, 1.0)
const PURPLE_TEXT := Color(0.97, 0.92, 1.0)


## The filled neon-purple skin: bright violet tube border, glowing lavender
## text. FIGHT! in character select wears it as that screen's one primary
## action; anything else wearing it is saying "this is the button on the
## screen". Static so non-menu screens can use it too. Disabled deliberately
## keeps the default gray stylebox.
static func style_purple_button(b: Button) -> void:
	var fills := {
		"normal": Color(0.45, 0.15, 0.75),
		"hover": Color(0.58, 0.28, 0.9),
		"pressed": Color(0.33, 0.1, 0.58),
		"focus": Color(0.45, 0.15, 0.75),
	}
	for state in fills:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fills[state]
		sb.set_corner_radius_all(BUTTON_RADIUS)
		sb.set_border_width_all(BUTTON_BORDER)
		sb.border_color = PURPLE_BORDER
		b.add_theme_stylebox_override(state, sb)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, PURPLE_TEXT)


static func style_gray_button(b: Button) -> void:
	var fills := {
		"normal": Color(0.16, 0.16, 0.19),
		"hover": Color(0.26, 0.26, 0.30),
		"pressed": Color(0.11, 0.11, 0.13),
		"focus": Color(0.16, 0.16, 0.19),
	}
	for state in fills:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fills[state]
		sb.set_corner_radius_all(BUTTON_RADIUS)
		sb.set_border_width_all(BUTTON_BORDER)
		sb.border_color = GRAY_BORDER
		b.add_theme_stylebox_override(state, sb)


## The BACK button's look and behaviour without the corner: builds the square
## red button, wires the click SFX and the callback, and leaves placement to
## the caller. Static, so things that are not menu screens can wear the same
## control — the in-game hint popup hangs one off its own top-right as a close
## button, and players meet exactly one "get me out of here" button in the
## whole app instead of two that look different.
static func make_back_button(cb: Callable) -> Button:
	var b := Button.new()
	b.icon = back_arrow_texture()
	set_tip(b, "Back")
	b.custom_minimum_size = BACK_SIZE
	# With no text, a Button still parks its icon at the left edge — center it
	# both ways so the arrow sits in the middle of the square.
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	var fills := {
		"normal": Color(0.66, 0.12, 0.15),
		"hover": Color(0.82, 0.2, 0.22),
		"pressed": Color(0.48, 0.08, 0.11),
		"focus": Color(0.66, 0.12, 0.15),
	}
	for state in fills:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fills[state]
		sb.set_corner_radius_all(3)
		sb.set_border_width_all(2)
		sb.border_color = Color(1.0, 0.6, 0.55)
		# Zero content margins: the theme's default button padding is not
		# symmetric, which would nudge a centered icon off-center.
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		b.add_theme_stylebox_override(state, sb)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color",
			"icon_focus_color"]:
		b.add_theme_color_override(state, Color.WHITE)
	b.pressed.connect(func():
		GameState.play_sfx("click")
		cb.call())
	return b


func add_back_button(cb: Callable) -> Button:
	var b := make_back_button(guard_tap(cb))
	# Top-left corner, growing right/down so a wider screen never moves it.
	b.anchor_left = 0.0
	b.anchor_right = 0.0
	b.anchor_top = 0.0
	b.anchor_bottom = 0.0
	b.offset_left = EDGE_ARROW_MARGIN
	b.offset_right = EDGE_ARROW_MARGIN + BACK_SIZE.x
	b.offset_top = EDGE_ARROW_MARGIN
	b.offset_bottom = EDGE_ARROW_MARGIN + BACK_SIZE.y
	b.grow_horizontal = Control.GROW_DIRECTION_END
	b.grow_vertical = Control.GROW_DIRECTION_END
	add_child(b)
	return b


## The white pixel arrow on that button, drawn in code so there is no new art
## asset to import (and no filtering to fight): a solid triangle head with a
## shaft, built at ARROW_PIXEL-sized blocks to sit on the same chunky grid as
## the rest of the UI. Cached — every menu shows one.
const ARROW_W := 12
const ARROW_H := 11
const ARROW_PIXEL := 2

static var _arrow_tex: ImageTexture


static func back_arrow_texture() -> ImageTexture:
	if _arrow_tex != null:
		return _arrow_tex
	var img := Image.create(ARROW_W * ARROW_PIXEL, ARROW_H * ARROW_PIXEL, false,
			Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mid := ARROW_H / 2  # integer: 5 for an 11-tall arrow
	for y in ARROW_H:
		var d := absi(y - mid)
		for x in ARROW_W:
			# Head: triangle narrowing to the tip at x=0. Shaft: 3 rows out
			# to the right edge.
			if (x <= mid and x >= d) or (x >= mid and d <= 1):
				for py in ARROW_PIXEL:
					for px in ARROW_PIXEL:
						img.set_pixel(x * ARROW_PIXEL + px, y * ARROW_PIXEL + py,
								Color.WHITE)
	_arrow_tex = ImageTexture.create_from_image(img)
	return _arrow_tex


## A tall, narrow "<" / ">" pager button. Shared by character select and the
## scoreboard so both pagers click and look the same; the caller decides what
## turning a page means.
func make_arrow_button(text: String, cb: Callable, min_size := Vector2(30, 60)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(func():
		GameState.play_sfx("click")
		cb.call())
	return b


# ---------------------------------------------------------------- swipe paging
## Horizontal swipe as a SECOND way to turn a page, alongside the edge arrows
## above. Players kept trying it on the boards and nothing happened, so the
## gesture now runs into the same _turn_page() the arrows already call — the
## arrows are unchanged and still the discoverable path.
##
## It lives here rather than in the paging screens because the whole contract is
## one method: any MenuBase subclass that defines `_turn_page(dir: int)` gets
## swipe for free, and every screen that doesn't is untouched. Today that is
## scenes/scoreboard.gd and scenes/character_select.gd; a future paged screen
## needs no wiring.
##
## TABS ARE DELIBERATELY NOT SWIPEABLE — you tap to change tab, you swipe to
## turn a page. That is why the recogniser calls _turn_page and nothing else.

## Thresholds are in the 640x360 design space: stretch mode "canvas_items"
## hands input over already scaled, so these numbers mean the same thing on
## every screen size. Two knobs only, both meant to be tuned on a real phone.
##
## ~1/16 of the screen width — far enough not to be a fat-fingered tap, short
## enough to flick without thinking about it.
const SWIPE_MIN_X := 40.0
## How much vertical wander to forgive. Generous on purpose: a thumb arcs, and
## none of the paging screens scroll vertically, so there is no other gesture
## for a sloppy diagonal to be confused with.
const SWIPE_MAX_Y := 60.0

var _swipe_from := Vector2.ZERO
var _swipe_tracking := false
## Which touch owns the gesture. NEVER assume 0: Godot's web export passes the
## browser's raw Touch.identifier through as the index (see godot.js,
## _godot_js_input_touch_cb), and that is browser-defined — Chrome/Android
## counts up from 0, iOS Safari hands out arbitrary large integers. Testing
## `index == 0` therefore worked on Android and matched NOTHING on iPhone.
var _swipe_index := -1
## True from the moment a swipe is recognised until the NEXT touch starts, so
## the release that ENDS the swipe cannot also press the button the finger
## happened to be resting on. See guard_tap().
var _swipe_took_over := false


## No time limit on the gesture, deliberately. A slow horizontal drag means
## nothing else on these screens, and the failure we are fixing is a swipe that
## does nothing — so this errs toward recognising too much rather than too
## little. Add a duration cap here if resting thumbs start turning pages.
func _input(event: InputEvent) -> void:
	if not has_method("_turn_page"):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			# The first finger down owns the gesture; a second one arriving
			# mid-swipe is ignored rather than allowed to start a rival one.
			if not _swipe_tracking:
				_swipe_index = event.index
				_swipe_from = event.position
				_swipe_tracking = true
				_swipe_took_over = false
		elif event.index == _swipe_index:
			_swipe_tracking = false
		return
	if not (event is InputEventScreenDrag and event.index == _swipe_index):
		return
	if not _swipe_tracking or _swipe_took_over:
		return
	var delta: Vector2 = event.position - _swipe_from
	if absf(delta.y) > SWIPE_MAX_Y:
		# Wandered off the horizontal. Abandon this touch outright rather than
		# waiting to see whether it happens to drift back.
		_swipe_tracking = false
		return
	if absf(delta.x) < SWIPE_MIN_X:
		return
	# Fire the moment the threshold is crossed rather than on release: the page
	# turns under the finger, which is what separates a swipe from a slow tap.
	# _swipe_took_over then locks the rest of this touch, so one drag can only
	# ever move one page no matter how far it keeps going.
	_swipe_took_over = true
	# The same click the pager arrows make, so a swipe confirms itself the way
	# every other control on the screen does. It belongs HERE and not inside
	# _turn_page(): the arrows already play it themselves (see
	# make_arrow_button), and moving it down there would double it on every tap.
	GameState.play_sfx("click")
	# Dragging LEFT pulls the next page in from the right, like every other
	# paged list on a phone.
	call("_turn_page", -1 if delta.x > 0.0 else 1)


## Wraps a button callback so a swipe that STARTED on that button does not also
## press it. Needed because a 40px swipe can begin and end inside one control —
## a beef row is 220px wide, a character card 64px — and Godot fires `pressed`
## on release-inside-rect knowing nothing about the gesture.
##
## Guards at the CALLBACK rather than consuming the release event on purpose:
## swallowing the touch-up would leave the Button stuck in its held state,
## since BaseButton clears that on the release it would then never receive.
func guard_tap(cb: Callable) -> Callable:
	return func():
		if _swipe_took_over:
			return
		cb.call()
