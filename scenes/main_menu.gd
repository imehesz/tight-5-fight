extends MenuBase
## Main Menu: Play, Settings, Scoreboard, About — plus Sponsors, which only
## appears (at the bottom) once the roster loads with at least one active
## sponsor. No sponsors signed → no dead menu entry.

var _sponsors_btn: Button


func _ready() -> void:
	var box := build_backdrop()
	add_title(box, GameState.menu_title(), 24)
	add_text(box, "beat the streets. bomb gracefully.", 8, Color(0.7, 0.7, 0.8))
	add_spacer(box, 12)
	add_button(box, "PLAY", func(): GameState.change_scene(GameState.SCENE_CHARACTER_SELECT))
	add_button(box, "SETTINGS", func(): GameState.change_scene(GameState.SCENE_SETTINGS))
	add_button(box, "SCOREBOARD", func(): GameState.change_scene(GameState.SCENE_SCOREBOARD))
	add_button(box, "ABOUT", func(): GameState.change_scene(GameState.SCENE_ABOUT))
	_sponsors_btn = add_button(box, "SPONSORS", func(): GameState.change_scene(GameState.SCENE_SPONSORS))
	_sponsors_btn.visible = not Sponsors.active.is_empty()
	if not Sponsors.is_ready():
		Sponsors.ensure_loaded()
		Sponsors.sponsors_ready.connect(_show_sponsors_if_any)


func _show_sponsors_if_any() -> void:
	_sponsors_btn.visible = not Sponsors.active.is_empty()
