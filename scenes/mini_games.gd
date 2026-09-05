extends MenuBase
## MINI GAMES: the shelf of side games, reached from CHARACTER SELECT.
##
## Deliberately NOT part of a run — nothing here starts the clock, spends a
## life or touches the score. The comedian picked next door is irrelevant to
## everything on this shelf, which is why the button that opens it is the one
## control on character select that stays enabled with an empty roster.
##
## Each entry is a splash tile with its name underneath. An entry with no
## scene yet draws dimmed under a COMING SOON banner and does not respond to
## a tap — that is how a game gets announced here before it is built, without
## a dead button that looks broken.

## The shelf, in display order. `scene` empty means "announced, not built".
const GAMES := [
	{
		"title": "SLOT MACHINE",
		"art": "res://shared/assets/minigames/tile_slots.png",
		"scene": GameState.SCENE_SLOT_MACHINE,
	},
	{
		"title": "BLACK JACK",
		"art": "res://shared/assets/minigames/tile_blackjack.png",
		"scene": "",
	},
]

## Tile art is authored at 3:2, so the box is too. Big enough that the art
## still reads at a glance, small enough that three would still fit on the
## shelf when a third game shows up.
const TILE_SIZE := Vector2(180, 120)
const TILE_GAP := 24
const CAPTION_FONT := 10
## What an unbuilt entry looks like: art dimmed to this, banner over the top.
const SOON_DIM := 0.35


func _ready() -> void:
	var box := build_backdrop()
	add_title(box, "MINI GAMES", 14)
	add_text(box, "warm up between sets", 8, Color(0.7, 0.7, 0.8))
	add_spacer(box, 10)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", TILE_GAP)
	box.add_child(row)
	for game in GAMES:
		row.add_child(_build_tile(game))

	add_back_button(func(): GameState.change_scene(GameState.SCENE_CHARACTER_SELECT))


## One shelf entry: splash art over its name. The art is a TextureButton so
## the whole tile is the tap target rather than a caption-sized sliver.
func _build_tile(game: Dictionary) -> Control:
	var scene := String(game.get("scene", ""))
	var ready_to_play := scene != ""

	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 6)

	# The art and its COMING SOON banner share one box, so the banner sits on
	# the picture rather than pushing the caption down.
	var stage := Control.new()
	stage.custom_minimum_size = TILE_SIZE

	var btn := TextureButton.new()
	btn.custom_minimum_size = TILE_SIZE
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	var art := String(game.get("art", ""))
	if art != "" and ResourceLoader.exists(art):
		btn.texture_normal = load(art)
	btn.modulate = Color(1, 1, 1) if ready_to_play else Color(1, 1, 1, SOON_DIM)
	if ready_to_play:
		btn.pressed.connect(guard_tap(func():
			GameState.play_sfx("click")
			GameState.change_scene(scene)))
	else:
		btn.disabled = true
	stage.add_child(btn)

	# A framed border over the art, so a tile reads as a card even where the
	# splash happens to fade out at its own edges.
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(MenuBase.BUTTON_RADIUS)
	sb.set_border_width_all(MenuBase.BUTTON_BORDER)
	sb.border_color = MenuBase.PURPLE_BORDER if ready_to_play else Color(0.5, 0.5, 0.58)
	frame.add_theme_stylebox_override("panel", sb)
	stage.add_child(frame)

	if not ready_to_play:
		stage.add_child(_soon_banner())
	card.add_child(stage)

	var caption := Label.new()
	caption.text = String(game.get("title", "?"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.custom_minimum_size = Vector2(TILE_SIZE.x, 0)
	caption.add_theme_font_size_override("font_size", CAPTION_FONT)
	caption.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.4) if ready_to_play else Color(0.6, 0.6, 0.68))
	card.add_child(caption)
	return card


## The COMING SOON strip across an unbuilt tile: a dark band with gold text,
## centred on the art and ignoring the mouse so it never eats a tap the
## disabled button below it would have swallowed anyway.
func _soon_banner() -> Control:
	var band := Panel.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_anchors_preset(Control.PRESET_CENTER)
	band.custom_minimum_size = Vector2(TILE_SIZE.x, 22)
	band.offset_left = -TILE_SIZE.x / 2.0
	band.offset_right = TILE_SIZE.x / 2.0
	band.offset_top = -11
	band.offset_bottom = 11
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.09, 0.85)
	band.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = "COMING SOON"
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	band.add_child(l)
	return band
