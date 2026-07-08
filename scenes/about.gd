extends MenuBase
## About: credits and a silly blurb.

const BLURB := """Somewhere between the parking lot and the stage,
every comedian must fight for the mic. Literally.

Walk the mean streets. Silence the hecklers.
Storm the venues. Duck the boss's beer bottles.
Comedy is a contact sport.

No comedians were permanently harmed
in the making of this game. Just their egos.

Built with Godot. Powered by cheap laughs."""

const SUPPORT_URL := "https://buymeacoffee.com/imehesz"


func _ready() -> void:
	var box := build_backdrop()
	add_title(box, "ABOUT", 18)
	add_spacer(box, 6)
	add_text(box, BLURB, 8)
	add_spacer(box, 10)
	add_text(box, "Enjoying the fight? Keep the mic on:", 8)
	add_button(box, "BUY ME A COFFEE", func(): OS.shell_open(SUPPORT_URL))
	add_spacer(box, 12)
	add_button(box, "BACK", func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))
