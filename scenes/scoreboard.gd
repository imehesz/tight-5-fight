extends MenuBase
## Leaderboard, three tabs:
##   LOCAL  — this device's high scores (user://<game>_highscores.json).
##   GLOBAL — two boards side by side (server/server.js; see
##            autoload/leaderboard.gd): TOP SCORE shows the highest score
##            ever posted with each character, MOST BEAT UP counts how many
##            times each was KO'd as an enemy. One pager drives both panels.
##   VENUES — one board: which venue doors players walk through the most,
##            counted per run alongside the KO tally.
##   JOKE BOOK — this player's daily attendance: a 3x3 grid of the last 90
##            days, newest first, each day a check or a cross. Gated behind
##            Leaderboard.JOKE_BOOK_ENABLED; the tab is not built at all when
##            the feature is off.
## The first three tabs are paged 10 rows at a time; JOKE BOOK pages 9 cells
## at a time. LOCAL is shown first and never needs the network, so the screen
## is useful even with the server down.

enum Tab { LOCAL, GLOBAL, VENUES, JOKE_BOOK }

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

## JOKE BOOK grid: 3x3 cells a page, 10 pages, 90 days — which must match
## jokeBook.windowDays in server/config.js. The server sends exactly that many
## day entries newest-first, so the client never does date arithmetic; it
## slices the array it was handed.
const JOKE_COLS := 3
const JOKE_ROWS := 3
const JOKE_PER_PAGE := JOKE_COLS * JOKE_ROWS
const JOKE_PAGES := 10
## Each day is the same bordered square the CHARACTERS grid pads its short
## pages with (character_select.gd _empty_card), holding the date and the mark
## together. 58 rather than that grid's 64: three of those plus the streak
## line do not fit the fixed well this screen shares with the GLOBAL tab
## (14 + 10*18 = 194px tall), and the well is what stops the layout jumping
## when you switch tabs.
const JOKE_CELL := 56
const JOKE_CELL_INSET := 2
## Breathing room between the STREAK line and the grid. Paid for by the two
## pixels off JOKE_CELL above — the well is a fixed 194px and the grid was
## already using most of it.
const JOKE_HEAD_GAP := 8
## Press Start 2P has NO check or cross glyph (verified against the font's
## cmap — U+2713/U+2717 are absent), so drawing them as text would render two
## tofu boxes. They are stroked in _draw() instead, which also lets them be
## as big as the square allows without a second font.
const JOKE_YES := Color(0.45, 0.9, 0.5)
const JOKE_NO := Color(0.95, 0.38, 0.38)
## Frame styling lifted from character_select.gd's blank card, so a JOKE BOOK
## square and a CHARACTERS filler square are visibly the same object.
const JOKE_FRAME_BG := Color(1, 1, 1, 0.04)
const JOKE_FRAME_EDGE := Color(0.45, 0.45, 0.52, 0.35)
const MONTHS := ["Jan.", "Feb.", "Mar.", "Apr.", "May", "Jun.",
		"Jul.", "Aug.", "Sep.", "Oct.", "Nov.", "Dec."]

const TAB_ON := Color(1.0, 0.85, 0.4)
const TAB_OFF := Color(0.6, 0.6, 0.68)
const TEXT := Color(0.85, 0.85, 0.9)
const DIM := Color(0.6, 0.6, 0.68)
const YOU := Color(1.0, 0.85, 0.4)

var _tab := Tab.LOCAL
var _local_page := 0
var _global_page := 0
var _venues_page := 0
var _joke_page := 0
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
	if Leaderboard.JOKE_BOOK_ENABLED:
		Leaderboard.jokebook_loaded.connect(_on_jokebook_loaded)
		Leaderboard.jokebook_failed.connect(_on_jokebook_failed)

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
	# Four tabs no longer fit at the three-tab width on a 640-wide design view,
	# so they share the row out instead of each keeping 130px.
	if Leaderboard.JOKE_BOOK_ENABLED:
		tabs.add_child(_tab_button(Tab.JOKE_BOOK, "JOKE BOOK"))
		tabs.add_theme_constant_override("separation", 6)
		for b in _tab_buttons.values():
			b.custom_minimum_size = Vector2(96, 28)
			b.add_theme_font_size_override("font_size", 8)
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
	if _tab == Tab.JOKE_BOOK:
		# Fixed: the window is always the full 90 days, present or not.
		return JOKE_PAGES
	return maxi(ceili(GameState.high_scores.size() / float(ROWS_PER_PAGE)), 1)


func _page() -> int:
	match _tab:
		Tab.GLOBAL:
			return _global_page
		Tab.VENUES:
			return _venues_page
		Tab.JOKE_BOOK:
			return _joke_page
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
		Tab.JOKE_BOOK:
			_joke_page = next
			_render_jokebook()
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
		Tab.JOKE_BOOK:
			_render_jokebook()
		_:
			_render_local()


# ---------------------------------------------------------------- joke book
## One day's tick or cross, stroked rather than typed — see JOKE_MARK_H.
class DayMark:
	extends Control
	var played := false
	var yes: Color
	var no: Color

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := (w * 0.5)
		var r := minf(w, h) * 0.34
		var width := maxf(r * 0.26, 2.0)
		if played:
			# Tick: short down-stroke into a long up-stroke, drawn as two
			# joined segments so the elbow stays sharp at any size.
			var a := Vector2(c - r, h * 0.5)
			var b := Vector2(c - r * 0.25, h * 0.5 + r * 0.72)
			var d := Vector2(c + r, h * 0.5 - r * 0.72)
			draw_line(a, b, yes, width, true)
			draw_line(b, d, yes, width, true)
		else:
			var m := h * 0.5
			draw_line(Vector2(c - r, m - r), Vector2(c + r, m + r), no, width, true)
			draw_line(Vector2(c + r, m - r), Vector2(c - r, m + r), no, width, true)


## "2026-08-17" -> "Aug. 17." Falls back to the raw string on anything
## unexpected, so a server that changes shape shows an odd label rather than
## an empty grid.
func _pretty_day(day: String) -> String:
	var parts := day.split("-")
	if parts.size() != 3:
		return day
	var m := int(parts[1])
	if m < 1 or m > 12:
		return day
	return "%s %d." % [MONTHS[m - 1], int(parts[2])]


func _on_jokebook_loaded(_data: Dictionary) -> void:
	if _tab == Tab.JOKE_BOOK:
		_render_jokebook()


func _on_jokebook_failed(reason: String) -> void:
	if _tab == Tab.JOKE_BOOK:
		_message("JOKE BOOK UNAVAILABLE\n(%s)" % reason.to_upper())
		_update_pager()


## The 3x3 grid for the current page. Reads the cached payload rather than
## fetching: Leaderboard pings on boot, so by the time anyone opens this the
## answer is usually already here — and if it isn't, the ping's signal
## re-renders us.
func _render_jokebook() -> void:
	_clear_rows()
	_update_pager()
	var book: Dictionary = Leaderboard.jokebook()
	if book.is_empty():
		_message("CHECKING IN ...")
		return
	var days: Array = book.get("days", [])
	if days.is_empty():
		_message("NO DAYS RECORDED YET")
		return

	# Streak summary: the whole reason the grid exists, so it says plainly what
	# the attendance is currently worth.
	var streak := int(book.get("streak", 0))
	var head := Label.new()
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 8)
	head.add_theme_color_override("font_color", YOU if streak > 1 else DIM)
	head.text = "STREAK %d DAY%s" % [streak, "" if streak == 1 else "S"]
	_rows.add_child(head)
	add_spacer(_rows, JOKE_HEAD_GAP)

	var grid := GridContainer.new()
	grid.columns = JOKE_COLS
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 2)
	# Shrink-centred, not expand-fill: the squares are a fixed size now, so
	# spreading them over the full two-panel width would strand them at the
	# edges of a mostly empty well.
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rows.add_child(grid)

	var start := _joke_page * JOKE_PER_PAGE
	for i in JOKE_PER_PAGE:
		var idx := start + i
		# A short last page can't happen at 90/9, but pad anyway rather than
		# let the grid reflow if windowDays is ever retuned server-side.
		if idx >= days.size():
			var pad := Control.new()
			pad.custom_minimum_size = Vector2(JOKE_CELL, JOKE_CELL)
			grid.add_child(pad)
			continue
		var entry: Dictionary = days[idx]
		grid.add_child(_joke_cell(String(entry.get("day", "")),
				bool(entry.get("played", false)), idx == 0))


## One day, as the same bordered square the CHARACTERS grid uses for its
## blank filler cards — date across the top, mark filling the rest. `is_today`
## golds the frame and the date so the grid always says plainly where now is.
func _joke_cell(day: String, played: bool, is_today: bool) -> Panel:
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(JOKE_CELL, JOKE_CELL)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = JOKE_FRAME_BG
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(2)
	sb.border_color = YOU if is_today else JOKE_FRAME_EDGE
	frame.add_theme_stylebox_override("panel", sb)

	# anchors AND offsets: anchors alone leave the box at its own size in the
	# corner, which is the classic way a full-rect child silently doesn't fill.
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	col.offset_left = JOKE_CELL_INSET
	col.offset_top = JOKE_CELL_INSET - 1
	col.offset_right = -JOKE_CELL_INSET
	col.offset_bottom = -JOKE_CELL_INSET
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(col)

	# Font 6, not the 8 used elsewhere: "Sep. 30." is 8 glyphs and Press Start
	# 2P is a wide monospace at ~1em each, so 8 would run the full 52px of
	# usable width and touch both borders.
	var date := Label.new()
	date.text = _pretty_day(day)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	date.add_theme_font_size_override("font_size", 6)
	date.add_theme_color_override("font_color", YOU if is_today else TEXT)
	col.add_child(date)

	var mark := DayMark.new()
	mark.played = played
	mark.yes = JOKE_YES
	mark.no = JOKE_NO
	mark.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(mark)
	return frame


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
