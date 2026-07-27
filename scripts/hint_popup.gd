class_name HintPopup
extends CanvasLayer
## A teaching popup that freezes the game behind it: dimmed street, one panel,
## one button. Built for the first-run "this is a door" lesson (street.gd), but
## it takes any title/body, so the next thing worth explaining reuses it.
##
## process_mode = ALWAYS is what makes this work — GameState.set_paused()
## stops the whole tree, and this node is deliberately the exception, so it can
## still take the tap that closes it. Everything inside inherits that, which is
## why the button is clickable while nothing else in the game is.
##
## Closing NEVER acts on the game: the player is told about the door and left
## standing in front of it, free to walk away. That is the owner's call — the
## popup teaches, it does not decide.

signal closed

const PANEL_W := 320.0
const PANEL_PAD := 18.0
const NEON := Color(0.85, 0.6, 1.0)
const FILL := Color(0.10, 0.07, 0.18, 0.96)
## 50% black between the game and the panel. It is a real input blocker, not
## just a tint: it covers the whole screen and swallows every tap, so the only
## thing on screen that responds is the BACK button.
const DIM := Color(0, 0, 0, 0.5)

var title_text := "HEADS UP"
var body_text := ""

var _panel: Panel
var _button: Button


func _ready() -> void:
	# Above the HUD (80) AND the on-screen touch controls (90) — a tie with
	# TouchControls leaves the draw order down to canvas insertion order, which
	# is not something to leave to chance.
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The dim sheet also eats stray taps: without a Control swallowing them,
	# a miss lands on the touch controls behind the popup.
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var style := StyleBoxFlat.new()
	style.bg_color = FILL
	style.border_color = NEON
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.content_margin_left = PANEL_PAD
	style.content_margin_right = PANEL_PAD
	style.content_margin_top = PANEL_PAD
	style.content_margin_bottom = PANEL_PAD
	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", style)
	# Centered on the LIVE viewport, never design-width 320 (wide-phone rule),
	# and lifted by the Android nav-bar dead zone like every other UI.
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(col)
	_add_label(col, title_text, 12, Color(1.0, 0.85, 0.4))
	_add_label(col, body_text, 9, Color(0.92, 0.92, 0.97))

	# The app's own corner BACK button, hung off the panel's top-right like a
	# dialog's close box — big, red, and the one control the player has already
	# pressed on every menu screen. It is the ONLY way out: nothing else
	# dismisses this, so the game cannot be resumed by a stray keypress while
	# the player is still reading.
	_button = MenuBase.make_back_button(close)
	_button.anchor_left = 1.0
	_button.anchor_right = 1.0
	_button.anchor_top = 0.0
	_button.anchor_bottom = 0.0
	# Sits ON the corner, overlapping outward by roughly half itself, so it
	# reads as attached to the panel rather than floating beside it.
	_button.offset_left = -MenuBase.BACK_SIZE.x * 0.55
	_button.offset_right = MenuBase.BACK_SIZE.x * 0.45
	_button.offset_top = -MenuBase.BACK_SIZE.y * 0.45
	_button.offset_bottom = MenuBase.BACK_SIZE.y * 0.55
	_panel.add_child(_button)

	# Size the panel to its content, then let the layout settle before the
	# pop-in tween reads it (a Container's size is not final on the same frame).
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	await get_tree().process_frame
	_panel.size = Vector2(PANEL_W, col.get_combined_minimum_size().y + PANEL_PAD * 2.0)
	_panel.offset_left = -PANEL_W / 2.0
	_panel.offset_right = PANEL_W / 2.0
	_panel.offset_top = -_panel.size.y / 2.0 - GameState.SAFE_BOTTOM
	_panel.offset_bottom = _panel.size.y / 2.0 - GameState.SAFE_BOTTOM
	_pop_in()
	# Focus is grabbed only once the grace is up, and never before: a FOCUSED
	# Button fires on ui_accept, so an accept press already in flight when the
	# game froze would close the popup on the frame it appeared. The timer's
	# process_always flag is what keeps it ticking while the game is paused.
	await get_tree().create_timer(INPUT_GRACE, true, false, true).timeout
	if is_instance_valid(_button):
		_button.grab_focus()  # so ENTER/SPACE and a gamepad's A close it too


## Nothing but the BACK button closes this — no key, no tap on the dim sheet.
## A player mashing punch at a heckler on the way to the door, or still
## holding a movement key when the game froze, would otherwise blow the popup
## away in the frame it appeared and never see it. The button takes focus
## after a short grace for the same reason: a focused Button consumes
## ui_accept itself, so an accept press already in flight would close it.
const INPUT_GRACE := 0.35


func close() -> void:
	# Unpausing before the free: the tween below is this node's own, and a
	# freed node's tween never lands, so the order matters more than it looks.
	GameState.set_paused(false)
	GameState.play_sfx("click")
	closed.emit()
	queue_free()


## Slams in like the menus' title: born big, snapping down to size.
func _pop_in() -> void:
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2(1.35, 1.35)
	_panel.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.15)


func _add_label(box: Container, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_W - PANEL_PAD * 2.0, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", 6)
	box.add_child(l)
	return l
