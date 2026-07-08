extends MenuBase
## Game Over: final score, high-score callout, replay / menu options,
## plus the just-played character dancing it off on the left.

## Twice the in-game fighter size.
const DANCE_SCALE := Fighter.BODY_SCALE * 2.0
const DANCE_FEET_POS := Vector2(110, 330)


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
	var dancer := Dancer.new()
	dancer.position = DANCE_FEET_POS
	dancer.scale = Vector2(DANCE_SCALE, DANCE_SCALE)
	dancer.set_character(GameState.selected_character_data())
	add_child(dancer)
