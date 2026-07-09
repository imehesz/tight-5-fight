extends MenuBase
## Settings: Music and SFX volume sliders, plus the player's outfit color,
## previewed live on their comedian (all persisted per game — see
## GameState.SETTINGS_PATH).
## The SFX slider plays a hurt sound at the new volume so changes are audible.

## Matches the character select preview, so the comedian is framed and sized
## the same on both screens.
const PREVIEW_SIZE := Vector2(150, 170)
const PREVIEW_SCALE := Fighter.BODY_SCALE * 1.5

var _feedback_cooldown := 0.0
var _dancer: Dancer


func _ready() -> void:
	var box := build_backdrop()
	add_title(box, "SETTINGS", 18)
	add_spacer(box, 10)

	# Controls on the left, comedian on the right — the character select layout.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	col.add_child(_volume_row("MUSIC", GameState.music_volume, GameState.set_music_volume))
	col.add_child(_volume_row("SFX", GameState.sfx_volume, GameState.set_sfx_volume, true))
	add_spacer(col, 6)
	add_text(col, "OUTFIT")
	col.add_child(_outfit_picker())
	row.add_child(_outfit_preview())

	add_spacer(box, 14)
	add_button(box, "BACK", func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))
	_add_version_label()


## Faint build stamp pinned to the screen bottom, so a deployed build can be
## eyeballed as up to date (see GameState.version_string).
func _add_version_label() -> void:
	var v := Label.new()
	v.text = GameState.version_string()
	v.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	v.offset_top = -16
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 8)
	v.modulate = Color(1.0, 1.0, 1.0, 0.3)
	add_child(v)


func _process(delta: float) -> void:
	_feedback_cooldown = maxf(_feedback_cooldown - delta, 0.0)


func _volume_row(label_text: String, value: float, setter: Callable,
		feedback := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(60, 0)
	l.add_theme_font_size_override("font_size", 8)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(200, 20)
	slider.value_changed.connect(func(v):
		setter.call(v)
		# Throttled so dragging doesn't machine-gun the sample.
		if feedback and _feedback_cooldown <= 0.0:
			_feedback_cooldown = 0.25
			GameState.play_sfx("hurt"))
	row.add_child(slider)
	return row


## The player's comedian, wearing the current outfit. Falls back to the first
## on the roster for someone who has never picked one.
func _outfit_preview() -> Control:
	var panel := VBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	var stage := Control.new()
	stage.custom_minimum_size = PREVIEW_SIZE
	panel.add_child(stage)
	if GameState.characters.is_empty():
		return panel
	_dancer = Dancer.new()
	_dancer.position = Vector2(PREVIEW_SIZE.x / 2.0, PREVIEW_SIZE.y - 6.0)
	_dancer.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	stage.add_child(_dancer)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(PREVIEW_SIZE.x, 0)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	name_label.text = String(GameState.selected_character_data().get("CharacterName", "?"))
	panel.add_child(name_label)

	_refresh_preview()
	return panel


## Dancer reads GameState.outfit as it builds its frames, so re-applying the
## character is what re-dyes it.
func _refresh_preview() -> void:
	if is_instance_valid(_dancer):
		_dancer.set_character(GameState.selected_character_data())


## The player's outfit color: eight swatches, 4 per row. Picking one saves
## immediately, and is worn on whichever comedian is selected.
func _outfit_picker() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 9)
	grid.add_theme_constant_override("v_separation", 9)

	var buttons: Array[Button] = []
	for i in CharacterFactory.OUTFITS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 26)
		b.tooltip_text = String(CharacterFactory.OUTFITS[i]["name"])
		b.pressed.connect(func():
			GameState.play_sfx("click")
			GameState.set_outfit(i)
			_paint_swatches(buttons)
			_refresh_preview())
		grid.add_child(b)
		buttons.append(b)
	_paint_swatches(buttons)
	return grid


func _paint_swatches(buttons: Array[Button]) -> void:
	for i in buttons.size():
		var sb := StyleBoxFlat.new()
		sb.bg_color = CharacterFactory.outfit_color(i)
		sb.set_corner_radius_all(3)
		# The picked swatch gets the menu's gold ring; the rest a thin outline
		# so a dark outfit still reads as a button against the backdrop.
		sb.set_border_width_all(3 if i == GameState.outfit else 1)
		sb.border_color = Color(1.0, 0.85, 0.4) if i == GameState.outfit \
				else Color(0.0, 0.0, 0.0, 0.5)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			buttons[i].add_theme_stylebox_override(state, sb)
