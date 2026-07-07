extends Control
## Splash screen: key art + title, any input continues to the main menu.

const ART_PATH := "res://assets/art/splash_jax.png"

var _done := false


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if ResourceLoader.exists(ART_PATH):
		var art := TextureRect.new()
		art.texture = load(ART_PATH)
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(art)

	var title := Label.new()
	title.text = ""
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 18
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10)
	add_child(title)

	var tap := Label.new()
	tap.text = "TAP TO START"
	tap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tap.offset_top = -40
	tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tap.add_theme_font_size_override("font_size", 14)
	tap.add_theme_color_override("font_outline_color", Color.BLACK)
	tap.add_theme_constant_override("outline_size", 6)
	add_child(tap)
	var tw := create_tween().set_loops()
	tw.tween_property(tap, "modulate:a", 0.15, 0.6)
	tw.tween_property(tap, "modulate:a", 1.0, 0.6)


func _input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventKey and event.pressed)
	if pressed and not _done:
		_done = true
		GameState.play_sfx("click")
		GameState.change_scene(GameState.SCENE_MAIN_MENU)
