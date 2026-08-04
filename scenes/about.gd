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
const LEGAL_URL := "https://games.imstandup.com/tight5fight/legal.html"

## Everyone who gets a nod, in the order they appear on screen.
const THANKS := [
	"Kayla Mai",
	"D-Man",
	"The JAX & Daytona Comedy Community",
	"Coffee",
]

## Fixed viewport for the scrolling body; the blurb + thanks list runs taller
## than the screen, so it scrolls under a title that stays put.
const BODY_SIZE := Vector2(400, 250)


func _ready() -> void:
	var box := build_backdrop()
	add_title(box, "ABOUT", 18)
	add_spacer(box, 6)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = BODY_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	add_text(body, BLURB, 8)
	add_spacer(body, 10)
	add_text(body, "Enjoying the fight? Keep the mic on:", 8)
	# Inside a fill-width column a button would stretch edge to edge; keep it
	# the same 220-wide target every other menu uses.
	var coffee := add_button(body, "BUY ME A COFFEE", func(): OS.shell_open(SUPPORT_URL))
	coffee.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	add_spacer(body, 14)
	add_title(body, "SPECIAL THANKS", 12)
	add_spacer(body, 2)
	for who in THANKS:
		add_text(body, who, 9)
	add_spacer(body, 10)

	# Opt-out route for anyone listed above who'd rather not be in the game.
	var optout := add_button(body, "THIS SUCKS, TAKE ME OFF", func(): OS.shell_open(LEGAL_URL))
	optout.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	MenuBase.style_purple_button(optout)
	add_spacer(body, 6)

	add_back_button(func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))
