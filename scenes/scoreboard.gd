extends MenuBase
## Leaderboard, three tabs:
##   LOCAL  — this device's high scores (user://<game>_highscores.json).
##   GLOBAL — two boards side by side (server/server.js; see
##            autoload/leaderboard.gd): TOP SCORE shows the highest score
##            ever posted with each character, MOST BEAT UP counts how many
##            times each was KO'd as an enemy. One pager drives both panels.
##   VENUES — one board: which venue doors players walk through the most,
##            counted per run alongside the KO tally.
## All tabs are paged 10 rows at a time. LOCAL is shown first and never
## needs the network, so the screen is useful even with the server down.

enum Tab { LOCAL, GLOBAL, VENUES }

## Must match Leaderboard.PAGE_SIZE (and pageSize in server/config.js). Not
## `= Leaderboard.PAGE_SIZE`: an autoload lookup isn't a constant expression.
const ROWS_PER_PAGE := 10
const ROW_HEIGHT := 14
const ROW_FONT := 9

## The global tab packs two half-width boards side by side, so its rows keep
## the normal rank font and a small head. Ten rows plus the panel headers
## still have to fit above the pager in a 360px-tall viewport (aspect="expand"
## widens on phones, never heightens), so the chrome around the row well
## below is deliberately tight.
const HEAD_SIZE := 18
const GLOBAL_ROW_HEIGHT := 18    # the head is the tallest thing in the row
## Each panel's row is | rank 28 | count 46 | head | name 162 | with 6px
## separations — exactly PANEL_W. Press Start 2P is a wide monospace, ~1em
## per glyph at ROW_FONT, so 46px comfortably fits a 5-digit KO count.
const PANEL_W := 272
const PANEL_GAP := 8
const PANEL_HEADER_H := 14

const TAB_ON := Color(1.0, 0.85, 0.4)
const TAB_OFF := Color(0.6, 0.6, 0.68)
const TEXT := Color(0.85, 0.85, 0.9)
const DIM := Color(0.6, 0.6, 0.68)
const YOU := Color(1.0, 0.85, 0.4)

var _tab := Tab.LOCAL
var _local_page := 0
var _global_page := 0
var _venues_page := 0
## Page counts reported by the server; 1 until the first response lands.
var _global_pages := 1
var _venues_pages := 1
## Rebuilt on every render, so a row can be dropped in mid-flight.
var _rows: VBoxContainer
var _pager: Label
var _prev_btn: Button
var _next_btn: Button
var _tab_buttons := {}
## Name -> head sprite path, from the local roster. The server only sends
## character names; the heads already ship in the build, so no image ever
## crosses the wire (and a name we no longer ship just gets a placeholder).
var _heads := {}


func _ready() -> void:
	for c in GameState.characters:
		_heads[String(c.get("CharacterName", ""))] = String(c.get("HeadSpritePath", ""))

	Leaderboard.board_loaded.connect(_on_board_loaded)
	Leaderboard.board_failed.connect(_on_board_failed)
	Leaderboard.venues_loaded.connect(_on_venues_loaded)
	Leaderboard.venues_failed.connect(_on_venues_failed)

	var box := build_backdrop()
	# Ten tall global rows leave little room to spare, so this screen packs its
	# column tighter than MenuBase's default 8px gaps.
	box.add_theme_constant_override("separation", 2)
	add_title(box, "LEADERBOARD", 14)
	add_spacer(box, 2)
	box.add_child(_build_tabs())
	add_spacer(box, 2)

	# Fixed-height well: rows come and go, but the column around them must not
	# jump around as pages fill up or the network is still thinking. Sized for
	# the global tab (two panels wide, header + rows tall), so switching tabs
	# doesn't move anything either. (The pager and BACK are pinned to the
	# screen now, so they were never going to move — the tabs above still are.)
	var well := Control.new()
	well.custom_minimum_size = Vector2(PANEL_W * 2 + PANEL_GAP,
			PANEL_HEADER_H + ROWS_PER_PAGE * GLOBAL_ROW_HEIGHT)
	box.add_child(well)
	_rows = VBoxContainer.new()
	_rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rows.add_theme_constant_override("separation", 0)
	well.add_child(_rows)

	_pager = add_bottom_label()
	_prev_btn = add_edge_arrow("<", false, func(): _turn_page(-1))
	_next_btn = add_edge_arrow(">", true, func(): _turn_page(1))
	add_back_button(func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))

	# Arriving from game over, open straight to the page holding the new
	# entry — otherwise a top-50 board buries it and the run feels unrecorded.
	if GameState.last_run_rank >= 0:
		_local_page = GameState.last_run_rank / ROWS_PER_PAGE
	_show_tab(Tab.LOCAL)


# ---------------------------------------------------------------- chrome
func _build_tabs() -> HBoxContainer:
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	tabs.add_child(_tab_button(Tab.LOCAL, "LOCAL"))
	tabs.add_child(_tab_button(Tab.GLOBAL, "GLOBAL"))
	tabs.add_child(_tab_button(Tab.VENUES, "VENUES"))
	return tabs


func _tab_button(tab: Tab, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(130, 28)
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(func():
		GameState.play_sfx("click")
		_show_tab(tab))
	_tab_buttons[tab] = b
	return b


## Just the "PAGE x / y" label — the arrows are pinned to the screen edges in
## _ready() so they never move with the table between them.
## The active tab is gold and bright; the other is dimmed on every axis a
## Button paints text with, so hovering the inactive one doesn't fake it.
func _style_tabs() -> void:
	for tab in _tab_buttons:
		var on: bool = tab == _tab
		var b: Button = _tab_buttons[tab]
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(state, TAB_ON if on else TAB_OFF)
		b.modulate = Color(1, 1, 1) if on else Color(0.72, 0.72, 0.78)


# ---------------------------------------------------------------- paging
func _page_count() -> int:
	if _tab == Tab.GLOBAL:
		return maxi(_global_pages, 1)
	if _tab == Tab.VENUES:
		return maxi(_venues_pages, 1)
	return maxi(ceili(GameState.high_scores.size() / float(ROWS_PER_PAGE)), 1)


func _page() -> int:
	match _tab:
		Tab.GLOBAL:
			return _global_page
		Tab.VENUES:
			return _venues_page
		_:
			return _local_page


func _turn_page(dir: int) -> void:
	var next := wrapi(_page() + dir, 0, _page_count())
	match _tab:
		Tab.GLOBAL:
			_global_page = next
			_load_global()
		Tab.VENUES:
			_venues_page = next
			_load_venues()
		_:
			_local_page = next
			_render_local()


func _update_pager() -> void:
	var pages := _page_count()
	_pager.text = "PAGE %d / %d" % [_page() + 1, pages]
	_prev_btn.disabled = pages <= 1
	_next_btn.disabled = pages <= 1


func _show_tab(tab: Tab) -> void:
	_tab = tab
	_style_tabs()
	match tab:
		Tab.GLOBAL:
			_load_global()
		Tab.VENUES:
			_load_venues()
		_:
			_render_local()


func _clear_rows() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()


## Centered one-liner for empty / loading / offline states.
func _message(text: String, color := DIM) -> void:
	_clear_rows()
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", ROW_FONT)
	l.add_theme_color_override("font_color", color)
	_rows.add_child(l)


func _cell(text: String, width: int, align: int, color := TEXT, height := ROW_HEIGHT, font := ROW_FONT) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, height)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_color", color)
	return l


# ---------------------------------------------------------------- local tab
func _render_local() -> void:
	_local_page = clampi(_local_page, 0, _page_count() - 1)
	_update_pager()
	if GameState.high_scores.is_empty():
		_message("No scores yet. Go bomb somewhere!")
		return
	_clear_rows()
	var start := _local_page * ROWS_PER_PAGE
	for i in range(start, mini(start + ROWS_PER_PAGE, GameState.high_scores.size())):
		var entry: Dictionary = GameState.high_scores[i]
		var color := YOU if i == GameState.last_run_rank else TEXT
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		row.add_child(_cell("%d." % (i + 1), 30, HORIZONTAL_ALIGNMENT_RIGHT, color))
		row.add_child(_cell("%d" % int(entry.get("score", 0)), 60, HORIZONTAL_ALIGNMENT_RIGHT, color))
		row.add_child(_cell("V%d" % int(entry.get("venue", 0)), 34, HORIZONTAL_ALIGNMENT_CENTER, color))
		row.add_child(_cell(String(entry.get("character", "?")), 170, HORIZONTAL_ALIGNMENT_LEFT, color))
		row.add_child(_cell(String(entry.get("date", "")), 90, HORIZONTAL_ALIGNMENT_RIGHT, DIM))
		_rows.add_child(row)


# ---------------------------------------------------------------- global tab
func _load_global() -> void:
	_update_pager()
	_message("Loading…")
	Leaderboard.fetch_board(_global_page)


## Late responses are common here: tap GLOBAL, tap LOCAL, the first request
## lands. The payload carries the page it answers, so anything that no longer
## matches what's on screen is dropped.
func _on_board_loaded(data: Dictionary) -> void:
	if _tab != Tab.GLOBAL:
		return
	_global_pages = maxi(int(data.get("pageCount", 1)), 1)
	# The server clamps out-of-range pages; follow it rather than argue.
	_global_page = clampi(int(data.get("page", _global_page)), 0, _global_pages - 1)
	_update_pager()

	var rows: Array = data.get("rows", [])
	var beat_rows: Array = data.get("beatRows", [])
	if rows.is_empty() and beat_rows.is_empty():
		_message("No plays recorded yet.")
		return
	_clear_rows()
	var split := HBoxContainer.new()
	split.alignment = BoxContainer.ALIGNMENT_CENTER
	split.add_theme_constant_override("separation", PANEL_GAP)
	split.add_child(_board_panel("TOP SCORE", rows, "best"))
	split.add_child(_board_panel("MOST BEAT UP", beat_rows, "kos"))
	_rows.add_child(split)


func _on_board_failed(reason: String) -> void:
	if _tab != Tab.GLOBAL:
		return
	_message("Global leaderboard unavailable.\n(%s)" % reason)


# ---------------------------------------------------------------- venues tab
func _load_venues() -> void:
	_update_pager()
	_message("Loading…")
	Leaderboard.fetch_venues(_venues_page)


## Same late-response discipline as the global tab: anything answering a tab
## that is no longer on screen is dropped.
func _on_venues_loaded(data: Dictionary) -> void:
	if _tab != Tab.VENUES:
		return
	_venues_pages = maxi(int(data.get("pageCount", 1)), 1)
	_venues_page = clampi(int(data.get("page", _venues_page)), 0, _venues_pages - 1)
	_update_pager()

	var rows: Array = data.get("rows", [])
	if rows.is_empty():
		_message("No venues entered yet.")
		return
	_clear_rows()
	var panel := VBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 0)
	panel.add_child(_cell("MOST BATTLED", PANEL_W, HORIZONTAL_ALIGNMENT_CENTER,
		TAB_ON, PANEL_HEADER_H, 8))
	for r in rows:
		panel.add_child(_venue_row(r))
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(panel)
	_rows.add_child(center)


func _on_venues_failed(reason: String) -> void:
	if _tab != Tab.VENUES:
		return
	_message("Venue leaderboard unavailable.\n(%s)" % reason)


## | rank | count | venue name | — one centered panel, no head sprite (venue
## art is a whole building; at row height it would be an unreadable smudge).
func _venue_row(r: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_cell("%d." % int(r.get("rank", 0)), 28,
		HORIZONTAL_ALIGNMENT_RIGHT, TEXT, GLOBAL_ROW_HEIGHT))
	row.add_child(_cell("%d" % int(r.get("entries", 0)), 46,
		HORIZONTAL_ALIGNMENT_RIGHT, YOU, GLOBAL_ROW_HEIGHT))
	row.add_child(_cell(String(r.get("venue", "?")), 186,
		HORIZONTAL_ALIGNMENT_LEFT, TEXT, GLOBAL_ROW_HEIGHT))
	return row


## One half of the global tab: a small gold header over up to ROWS_PER_PAGE
## rows. count_key names the number the server row carries for this board
## ("best" or "kos"). A panel past the end of its own board (the pager spans
## the longer of the two) just says so.
func _board_panel(title: String, rows: Array, count_key: String) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.add_theme_constant_override("separation", 0)
	panel.add_child(_cell(title, PANEL_W, HORIZONTAL_ALIGNMENT_CENTER, TAB_ON, PANEL_HEADER_H, 8))
	if rows.is_empty():
		panel.add_child(_cell("Nothing yet.", PANEL_W, HORIZONTAL_ALIGNMENT_CENTER, DIM, GLOBAL_ROW_HEIGHT))
	for r in rows:
		panel.add_child(_panel_row(r, count_key))
	return panel


## | rank | count | head | name | — see PANEL_W for the width budget. Scores
## run bigger than KO counts, so the TOP SCORE panel trades name width for a
## wider number cell (both variants still sum to PANEL_W).
func _panel_row(r: Dictionary, count_key: String) -> HBoxContainer:
	var character := String(r.get("character", "?"))
	var count_w := 64 if count_key == "best" else 46
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_cell("%d." % int(r.get("rank", 0)), 28,
		HORIZONTAL_ALIGNMENT_RIGHT, TEXT, GLOBAL_ROW_HEIGHT))
	row.add_child(_cell("%d" % int(r.get(count_key, 0)), count_w,
		HORIZONTAL_ALIGNMENT_RIGHT, YOU, GLOBAL_ROW_HEIGHT))

	var head := TextureRect.new()
	head.texture = CharacterFactory.head_texture(String(_heads.get(character, "")))
	head.custom_minimum_size = Vector2(HEAD_SIZE, HEAD_SIZE)
	head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	head.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(head)

	row.add_child(_cell(character, 208 - count_w, HORIZONTAL_ALIGNMENT_LEFT, TEXT, GLOBAL_ROW_HEIGHT))
	return row
