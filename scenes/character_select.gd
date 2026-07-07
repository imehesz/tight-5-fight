extends MenuBase
## Character Select: grid of comedian heads parsed from characters.json,
## paged 9 at a time with LEFT/RIGHT arrows when there's more than one page.

const GRID_COLUMNS := 3
const PAGE_SIZE := 9

var _page := 0
var _grid: GridContainer


func _ready() -> void:
	var box := build_backdrop(MENU_BG)
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

	_fill_page()
	if GameState.characters.is_empty():
		add_text(box, "No characters found in data/characters.json!")

	add_spacer(box, 10)
	add_button(box, "BACK", func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))


func _page_count() -> int:
	return maxi(ceili(GameState.characters.size() / float(PAGE_SIZE)), 1)


func _turn_page(dir: int) -> void:
	_page = wrapi(_page + dir, 0, _page_count())
	_fill_page()


func _fill_page() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var start := _page * PAGE_SIZE
	for i in range(start, mini(start + PAGE_SIZE, GameState.characters.size())):
		_grid.add_child(_character_card(i, GameState.characters[i]))


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
	var btn := TextureButton.new()
	btn.texture_normal = CharacterFactory.head_texture(String(cfg.get("HeadSpritePath", "")))
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = Vector2(64, 64)
	btn.pressed.connect(func(): GameState.start_new_game(index))
	card.add_child(btn)
	var name_label := Label.new()
	name_label.text = String(cfg.get("CharacterName", "?"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 8)
	card.add_child(name_label)
	return card
