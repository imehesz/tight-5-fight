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


func _ready() -> void:
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
	if not GameState.characters.is_empty() and not GameState.random_select:
		_page = (GameState.selected_character + 1) / PAGE_SIZE

	# Pagers hug the screen edges (not the row) so they never shift with the
	# widths of the names between them — taps land where the thumb expects.
	if _entry_count() > PAGE_SIZE:
		add_edge_arrow("<", false, func(): _turn_page(-1))
		add_edge_arrow(">", true, func(): _turn_page(1))
	var center := CenterContainer.new()
	center.add_child(_grid)
	row.add_child(center)
	row.add_child(_build_preview())

	_fill_page()
	if GameState.characters.is_empty():
		add_text(box, "No characters found in data/characters.json!")

	add_spacer(box, 8)
	if _entry_count() > PAGE_SIZE:
		box.add_child(_build_pager())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_fight_btn = add_button(buttons, "FIGHT!", _start_fight)
	_style_fight_button(_fight_btn)
	add_button(buttons, "BACK", func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))

	if GameState.characters.is_empty():
		_fight_btn.disabled = true
	else:
		_select(RANDOM if GameState.random_select else GameState.selected_character)


## The "?" pick is resolved here, at the last moment, so the player only
## discovers who they got once the run is already starting.
func _start_fight() -> void:
	var index := _selected
	if index == RANDOM:
		index = randi() % GameState.characters.size()
	GameState.start_new_game(index)


## FIGHT! is this screen's one primary action, so it wears a neon-purple
## fill — bright violet tube border, glowing lavender text — while BACK
## stays on the stock gray, which is what makes this one pop. Disabled
## keeps the default gray stylebox on purpose.
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
	_update_highlights()


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


## Same "PAGE x / y" treatment as the leaderboard's pager. Built after the
## first _fill_page() runs, so it seeds its own text.
func _build_pager() -> HBoxContainer:
	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	_pager = Label.new()
	_pager.custom_minimum_size = Vector2(110, 0)
	_pager.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pager.add_theme_font_size_override("font_size", 8)
	_pager.add_theme_color_override("font_color", Color(0.6, 0.6, 0.68))
	_pager.text = "PAGE %d / %d" % [_page + 1, _page_count()]
	pager.add_child(_pager)
	return pager


## Grid entries = the "?" card + the whole roster (0 when there's no roster,
## so an empty characters.json keeps its plain error screen).
func _entry_count() -> int:
	return 0 if GameState.characters.is_empty() else GameState.characters.size() + 1


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
			_grid.add_child(_character_card(e - 1, GameState.characters[e - 1]))
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
