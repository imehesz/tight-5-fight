extends MenuBase
## Main Menu: Play, Settings, Scoreboard, About.


func _ready() -> void:
	var box := build_backdrop()
	add_title(box, "OPEN MIC NIGHT!", 40)
	add_text(box, "beat the streets. bomb gracefully.", 11, Color(0.7, 0.7, 0.8))
	add_spacer(box, 12)
	add_button(box, "PLAY", func(): GameState.change_scene(GameState.SCENE_CHARACTER_SELECT))
	add_button(box, "SETTINGS", func(): GameState.change_scene(GameState.SCENE_SETTINGS))
	add_button(box, "SCOREBOARD", func(): GameState.change_scene(GameState.SCENE_SCOREBOARD))
	add_button(box, "ABOUT", func(): GameState.change_scene(GameState.SCENE_ABOUT))
