extends MenuBase
## Settings: Music and SFX volume sliders (persisted to user://settings.json).
## The SFX slider plays a hurt sound at the new volume so changes are audible.

var _feedback_cooldown := 0.0


func _ready() -> void:
	var box := build_backdrop()
	add_title(box, "SETTINGS", 18)
	add_spacer(box, 10)
	box.add_child(_volume_row("MUSIC", GameState.music_volume, GameState.set_music_volume))
	box.add_child(_volume_row("SFX", GameState.sfx_volume, GameState.set_sfx_volume, true))
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
