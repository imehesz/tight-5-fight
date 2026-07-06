extends MenuBase
## Character Select: grid of comedian heads parsed from characters.json.

const GRID_COLUMNS := 3


func _ready() -> void:
	var box := build_backdrop()
	add_title(box, "CHOOSE YOUR COMEDIAN", 14)
	add_spacer(box, 6)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	var center := CenterContainer.new()
	center.add_child(grid)
	box.add_child(center)

	for i in GameState.characters.size():
		grid.add_child(_character_card(i, GameState.characters[i]))
	if GameState.characters.is_empty():
		add_text(box, "No characters found in data/characters.json!")

	add_spacer(box, 10)
	add_button(box, "BACK", func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))


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
