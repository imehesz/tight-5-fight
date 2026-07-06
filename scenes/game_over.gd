extends MenuBase
## Game Over: final score, high-score callout, replay / menu options.


func _ready() -> void:
	var box := build_backdrop()
	add_title(box, "GAME OVER", 24, Color(0.95, 0.3, 0.25))
	add_text(box, "%s bombed after %d venue%s." % [
		String(GameState.selected_character_data().get("CharacterName", "You")),
		GameState.venues_entered,
		"" if GameState.venues_entered == 1 else "s",
	])
	add_spacer(box, 8)
	add_title(box, "FINAL SCORE: %d" % GameState.score, 14, Color(0.9, 0.9, 0.95))
	if GameState.last_run_rank >= 0:
		add_title(box, "NEW HIGH SCORE — #%d!" % (GameState.last_run_rank + 1), 10)
	add_spacer(box, 14)
	add_button(box, "PLAY AGAIN", func(): GameState.change_scene(GameState.SCENE_CHARACTER_SELECT))
	add_button(box, "SCOREBOARD", func(): GameState.change_scene(GameState.SCENE_SCOREBOARD))
	add_button(box, "MAIN MENU", func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))
