class_name JokeCrafterPanel
extends Control
## The JOKE CRAFTER, drawn as a page in the comedian's notepad. Sits inline in
## the LEADERBOARD's JOKE BOOK tab, beside the attendance grid.
##
## The notepad is LANDSCAPE here, not the portrait mockup. The well is a fixed
## 552x194, so a portrait page capped at 194 tall would be 129px wide — 46px
## for a word like PUNCHLINES, a font size of 4. Turned on its side the same
## notepad gets 324x194, and the page inside it 221x164, which is room to
## spare: it is what pays for ADD being a 42px target instead of 28.
##
## Only the SHELL is art — rings, strap, gold corners, ruled paper. Every row,
## number, highlighter swipe and button is a real control drawn on top, so the
## numbers are live and nothing has to line up with a picture of itself.

## Panel size, and the page inside it. The shell art's ruled page occupies
## x 14.1%..82.4% and y 6.7%..91.3% of the texture — measured off the file, not
## guessed — so nothing sits on the rings or under the elastic strap.
const PANEL := Vector2(324, 194)
const PAGE_L := 0.141
const PAGE_R := 0.824
const PAGE_T := 0.067
const PAGE_B := 0.913

const SHELL_ART := "res://shared/assets/ui/notepad_shell_wide.png"
const ICON_PATH := "res://shared/assets/components/%s_ink.png"
const ICON_FILES := {"setups": "setup", "punchlines": "punchline", "tags": "tag"}

## Row geometry. The page is 221px wide and the row needs
## | icon 16 | label 84 | count 32 | ADD 42 | plus 2px gaps = 180, so there is
## real slack here — which is spent on ADD being 42 wide rather than the 28 it
## would need to be on a portrait page. Press Start 2P advances one em per
## glyph, so "PUNCHLINES" is exactly 10 * font_size: 80px at font 8, and a four
## digit count is 32. Those two numbers set everything else.
const ROW_H := 22
const ICON_W := 16
const LABEL_W := 84
const COUNT_W := 32
const ADD_W := 42
const ROW_GAP := 2
const LABEL_FONT := 8

## Highlighter swipes, one per kind, matching the marker colours in the design.
## Drawn as a rect BEHIND the word rather than baked into the art, so the swipe
## and the text can never drift apart.
const HILITE := {
	"setups": Color(0.35, 0.90, 0.95),
	"punchlines": Color(1.00, 0.35, 0.75),
	"tags": Color(0.70, 0.95, 0.30),
}
const LABELS := {"setups": "SETUPS", "punchlines": "PUNCHLINES", "tags": "TAGS"}
## The slot captions inside THE JOKE box are the short forms from the design.
const SLOT_LABELS := {"setups": "SETUP", "punchlines": "PUNCH", "tags": "TAG"}

## Everything on the page is pen on paper, so one ink colour for all of it.
const INK := Color(0.16, 0.15, 0.30)
const PAPER_CARD := Color(1.0, 0.98, 0.92, 0.85)
const AMBER := Color(0.90, 0.62, 0.25)
const AMBER_OFF := Color(0.62, 0.60, 0.58)

## The balance is the number the whole page is about, so it is the biggest
## thing on it. At font 12 a six digit total is 72px, well inside the ~85px
## the points column gets beside the GENERATE button.
const POINTS_FONT := 12
const POINTS_PAD := 3

const COUNT_DIGITS := 4
const SLOT_DIGITS := 2

var _slots := {"setups": 0, "punchlines": 0, "tags": 0}
var _count_labels := {}
var _slot_labels := {}
var _add_buttons := {}
var _generate: Button
var _points: Label
var _status: Label


func _ready() -> void:
	custom_minimum_size = PANEL
	Leaderboard.crafter_loaded.connect(_on_loaded)
	Leaderboard.crafter_failed.connect(_on_failed)

	if ResourceLoader.exists(SHELL_ART):
		var art := TextureRect.new()
		art.texture = load(SHELL_ART)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = PANEL.x * PAGE_L
	col.offset_right = -PANEL.x * (1.0 - PAGE_R)
	col.offset_top = PANEL.y * PAGE_T
	col.offset_bottom = -PANEL.y * (1.0 - PAGE_B)
	col.add_theme_constant_override("separation", 3)
	add_child(col)

	for kind in GameState.COMPONENT_KINDS:
		col.add_child(_row(kind))
	col.add_child(_joke_box())

	# GENERATE and the balance share one line. Stacked they would need 24px
	# more than the 164px page has; side by side they fit with slack.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	col.add_child(foot)
	foot.add_child(_generate_button())
	foot.add_child(_points_line())

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 6)
	_status.add_theme_color_override("font_color", INK)
	col.add_child(_status)

	_paint()
	# A run may have banked components since this tab was last opened.
	Leaderboard.fetch_crafter()


## One inventory row, on its own pale card like the design: icon, highlighted
## word, count, ADD.
func _row(kind: String) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, ROW_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER_CARD
	sb.set_corner_radius_all(2)
	sb.set_border_width_all(1)
	sb.border_color = Color(INK.r, INK.g, INK.b, 0.25)
	sb.content_margin_left = 1
	sb.content_margin_right = 1
	card.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_GAP)
	card.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON_W, ICON_W)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var p: String = ICON_PATH % String(ICON_FILES.get(kind, "setup"))
	if ResourceLoader.exists(p):
		icon.texture = load(p)
	row.add_child(icon)

	# The word sits ON its highlighter swipe: a coloured rect the label is
	# parented to, so the two move together whatever the layout does.
	var swipe := Control.new()
	swipe.custom_minimum_size = Vector2(LABEL_W, ROW_H)
	swipe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mark := ColorRect.new()
	mark.color = HILITE.get(kind, Color.WHITE)
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.offset_top = ROW_H / 2.0 - LABEL_FONT
	mark.offset_bottom = -(ROW_H / 2.0 - LABEL_FONT) + 2.0
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swipe.add_child(mark)
	var word := Label.new()
	word.text = String(LABELS.get(kind, kind.to_upper()))
	word.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	word.add_theme_font_size_override("font_size", LABEL_FONT)
	word.add_theme_color_override("font_color", INK)
	swipe.add_child(word)
	row.add_child(swipe)

	var count := Label.new()
	count.custom_minimum_size = Vector2(COUNT_W, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 7)
	count.add_theme_color_override("font_color", INK)
	row.add_child(count)
	_count_labels[kind] = count

	var add := Button.new()
	add.text = "ADD"
	add.custom_minimum_size = Vector2(ADD_W, 26)
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.add_theme_font_size_override("font_size", 6)
	_style_add(add, HILITE.get(kind, Color.WHITE))
	add.pressed.connect(func(): _on_add(kind))
	row.add_child(add)
	_add_buttons[kind] = add
	return card


## ADD wears its own kind's highlighter colour, so the button and the swipe
## next to it are visibly the same thing.
func _style_add(b: Button, tint: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		var dim: bool = state == "disabled"
		sb.bg_color = tint.darkened(0.15) if not dim else Color(0.78, 0.76, 0.74)
		sb.set_corner_radius_all(2)
		sb.set_border_width_all(1)
		sb.border_color = INK if not dim else Color(INK.r, INK.g, INK.b, 0.4)
		b.add_theme_stylebox_override(state, sb)
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(state, INK)


## THE JOKE — the three loaded slots inside one hand-drawn box. Boxed together
## because they are one thing: a joke needs one of each, and GENERATE only
## lights when all three match.
func _joke_box() -> Control:
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.0)
	sb.set_border_width_all(2)
	sb.border_color = INK
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(3)
	frame.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	frame.add_child(box)

	var head := Label.new()
	head.text = "THE JOKE"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 7)
	head.add_theme_color_override("font_color", INK)
	box.add_child(head)

	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 10)
	box.add_child(slots)
	for kind in GameState.COMPONENT_KINDS:
		slots.add_child(_slot(kind))
	return frame


func _slot(kind: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var cap := Label.new()
	cap.text = String(SLOT_LABELS.get(kind, "?"))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 5)
	cap.add_theme_color_override("font_color", INK)
	col.add_child(cap)

	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(42, 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(2)
	sb.border_color = INK
	frame_corner(sb)
	cell.add_theme_stylebox_override("panel", sb)
	var n := Label.new()
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.add_theme_font_size_override("font_size", 8)
	n.add_theme_color_override("font_color", INK)
	cell.add_child(n)
	col.add_child(cell)
	_slot_labels[kind] = n
	return col


func frame_corner(sb: StyleBoxFlat) -> void:
	sb.set_corner_radius_all(1)


func _generate_button() -> Button:
	_generate = Button.new()
	_generate.text = "GENERATE JOKE"
	_generate.custom_minimum_size = Vector2(130, 24)
	_generate.add_theme_font_size_override("font_size", 7)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = AMBER if state != "disabled" else AMBER_OFF
		if state == "hover":
			sb.bg_color = AMBER.lightened(0.12)
		if state == "pressed":
			sb.bg_color = AMBER.darkened(0.15)
		sb.set_corner_radius_all(2)
		# The heavy marker outline from the design — the one thing on the page
		# that is drawn twice as thick as anything else.
		sb.set_border_width_all(3)
		sb.border_color = INK
		_generate.add_theme_stylebox_override(state, sb)
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		_generate.add_theme_color_override(state, INK)
	_generate.pressed.connect(_on_generate)
	return _generate


func _points_line() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A little air above the caption so the block sits off the GENERATE
	# button's top edge instead of aligning flush with it.
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, POINTS_PAD)
	box.add_child(pad)
	var cap := Label.new()
	cap.text = "JOKE POINTS:"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 6)
	cap.add_theme_color_override("font_color", INK)
	box.add_child(cap)
	_points = Label.new()
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points.add_theme_font_size_override("font_size", POINTS_FONT)
	_points.add_theme_color_override("font_color", INK)
	box.add_child(_points)
	return box


# ---------------------------------------------------------------- logic
## Free to load: what the server says is owned, minus what is already in a slot.
func _available(kind: String) -> int:
	return maxi(Leaderboard.components(kind) - int(_slots.get(kind, 0)), 0)


## ADD refuses a move that would strand the panel. Nothing can be taken back
## out of a slot, so loading a seventh punchline when only four tags exist in
## the world would lock the page for good. Since slot + available always equals
## the owned total, the cap is just the smaller of the other two totals.
func _can_add(kind: String) -> bool:
	if _available(kind) <= 0:
		return false
	var cap := 0x7FFFFFFF
	for other in GameState.COMPONENT_KINDS:
		if other != kind:
			cap = mini(cap, Leaderboard.components(other))
	return int(_slots.get(kind, 0)) < cap


func _batch() -> int:
	var n := int(_slots.get("setups", 0))
	if n <= 0:
		return 0
	for k in GameState.COMPONENT_KINDS:
		if int(_slots.get(k, 0)) != n:
			return 0
	return n


func _pad(v: int, digits: int) -> String:
	var cap := int(pow(10, digits)) - 1
	return String.num_int64(clampi(v, 0, cap)).pad_zeros(digits)


func _paint() -> void:
	if not is_instance_valid(_generate):
		return
	for kind in GameState.COMPONENT_KINDS:
		_count_labels[kind].text = _pad(_available(kind), COUNT_DIGITS)
		_slot_labels[kind].text = _pad(int(_slots.get(kind, 0)), SLOT_DIGITS)
		_add_buttons[kind].disabled = not _can_add(kind)
	var n := _batch()
	_generate.disabled = n <= 0
	_generate.text = "GENERATE JOKE" if n <= 0 else "GENERATE %d JOKE%s" % [n, "" if n == 1 else "S"]
	_points.text = str(Leaderboard.joke_points())


func _on_add(kind: String) -> void:
	if not _can_add(kind):
		return
	GameState.play_sfx("click")
	_slots[kind] = int(_slots.get(kind, 0)) + 1
	_paint()


func _on_generate() -> void:
	var n := _batch()
	if n <= 0:
		return
	GameState.play_sfx("click")
	_status.text = "WRITING ..."
	_generate.disabled = true
	# Cleared optimistically: the reply carries the post-craft inventory, so
	# leaving them loaded would double-count against it for a frame.
	_slots = {"setups": 0, "punchlines": 0, "tags": 0}
	Leaderboard.craft_jokes(n)


func _on_loaded(_d: Dictionary) -> void:
	if is_instance_valid(_status):
		_status.text = ""
	_paint()


func _on_failed(reason: String) -> void:
	if not is_instance_valid(_status):
		return
	_status.text = reason.to_upper()
	_paint()
