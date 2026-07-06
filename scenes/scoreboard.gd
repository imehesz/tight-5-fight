extends MenuBase
## Scoreboard: local top-10 high scores (persisted to user://highscores.json).


func _ready() -> void:
	var box := build_backdrop(MENU_BG)
	add_title(box, "HIGH SCORES", 18)
	add_spacer(box, 8)
	if GameState.high_scores.is_empty():
		add_text(box, "No scores yet. Go bomb somewhere!")
	for i in GameState.high_scores.size():
		var entry: Dictionary = GameState.high_scores[i]
		var row := "%2d. %6d  V%-2d %s (%s)" % [
			i + 1,
			int(entry.get("score", 0)),
			int(entry.get("venue", 0)),
			String(entry.get("character", "?")),
			String(entry.get("date", "")),
		]
		var color := Color(1.0, 0.85, 0.4) if i == GameState.last_run_rank else Color(0.85, 0.85, 0.9)
		add_text(box, row, 8, color)
	add_spacer(box, 14)
	add_button(box, "BACK", func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))
