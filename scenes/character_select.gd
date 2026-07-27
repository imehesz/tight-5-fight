extends MenuBase
## Character Select: grid of comedian heads parsed from characters.json
## (paged 9 at a time with LEFT/RIGHT arrows) on the left, a dancing
## preview of the highlighted comedian on the right. Tapping a head only
## selects it; the FIGHT! button starts the run.
##
## Slot 1 of the grid is a "?" card: pick it and FIGHT! rolls a random
## comedian, revealed only once the run starts. Short last pages are
## padded with blank frames so the 3x3 grid never changes shape.

const GRID_COLUMNS := 3
const PAGE_SIZE := 9
## _selected value meaning "the ? card" — resolved to a real roster index
## the moment FIGHT! is pressed.
const RANDOM := -1
const PREVIEW_SIZE := Vector2(150, 170)
## FIGHT! and SHARE share one row. 44 rather than the old 40 so the square
## SHARE target stays comfortably thumb-sized on a phone.
const ACTION_H := 44
const SHARE_W := 44
const ACTION_GAP := 6
## 1.5x the in-game fighter size.
const PREVIEW_SCALE := Fighter.BODY_SCALE * 1.5
## Pop-in zoom on selection: born this fraction of full size, grown back
## over ZOOM_TIME seconds.
const ZOOM_START := 0.1
const ZOOM_TIME := 0.3

var _page := 0
var _selected := -1
var _grid: GridContainer
var _pager: Label
var _dancer: Dancer
var _preview_question: Label
var _preview_name: Label
var _fight_btn: Button
var _share_btn: Button
var _share_icon: Control
var _share_toast: Label
var _toast_tween: Tween
var _orbit: SelectionOrbit
var _zoom: Tween


## A shiny golden dot with a fading trail circling the selected head.
class SelectionOrbit extends Control:
	const GOLD := Color(1.0, 0.84, 0.35)
	const LOOPS_PER_SEC := 0.6
	const TRAIL := 10
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		# Track the head button's rect by hand: anchors don't reliably pick
		# up the parent's size while the grid is being (re)laid out.
		var p := get_parent() as Control
		if p:
			position = Vector2.ZERO
			size = p.size
		_t = fposmod(_t + delta * LOOPS_PER_SEC, 1.0)
		queue_redraw()

	func _draw() -> void:
		for i in range(TRAIL, 0, -1):
			var p := _point_on_orbit(fposmod(_t - i * 0.012, 1.0))
			var fade := 1.0 - float(i) / (TRAIL + 1)
			draw_circle(p, 4.5 * fade, Color(GOLD.r, GOLD.g, GOLD.b, 0.16 * fade))
			draw_circle(p, 2.0 * fade, Color(GOLD.r, GOLD.g, GOLD.b, 0.6 * fade))
		# Head of the comet: soft glow, gold body, twinkling white core.
		var head := _point_on_orbit(_t)
		var pulse := 1.0 + 0.25 * sin(Time.get_ticks_msec() * 0.012)
		draw_circle(head, 6.0 * pulse, Color(GOLD.r, GOLD.g, GOLD.b, 0.25))
		draw_circle(head, 3.0, GOLD)
		draw_circle(head, 1.4 * pulse, Color(1.0, 0.98, 0.9))

	## Maps t in [0,1) to a point on a circle hugging the head, starting
	## at the top and running clockwise.
	func _point_on_orbit(t: float) -> Vector2:
		var radius := minf(size.x, size.y) / 2.0 + 2.0
		return size / 2.0 + Vector2.from_angle(t * TAU - PI / 2.0) * radius


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


func _ready() -> void:
	# If a shared link borrowed the slot for the last run, hand the player
	# their own comedian back before anything reads the selection.
	GameState.restore_own_pick()
	var box := build_backdrop()
	add_title(box, "CHOOSE YOUR COMEDIAN", 14)
	add_spacer(box, 6)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 10)

	# Open on the remembered comedian, on whichever page they live. The "?"
	# card shifts every roster index one entry to the right.
	if not GameState.playable.is_empty() and not GameState.random_select:
		_page = (maxi(GameState.playable.find(GameState.selected_character), 0) + 1) / PAGE_SIZE

	# Pagers hug the screen edges (not the row) so they never shift with the
	# widths of the names between them — taps land where the thumb expects.
	if _entry_count() > PAGE_SIZE:
		add_edge_arrow("<", false, func(): _turn_page(-1))
		add_edge_arrow(">", true, func(): _turn_page(1))
	var center := CenterContainer.new()
	center.add_child(_grid)
	row.add_child(center)
	row.add_child(_build_preview())

	# Pinned to the screen bottom rather than the column: it is a caption, not
	# a control, so it can use the strip the buttons moved out of. Built
	# before _fill_page() so that one call seeds its text.
	if _entry_count() > PAGE_SIZE:
		_pager = add_bottom_label()

	_fill_page()
	if GameState.playable.is_empty():
		add_text(box, "No characters found in data/characters.json!")

	add_back_button(func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))

	if GameState.playable.is_empty():
		_fight_btn.disabled = true
		_set_share_enabled(false)
	else:
		_select(RANDOM if GameState.random_select else GameState.selected_character)


## The "?" pick is resolved at the last moment, so the player only
## discovers who they got once the run is already starting. _select() has
## already persisted the pick, so GameState holds the same truth as _selected.
func _start_fight() -> void:
	GameState.start_new_game(GameState.fight_character_index())


## FIGHT! is this screen's one primary action, so it wears a neon-purple
## fill — bright violet tube border, glowing lavender text. It is the only
## filled button in the content column (BACK lives in the top-left corner in
## red), which is what makes it pop. Disabled keeps the default gray
## stylebox on purpose.
func _style_fight_button(b: Button) -> void:
	var fills := {
		"normal": Color(0.45, 0.15, 0.75),
		"hover": Color(0.58, 0.28, 0.9),
		"pressed": Color(0.33, 0.1, 0.58),
		"focus": Color(0.45, 0.15, 0.75),
	}
	for state in fills:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fills[state]
		sb.set_corner_radius_all(3)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.85, 0.6, 1.0)
		b.add_theme_stylebox_override(state, sb)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, Color(0.97, 0.92, 1.0))


## SHARE wears the same violet tube border as FIGHT! but stays hollow, so the
## pair reads as one control group without competing for the primary action.
func _style_share_button(b: Button) -> void:
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


## Hand the highlighted comedian's link to the OS. Never reachable on the "?"
## card — there is no comedian to share until one is picked.
func _on_share() -> void:
	if _selected == RANDOM or _selected < 0 or _selected >= GameState.characters.size():
		return
	var cfg: Dictionary = GameState.characters[_selected]
	var id := String(cfg.get("CharacterId", ""))
	if id == "":
		_flash_toast("NO SHARE ID", Color(1.0, 0.6, 0.5))
		return
	var msg := "Think you can do better? Fight as %s in %s!" % [
			String(cfg.get("CharacterName", "this comedian")), GameState.game_title()]
	match GameState.share_link(GameState.share_url(id), msg):
		GameState.SHARE_NATIVE:
			pass  # the OS sheet is its own confirmation
		GameState.SHARE_COPIED:
			_flash_toast("LINK COPIED!", Color(0.55, 1.0, 0.7))
		_:
			_flash_toast("SHARE FAILED", Color(1.0, 0.6, 0.5))


func _flash_toast(msg: String, color: Color) -> void:
	_share_toast.text = msg
	_share_toast.add_theme_color_override("font_color", color)
	_share_toast.modulate.a = 1.0
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.2)
	_toast_tween.tween_property(_share_toast, "modulate:a", 0.0, 0.5)


func _build_preview() -> Control:
	var panel := VBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	var stage := Control.new()
	stage.custom_minimum_size = PREVIEW_SIZE
	panel.add_child(stage)
	_dancer = Dancer.new()
	_dancer.position = Vector2(PREVIEW_SIZE.x / 2.0, PREVIEW_SIZE.y - 6.0)
	_dancer.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	stage.add_child(_dancer)
	# The mystery mark shown instead of the dancer while "?" is picked —
	# Press Start 2P at this size IS the pixelated game question mark.
	_preview_question = Label.new()
	_preview_question.text = "?"
	_preview_question.visible = false
	_preview_question.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_question.add_theme_font_size_override("font_size", 96)
	_preview_question.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_preview_question.pivot_offset = PREVIEW_SIZE / 2.0
	stage.add_child(_preview_question)
	_preview_name = Label.new()
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_name.custom_minimum_size = Vector2(PREVIEW_SIZE.x, 0)
	_preview_name.add_theme_font_size_override("font_size", 16)
	_preview_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	panel.add_child(_preview_name)
	# FIGHT! sits directly under the comedian it will send out — the pick and
	# the commit in one place, instead of a button row across the bottom.
	# Sized to the preview column so the panel width never jumps.
	add_spacer(panel, 6)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", ACTION_GAP)
	panel.add_child(actions)
	_fight_btn = add_button(actions, "FIGHT!", _start_fight)
	_fight_btn.custom_minimum_size = Vector2(PREVIEW_SIZE.x - SHARE_W - ACTION_GAP, ACTION_H)
	_fight_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_fight_button(_fight_btn)
	# Square, quieter than FIGHT!, and captionless — the glyph is the label.
	_share_btn = add_button(actions, "", _on_share)
	_share_btn.custom_minimum_size = Vector2(SHARE_W, ACTION_H)
	_share_btn.tooltip_text = "Share this comedian"
	_style_share_button(_share_btn)
	_share_icon = ShareIcon.new()
	# anchors AND offsets — anchors alone leaves the old offsets behind.
	_share_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_share_btn.add_child(_share_icon)
	# Reserved strip under the buttons: always present so confirming a copy
	# never nudges the layout.
	_share_toast = add_text(panel, "", 8, Color(0.55, 1.0, 0.7))
	_share_toast.custom_minimum_size = Vector2(PREVIEW_SIZE.x, 12)
	_share_toast.modulate.a = 0.0
	return panel


func _select(index: int) -> void:
	_selected = index
	# Persisted here, not on FIGHT!, so the pick survives quitting from the
	# roster. A no-op when it matches what's already saved.
	GameState.set_random_select(index == RANDOM)
	_dancer.visible = index != RANDOM
	_preview_question.visible = index == RANDOM
	if index == RANDOM:
		_pop_preview(_preview_question, Vector2.ONE)
		_preview_name.text = "???"
	else:
		GameState.set_selected_character(index)
		var cfg: Dictionary = GameState.characters[index]
		_dancer.set_character(cfg)
		_pop_preview(_dancer, Vector2.ONE * PREVIEW_SCALE)
		_preview_name.text = String(cfg.get("CharacterName", "?"))
	_fight_btn.disabled = false
	# Nothing to share on the "?" card: the comedian is not decided until the
	# run starts, so there is no link to hand out yet.
	_set_share_enabled(index != RANDOM)
	_update_highlights()


func _set_share_enabled(on: bool) -> void:
	_share_btn.disabled = not on
	# Buttons do not dim their children, so the glyph is faded by hand.
	_share_icon.modulate.a = 1.0 if on else 0.3


## The freshly picked comedian (or the "?") pops in: born tiny, zooming
## up to full preview size with a little overshoot bounce at the end.
func _pop_preview(node: Node, full_scale: Vector2) -> void:
	if _zoom:
		_zoom.kill()
	node.set("scale", full_scale * ZOOM_START)
	_zoom = create_tween()
	_zoom.tween_property(node, "scale", full_scale, ZOOM_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_highlights() -> void:
	_detach_orbit()
	for card in _grid.get_children():
		if not card.has_meta("index"):
			continue  # blank filler frame, never selected or dimmed
		var on: bool = card.get_meta("index") == _selected
		card.modulate = Color(1, 1, 1) if on else Color(0.62, 0.62, 0.68)
		if on:
			if _orbit == null:
				_orbit = SelectionOrbit.new()
			card.get_child(0).add_child(_orbit)


## The orbit is parked (unparented) while its card is being rebuilt or the
## selection lives on another page, so page turns never free it.
func _detach_orbit() -> void:
	if _orbit and _orbit.get_parent():
		_orbit.get_parent().remove_child(_orbit)


func _exit_tree() -> void:
	if _orbit and not _orbit.is_inside_tree():
		_orbit.free()


## Grid entries = the "?" card + every playable comedian (0 when nobody is
## playable, so an empty — or fully disabled — roster keeps its plain error
## screen). Entry e > 0 maps to roster index GameState.playable[e - 1]; cards
## carry that roster index, never their grid position.
func _entry_count() -> int:
	return 0 if GameState.playable.is_empty() else GameState.playable.size() + 1


func _page_count() -> int:
	return maxi(ceili(_entry_count() / float(PAGE_SIZE)), 1)


func _turn_page(dir: int) -> void:
	_page = wrapi(_page + dir, 0, _page_count())
	_fill_page()


func _fill_page() -> void:
	_detach_orbit()
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var start := _page * PAGE_SIZE
	for e in range(start, mini(start + PAGE_SIZE, _entry_count())):
		if e == 0:
			_grid.add_child(_random_card())
		else:
			var ri: int = GameState.playable[e - 1]
			_grid.add_child(_character_card(ri, GameState.characters[ri]))
	# Pad a short (only ever the last) page with blank frames so the 3x3
	# grid never changes shape.
	if _entry_count() > 0:
		while _grid.get_child_count() < PAGE_SIZE:
			_grid.add_child(_empty_card())
	if _pager:
		_pager.text = "PAGE %d / %d" % [_page + 1, _page_count()]
	_update_highlights()


## The "?" card heading the roster: a big pixel-font question mark where
## a head would be. Selecting it defers the pick to _start_fight().
func _random_card() -> VBoxContainer:
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.set_meta("index", RANDOM)
	var btn := Button.new()
	btn.flat = true
	btn.text = "?"
	btn.custom_minimum_size = Vector2(64, 64)
	btn.add_theme_font_size_override("font_size", 40)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, Color(1.0, 0.85, 0.4))
	btn.pressed.connect(func():
		GameState.play_sfx("click")
		_select(RANDOM))
	card.add_child(btn)
	var name_label := Label.new()
	name_label.text = "RANDOM"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 8)
	card.add_child(name_label)
	return card


## A blank placeholder frame (no meta, not clickable) keeping short pages
## on the same 3x3 grid as full ones.
func _empty_card() -> VBoxContainer:
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(64, 64)
	# Wide columns (long neighbor names) must not stretch the frame into a
	# rectangle — hold it at 64x64, centered in the cell.
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.45, 0.45, 0.52, 0.35)
	frame.add_theme_stylebox_override("panel", sb)
	card.add_child(frame)
	var pad := Label.new()
	pad.text = " "  # same metrics as a name label, so rows stay aligned
	pad.add_theme_font_size_override("font_size", 8)
	card.add_child(pad)
	return card


func _character_card(index: int, cfg: Dictionary) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.set_meta("index", index)
	var btn := TextureButton.new()
	btn.texture_normal = CharacterFactory.head_texture(String(cfg.get("HeadSpritePath", "")))
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = Vector2(64, 64)
	btn.pressed.connect(func():
		GameState.play_sfx("click")
		_select(index))
	card.add_child(btn)
	var name_label := Label.new()
	name_label.text = String(cfg.get("CharacterName", "?"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 8)
	card.add_child(name_label)
	return card
