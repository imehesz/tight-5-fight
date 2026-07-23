extends MenuBase
## Main Menu: Play, Settings, Scoreboard, About.
##
## The SPONSORS entry is temporarily commented out (2026-07-23) so players meet
## the in-game billboard ads with no menu explaining them — we want to see the
## unprimed reaction first. The sponsors_menu scene, the Sponsors autoload and
## the in-game billboards are all untouched; uncomment the marked blocks below
## to bring the button back.

#var _sponsors_btn: Button


func _ready() -> void:
	var box := build_backdrop()
	add_title(box, GameState.menu_title(), 24)
	add_text(box, "beat the streets. bomb gracefully.", 8, Color(0.7, 0.7, 0.8))
	add_spacer(box, 12)
	add_button(box, "PLAY", func(): GameState.change_scene(GameState.SCENE_CHARACTER_SELECT))
	add_button(box, "SETTINGS", func(): GameState.change_scene(GameState.SCENE_SETTINGS))
	add_button(box, "SCOREBOARD", func(): GameState.change_scene(GameState.SCENE_SCOREBOARD))
	add_button(box, "ABOUT", func(): GameState.change_scene(GameState.SCENE_ABOUT))
	# --- SPONSORS button: temporarily hidden, restore this block ------------
	#_sponsors_btn = add_button(box, "SPONSORS", func(): GameState.change_scene(GameState.SCENE_SPONSORS))
	#_sponsors_btn.visible = not Sponsors.active.is_empty()
	#if not Sponsors.is_ready():
		#Sponsors.ensure_loaded()
		#Sponsors.sponsors_ready.connect(_show_sponsors_if_any)
	# -----------------------------------------------------------------------


# --- SPONSORS button: temporarily hidden, restore with the block above ------
#func _show_sponsors_if_any() -> void:
	#_sponsors_btn.visible = not Sponsors.active.is_empty()
