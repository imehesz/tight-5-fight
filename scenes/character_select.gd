extends MenuBase
## Character Select, in three columns: the dancing preview of the highlighted
## comedian (with SHARE under it) on the LEFT, the grid of comedian heads
## parsed from characters.json (paged 9 at a time with LEFT/RIGHT arrows) in
## the MIDDLE, and the two ways to play on the RIGHT — CLASSIC starts the run,
## MINI GAMES opens the shelf. Tapping a head only selects it.
##
## Slot 1 of the grid is a "?" card: pick it and CLASSIC rolls a random
## comedian, revealed only once the run starts. Short last pages are
## padded with blank frames so the 3x3 grid never changes shape.
##
## The three columns plus their gaps are sized to clear the edge pagers on
## both sides — see COLUMN_GAP before widening any of them.

const GRID_COLUMNS := 3
const PAGE_SIZE := 9
## _selected value meaning "the ? card" — resolved to a real roster index
## the moment CLASSIC is pressed.
const RANDOM := -1
const PREVIEW_SIZE := Vector2(120, 170)
## Buttons are 44 tall so the square SHARE target stays comfortably
## thumb-sized on a phone; ACTION_W fits "MINI GAMES" at ACTION_FONT with
## room to spare (Press Start 2P advances one em per glyph, so ten glyphs at
## 10 is exactly 100px).
const ACTION_H := 44
const ACTION_W := 120
const ACTION_FONT := 10
const ACTION_GAP := 8
## THE WIDTH BUDGET. The edge pagers sit at x 10..55 and 585..630, so the row
## has to live inside those: 120 + 10 + (3*76 + 2*12) + 10 + 120 = 512,
## centred, which leaves 9px of clearance at either side — the same margin
## this screen ran with before the buttons moved over here. Widen anything
## below and the pagers start eating taps meant for the outer columns.
##
## What actually sets the grid's width is NAME_W, not the 64px heads: a cell
## is as wide as its caption, so before these captions were capped a single
## long comedian ("Dr. Anna Lepeley" is 128px at NAME_FONT) stretched a whole
## column and the grid measured 328. Capping it makes the grid 252 wide for
## every roster instead of however long the longest name happens to be.
const COLUMN_GAP := 10
const GRID_H_SEP := 12
## THE HEIGHT BUDGET. Three rows of (64 head + CARD_SEP + 22 caption) plus two
## of these is the tallest column, and the whole screen has 360 less the
## SAFE_BOTTOM lift to sit in. At these numbers the content is 312 tall and
## clears the top edge by 8px; loosen either and the title runs off the top.
const GRID_V_SEP := 6
## The head button, and the caption under it. NAME_H is fixed at two lines so
## every row is the same height whether its names wrap or not; names too long
## for two lines are ellipsised, and the full name is always readable in full
## size under the dancer anyway.
const CELL := 64
const NAME_W := 76
const NAME_H := 22
const NAME_FONT := 8
## Head-to-caption gap inside a cell. Tighter than the theme default because
## three rows of it is the tallest thing on the screen — see the height note
## on GRID_V_SEP.
const CARD_SEP := 2
## 1.5x the in-game fighter size.
const PREVIEW_SCALE := Fighter.BODY_SCALE * 1.5
## Pop-in zoom on selection: born this fraction of full size, grown back
## over ZOOM_TIME seconds.
const ZOOM_START := 0.1
const ZOOM_TIME := 0.3

var _page := 0
var _selected := -1
var _grid: GridContainer
var _pager: Label
var _dancer: Dancer
var _preview_question: Label
var _preview_name: Label
var _classic_btn: Button
var _mini_btn: Button
var _share_btn: Button
var _orbit: SelectionOrbit
var _zoom: Tween


## A shiny golden dot with a fading trail circling the selected head.
class SelectionOrbit extends Control:
	const GOLD := Color(1.0, 0.84, 0.35)
	const LOOPS_PER_SEC := 0.6
	const TRAIL := 10
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		# Track the head button's rect by hand: anchors don't reliably pick
		# up the parent's size while the grid is being (re)laid out.
		var p := get_parent() as Control
		if p:
			position = Vector2.ZERO
			size = p.size
		_t = fposmod(_t + delta * LOOPS_PER_SEC, 1.0)
		queue_redraw()

	func _draw() -> void:
		for i in range(TRAIL, 0, -1):
			var p := _point_on_orbit(fposmod(_t - i * 0.012, 1.0))
			var fade := 1.0 - float(i) / (TRAIL + 1)
			draw_circle(p, 4.5 * fade, Color(GOLD.r, GOLD.g, GOLD.b, 0.16 * fade))
			draw_circle(p, 2.0 * fade, Color(GOLD.r, GOLD.g, GOLD.b, 0.6 * fade))
		# Head of the comet: soft glow, gold body, twinkling white core.
		var head := _point_on_orbit(_t)
		var pulse := 1.0 + 0.25 * sin(Time.get_ticks_msec() * 0.012)
		draw_circle(head, 6.0 * pulse, Color(GOLD.r, GOLD.g, GOLD.b, 0.25))
		draw_circle(head, 3.0, GOLD)
		draw_circle(head, 1.4 * pulse, Color(1.0, 0.98, 0.9))

	## Maps t in [0,1) to a point on a circle hugging the head, starting
	## at the top and running clockwise.
	func _point_on_orbit(t: float) -> Vector2:
		var radius := minf(size.x, size.y) / 2.0 + 2.0
		return size / 2.0 + Vector2.from_angle(t * TAU - PI / 2.0) * radius


func _ready() -> void:
	# If a shared link borrowed the slot for the last run, hand the player
	# their own comedian back before anything reads the selection.
	GameState.restore_own_pick()
	var box := build_backdrop()
	add_title(box, "CHOOSE YOUR COMEDIAN", 14)
	add_spacer(box, 6)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", COLUMN_GAP)
	box.add_child(row)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", GRID_H_SEP)
	_grid.add_theme_constant_override("v_separation", GRID_V_SEP)

	# Open on the remembered comedian, on whichever page they live. The "?"
	# card shifts every roster index one entry to the right.
	if not GameState.playable.is_empty() and not GameState.random_select:
		_page = (maxi(GameState.playable.find(GameState.selected_character), 0) + 1) / PAGE_SIZE

	# Pagers hug the screen edges (not the row) so they never shift with the
	# widths of the names between them — taps land where the thumb expects.
	if _entry_count() > PAGE_SIZE:
		add_edge_arrow("<", false, func(): _turn_page(-1))
		add_edge_arrow(">", true, func(): _turn_page(1))
	var center := CenterContainer.new()
	center.add_child(_grid)
	# Preview LEFT, roster MIDDLE, the two play buttons RIGHT.
	row.add_child(_build_preview())
	row.add_child(center)
	row.add_child(_build_actions())

	# Pinned to the screen bottom rather than the column: it is a caption, not
	# a control, so it can use the strip the buttons moved out of. Built
	# before _fill_page() so that one call seeds its text.
	if _entry_count() > PAGE_SIZE:
		_pager = add_bottom_label()

	_fill_page()
	if GameState.playable.is_empty():
		add_text(box, "No characters found in data/characters.json!")

	add_back_button(func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))

	if GameState.playable.is_empty():
		_classic_btn.disabled = true
		set_share_enabled(_share_btn, false)
	else:
		_select(RANDOM if GameState.random_select else GameState.selected_character)


## The "?" pick is resolved at the last moment, so the player only
## discovers who they got once the run is already starting. _select() has
## already persisted the pick, so GameState holds the same truth as _selected.
func _start_fight() -> void:
	# Before the scene change, so the yell is already in flight as the venue
	# loads. It rides its own player and outlives this screen.
	GameState.play_scream()
	GameState.start_new_game(GameState.fight_character_index())


## CLASSIC is this screen's one primary action, so it wears the shared
## neon-purple fill. It is the only filled button in the content column (BACK
## lives in the top-left corner in red), which is what makes it pop.
func _style_fight_button(b: Button) -> void:
	MenuBase.style_purple_button(b)


## Hand the highlighted comedian's link to the OS. Never reachable on the "?"
## card — there is no comedian to share until one is picked.
func _on_share() -> void:
	if _selected == RANDOM or _selected < 0 or _selected >= GameState.characters.size():
		return
	var cfg: Dictionary = GameState.characters[_selected]
	share_character(cfg, "Think you can do better? Fight as %s in %s!" % [
			String(cfg.get("CharacterName", "this comedian")), GameState.game_title()])


func _build_preview() -> Control:
	var panel := VBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	var stage := Control.new()
	stage.custom_minimum_size = PREVIEW_SIZE
	panel.add_child(stage)
	_dancer = Dancer.new()
	# Carrying whatever is equipped in settings — the weapon is the player's,
	# not the comedian's, so it rides along whoever is highlighted here. Set
	# before the first set_character, which is what builds it.
	_dancer.show_weapon = true
	_dancer.position = Vector2(PREVIEW_SIZE.x / 2.0, PREVIEW_SIZE.y - 6.0)
	_dancer.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	stage.add_child(_dancer)
	# The mystery mark shown instead of the dancer while "?" is picked —
	# Press Start 2P at this size IS the pixelated game question mark.
	_preview_question = Label.new()
	_preview_question.text = "?"
	_preview_question.visible = false
	_preview_question.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_question.add_theme_font_size_override("font_size", 96)
	_preview_question.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_preview_question.pivot_offset = PREVIEW_SIZE / 2.0
	stage.add_child(_preview_question)
	_preview_name = Label.new()
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_name.custom_minimum_size = Vector2(PREVIEW_SIZE.x, 0)
	_preview_name.add_theme_font_size_override("font_size", 16)
	_preview_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	panel.add_child(_preview_name)
	# SHARE stays with the comedian it shares — under the preview, not over
	# with the play buttons, which are about how to play rather than who.
	# Shrink-centred so the square target keeps its shape in the column.
	add_spacer(panel, 6)
	_share_btn = add_share_button(panel, _on_share)
	_share_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_share_toast(panel, PREVIEW_SIZE.x)
	return panel


## The right-hand column: the two ways to play, stacked. CLASSIC is the run
## this screen has always started; MINI GAMES leaves the roster behind
## entirely, so it wears the plain gray skin and never disables with an empty
## roster — there is nothing on that shelf that needs a comedian.
##
## Vertically centred against the grid: an HBoxContainer stretches its
## children to the row height, so the column's own CENTER alignment is what
## parks the pair beside the middle row of heads.
func _build_actions() -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", ACTION_GAP)
	_classic_btn = add_button(col, "CLASSIC", _start_fight)
	_classic_btn.custom_minimum_size = Vector2(ACTION_W, ACTION_H)
	_classic_btn.add_theme_font_size_override("font_size", ACTION_FONT)
	_style_fight_button(_classic_btn)
	_mini_btn = add_button(col, "MINI GAMES",
			func(): GameState.change_scene(GameState.SCENE_MINI_GAMES))
	_mini_btn.custom_minimum_size = Vector2(ACTION_W, ACTION_H)
	_mini_btn.add_theme_font_size_override("font_size", ACTION_FONT)
	MenuBase.style_gray_button(_mini_btn)
	return col


func _select(index: int) -> void:
	_selected = index
	# Persisted here, not on FIGHT!, so the pick survives quitting from the
	# roster. A no-op when it matches what's already saved.
	GameState.set_random_select(index == RANDOM)
	_dancer.visible = index != RANDOM
	_preview_question.visible = index == RANDOM
	if index == RANDOM:
		_pop_preview(_preview_question, Vector2.ONE)
		_preview_name.text = "???"
	else:
		GameState.set_selected_character(index)
		var cfg: Dictionary = GameState.characters[index]
		_dancer.set_character(cfg)
		_pop_preview(_dancer, Vector2.ONE * PREVIEW_SCALE)
		_preview_name.text = String(cfg.get("CharacterName", "?"))
	_classic_btn.disabled = false
	# Nothing to share on the "?" card: the comedian is not decided until the
	# run starts, so there is no link to hand out yet.
	set_share_enabled(_share_btn, index != RANDOM)
	_update_highlights()


## The freshly picked comedian (or the "?") pops in: born tiny, zooming
## up to full preview size with a little overshoot bounce at the end.
func _pop_preview(node: Node, full_scale: Vector2) -> void:
	if _zoom:
		_zoom.kill()
	node.set("scale", full_scale * ZOOM_START)
	_zoom = create_tween()
	_zoom.tween_property(node, "scale", full_scale, ZOOM_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_highlights() -> void:
	_detach_orbit()
	for card in _grid.get_children():
		if not card.has_meta("index"):
			continue  # blank filler frame, never selected or dimmed
		var on: bool = card.get_meta("index") == _selected
		card.modulate = Color(1, 1, 1) if on else Color(0.62, 0.62, 0.68)
		if on:
			if _orbit == null:
				_orbit = SelectionOrbit.new()
			card.get_child(0).add_child(_orbit)


## The orbit is parked (unparented) while its card is being rebuilt or the
## selection lives on another page, so page turns never free it.
func _detach_orbit() -> void:
	if _orbit and _orbit.get_parent():
		_orbit.get_parent().remove_child(_orbit)


func _exit_tree() -> void:
	if _orbit and not _orbit.is_inside_tree():
		_orbit.free()


## Grid entries = the "?" card + every playable comedian (0 when nobody is
## playable, so an empty — or fully disabled — roster keeps its plain error
## screen). Entry e > 0 maps to roster index GameState.playable[e - 1]; cards
## carry that roster index, never their grid position.
func _entry_count() -> int:
	return 0 if GameState.playable.is_empty() else GameState.playable.size() + 1


func _page_count() -> int:
	return maxi(ceili(_entry_count() / float(PAGE_SIZE)), 1)


func _turn_page(dir: int) -> void:
	_page = wrapi(_page + dir, 0, _page_count())
	_fill_page()


func _fill_page() -> void:
	_detach_orbit()
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var start := _page * PAGE_SIZE
	for e in range(start, mini(start + PAGE_SIZE, _entry_count())):
		if e == 0:
			_grid.add_child(_random_card())
		else:
			var ri: int = GameState.playable[e - 1]
			_grid.add_child(_character_card(ri, GameState.characters[ri]))
	# Pad a short (only ever the last) page with blank frames so the 3x3
	# grid never changes shape.
	if _entry_count() > 0:
		while _grid.get_child_count() < PAGE_SIZE:
			_grid.add_child(_empty_card())
	if _pager:
		_pager.text = "PAGE %d / %d" % [_page + 1, _page_count()]
	_update_highlights()


## The caption under a head. Capped to NAME_W and two lines (see that
## constant): the cell's width is the grid's width, so an uncapped name is
## what used to stretch a column and shove the outer columns into the pagers.
func _style_name(l: Label) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = 2
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size = Vector2(NAME_W, NAME_H)
	l.add_theme_font_size_override("font_size", NAME_FONT)


## The "?" card heading the roster: a big pixel-font question mark where
## a head would be. Selecting it defers the pick to _start_fight().
func _random_card() -> VBoxContainer:
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", CARD_SEP)
	card.set_meta("index", RANDOM)
	var btn := Button.new()
	btn.flat = true
	btn.text = "?"
	btn.custom_minimum_size = Vector2(CELL, CELL)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 40)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, Color(1.0, 0.85, 0.4))
	btn.pressed.connect(guard_tap(func():
		GameState.play_sfx("click")
		_select(RANDOM)))
	card.add_child(btn)
	var name_label := Label.new()
	name_label.text = "RANDOM"
	_style_name(name_label)
	card.add_child(name_label)
	return card


## A blank placeholder frame (no meta, not clickable) keeping short pages
## on the same 3x3 grid as full ones.
func _empty_card() -> VBoxContainer:
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", CARD_SEP)
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(CELL, CELL)
	# Wide columns (long neighbor names) must not stretch the frame into a
	# rectangle — hold it at 64x64, centered in the cell.
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.45, 0.45, 0.52, 0.35)
	frame.add_theme_stylebox_override("panel", sb)
	card.add_child(frame)
	var pad := Label.new()
	pad.text = " "  # same metrics as a name label, so rows stay aligned
	_style_name(pad)
	card.add_child(pad)
	return card


func _character_card(index: int, cfg: Dictionary) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", CARD_SEP)
	card.set_meta("index", index)
	var btn := TextureButton.new()
	btn.texture_normal = CharacterFactory.head_texture(String(cfg.get("HeadSpritePath", "")))
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = Vector2(CELL, CELL)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(guard_tap(func():
		GameState.play_sfx("click")
		_select(index)))
	card.add_child(btn)
	var name_label := Label.new()
	name_label.text = String(cfg.get("CharacterName", "?"))
	_style_name(name_label)
	card.add_child(name_label)
	return card
