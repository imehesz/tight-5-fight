extends MenuBase
## Settings: Music and SFX volume sliders (persisted to user://settings.json).
## The SFX slider plays a punch at the new volume so changes are audible.

var _feedback_cooldown := 0.0


func _ready() -> void:
	var box := build_backdrop(MENU_BG)
	add_title(box, "SETTINGS", 18)
	add_spacer(box, 10)
	box.add_child(_volume_row("MUSIC", GameState.music_volume, GameState.set_music_volume))
	box.add_child(_volume_row("SFX", GameState.sfx_volume, GameState.set_sfx_volume, true))
	add_spacer(box, 14)
	add_button(box, "BACK", func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))


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
			GameState.play_sfx("punch"))
	row.add_child(slider)
	return row
