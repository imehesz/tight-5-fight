extends MenuBase
## Character Select: grid of comedian heads parsed from characters.json
## (paged 9 at a time with LEFT/RIGHT arrows) on the left, a dancing
## preview of the highlighted comedian on the right. Tapping a head only
## selects it; the FIGHT! button starts the run.

const GRID_COLUMNS := 3
const PAGE_SIZE := 9
const PREVIEW_SIZE := Vector2(150, 170)
## 1.5x the in-game fighter size.
const PREVIEW_SCALE := Fighter.BODY_SCALE * 1.5

var _page := 0
var _selected := -1
var _grid: GridContainer
var _dancer: Dancer
var _preview_name: Label
var _fight_btn: Button
var _orbit: SelectionOrbit


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

	var paged := GameState.characters.size() > PAGE_SIZE
	if paged:
		row.add_child(_arrow_button("<", -1))
	var center := CenterContainer.new()
	center.add_child(_grid)
	row.add_child(center)
	if paged:
		row.add_child(_arrow_button(">", 1))
	row.add_child(_build_preview())

	_fill_page()
	if GameState.characters.is_empty():
		add_text(box, "No characters found in data/characters.json!")

	add_spacer(box, 10)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_fight_btn = add_button(buttons, "FIGHT!", func(): GameState.start_new_game(_selected))
	add_button(buttons, "BACK", func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))

	if GameState.characters.is_empty():
		_fight_btn.disabled = true
	else:
		_select(0)


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
	var cfg: Dictionary = GameState.characters[index]
	_dancer.set_character(cfg)
	_preview_name.text = String(cfg.get("CharacterName", "?"))
	_fight_btn.disabled = false
	_update_highlights()


func _update_highlights() -> void:
	_detach_orbit()
	for card in _grid.get_children():
		var on: bool = card.get_meta("index", -1) == _selected
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


func _page_count() -> int:
	return maxi(ceili(GameState.characters.size() / float(PAGE_SIZE)), 1)


func _turn_page(dir: int) -> void:
	_page = wrapi(_page + dir, 0, _page_count())
	_fill_page()


func _fill_page() -> void:
	_detach_orbit()
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var start := _page * PAGE_SIZE
	for i in range(start, mini(start + PAGE_SIZE, GameState.characters.size())):
		_grid.add_child(_character_card(i, GameState.characters[i]))
	_update_highlights()


func _arrow_button(label: String, dir: int) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(30, 60)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(func():
		GameState.play_sfx("click")
		_turn_page(dir))
	return b


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
