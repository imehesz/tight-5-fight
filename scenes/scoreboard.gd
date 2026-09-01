extends MenuBase
## Leaderboard, five tabs:
##   LOCAL  — this device's high scores (user://<game>_highscores.json).
##   GLOBAL — two boards side by side (server/server.js; see
##            autoload/leaderboard.gd): TOP SCORE shows the highest score
##            ever posted with each character, MOST BEAT UP counts how many
##            times each was KO'd as an enemy. One pager drives both panels.
##   VENUES — one board: which venue doors players walk through the most,
##            counted per run alongside the KO tally.
##   BEEF   — the BEEF METER: who has been beating up whom. Reads the same
##            beatdown rows as MOST BEAT UP from the other end — the left
##            panel ranks comedians by KOs LANDED (i.e. landed by players
##            playing AS them), the right panel opens the selected one's
##            grudge list. See requirements/beef-meter-implementation.md.
##   JOKE BOOK — this player's daily attendance: a 3x3 grid of the last 90
##            days, newest first, each day a check or a cross. Gated behind
##            Leaderboard.JOKE_BOOK_ENABLED; the tab is not built at all when
##            the feature is off.
## LOCAL/GLOBAL/VENUES page 10 rows at a time; BEEF pages 6, because its rows
## are tap targets and have to stay thumb-sized; JOKE BOOK pages its 9 cells.
## LOCAL is shown first and never needs the network, so the screen is useful
## even with the server down.

enum Tab { LOCAL, GLOBAL, VENUES, BEEF, JOKE_BOOK }


## One row's beef bar: a chunky segmented meter that ramps from the menus' gold
## to the BACK button's red as the grudge gets worse, so a long bar reads as
## "hot" at a glance and not just "wide". Drawn rather than imported — no new
## art asset, and nothing to fight the pixel filtering over.
class BeefBar extends Control:
	## Ten blocks, not sixteen: at half the old bar width, sixteen segments came
	## out under 3px each and read as mush rather than as a chunky meter.
	const SEGMENTS := 10
	const TRACK := Color(0.13, 0.12, 0.18)
	const EDGE := Color(0.30, 0.28, 0.38)
	const COOL := Color(0.95, 0.78, 0.35)
	const HOT := Color(0.92, 0.26, 0.22)

	## 0..1, this victim's KOs against the worst beef on the board.
	var ratio := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), TRACK, true)
		draw_rect(Rect2(Vector2.ZERO, size), EDGE, false, 1.0)
		# ceil, so any nonzero grudge lights at least one block — a victim with
		# a real KO must never render as an empty bar.
		var lit := ceili(clampf(ratio, 0.0, 1.0) * SEGMENTS)
		var seg_w := (size.x - 4.0) / SEGMENTS
		for i in lit:
			# Coloured by the segment's own position, not the bar's length, so
			# the ramp sits at the same place on every row and a short bar just
			# stops before the hot end.
			var c := COOL.lerp(HOT, float(i) / float(SEGMENTS - 1))
			draw_rect(Rect2(2.0 + i * seg_w, 2.0, seg_w - 1.0, size.y - 4.0), c, true)

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

## BEEF tab geometry. The two panels share the same well as the GLOBAL tab
## (PANEL_W * 2 + PANEL_GAP wide), split unevenly: a narrow tappable list on
## the left, the detail on the right.
##
## Six rows, not ten: every left row is a BUTTON, and a 10-row list would put
## them at 18px, which is a coin-flip tap on a phone. At 30px they land near
## 65 real pixels on a 720p-tall handset. 14 + 6 * 30 fills the 194px well
## exactly, so switching to this tab still moves nothing above it.
const BEEF_ROWS_PER_PAGE := 6   # must match BEEF_PAGE_SIZE in server/server.js
const BEEF_ROW_HEIGHT := 30
const BEEF_LEFT_W := 220
const BEEF_RIGHT_W := PANEL_W * 2 - BEEF_LEFT_W
## | head 24 | name 176 | with a 4px separation, inside BEEF_ROW_PAD either
## side. The list carries no rank number and no KO count: it is already in rank
## order, and the selected comedian's total is right there on the other panel
## as KOs LANDED — so both columns were just noise, and their width buys the
## names real padding instead.
const BEEF_LIST_HEAD := 24
const BEEF_ROW_PAD := 8
## Both panels' titles — BEEFCAKES and the selected comedian's name — are set
## at one size, so the two halves read as a matched pair rather than a heading
## over a caption. "MOST BEEF WITH" deliberately stays smaller: it labels a
## section INSIDE the right panel, not the panel itself.
##
## Only the font is shared, not the height: the left title stays at
## PANEL_HEADER_H because 14 + 6 * BEEF_ROW_HEIGHT is exactly the 194px well.
const BEEF_TITLE_FONT := 10
## | head 18 | name 188 | bar 66 | kos 40 | with 4px separations — exactly
## BEEF_RIGHT_W. Not tap targets, so these rows stay compact. No rank number:
## a top-five list ordered by a number already printed on every row doesn't
## need one, and the width buys the names room at the larger top-row fonts.
const BEEF_VICTIM_ROW_H := 18
const BEEF_VICTIM_HEAD := 18
const BEEF_BAR_W := 66
## The meter keeps ONE height down the whole list, even where the type grows:
## the bars are read against each other, and a taller bar on top would imply a
## difference in kind on top of the length difference already saying it.
const BEEF_BAR_H := 12
const BEEF_PORTRAIT := 56

const DEALT := Color(0.55, 1.0, 0.7)
const TAKEN := Color(1.0, 0.5, 0.45)
const ROW_EDGE := Color(0.30, 0.28, 0.38)
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

## JOKE CRAFTER — the pane sharing this tab with the grid above. The well is a
## fixed 552 wide; the grid takes 3 * JOKE_CELL + 2 * JOKE_GRID_SEP = 192, so
## the crafter gets what is left after the gap. It re-flows the portrait mockup
## into landscape because the well cannot grow: making it taller would move
## everything above it every time the tab changes.
const JOKE_GRID_SEP := 10
const CRAFT_GAP := 8
const CRAFT_W := PANEL_W * 2 - (JOKE_CELL * JOKE_COLS + JOKE_GRID_SEP * 2) - CRAFT_GAP
## One row per component: | icon | name | owned | ADD | slot |. Widths sum to
## 282, comfortably inside CRAFT_W, so the row never has to shrink a label.
const CRAFT_ROW_H := 30
const CRAFT_ICON := 20
const CRAFT_NAME_W := 110
const CRAFT_OWNED_W := 42
const CRAFT_ADD_W := 66
const CRAFT_SLOT_W := 44
## Digit widths, zero-padded. Four for what you own, three for what is loaded —
## and these are real caps, matching maxInventory / maxCraft in
## server/config.js, so the display can never be overrun by a number.
const CRAFT_OWNED_DIGITS := 4
const CRAFT_SLOT_DIGITS := 3
## Hard ceiling on one batch, matching maxCraft in server/config.js and the
## three digits the slot can show.
const CRAFT_SLOT_MAX := 999
## Per-kind tint, matching ComponentPickup.TINTS so a TAG is the same green in
## the panel as it is lying on the street.
const CRAFT_TINTS := {
	"setups": Color(1.0, 0.92, 0.62),
	"punchlines": Color(0.62, 0.90, 1.15),
	"tags": Color(0.72, 1.12, 0.80),
}
const CRAFT_LABELS := {
	"setups": "SETUPS", "punchlines": "PUNCHLINES", "tags": "TAGS",
}
const CRAFT_FILES := {
	"setups": "setup", "punchlines": "punchline", "tags": "tag",
}

const TAB_ON := Color(1.0, 0.85, 0.4)
const TAB_OFF := Color(0.6, 0.6, 0.68)
const TEXT := Color(0.85, 0.85, 0.9)
const DIM := Color(0.6, 0.6, 0.68)
const YOU := Color(1.0, 0.85, 0.4)

var _tab := Tab.LOCAL
var _local_page := 0
var _global_page := 0
var _venues_page := 0
var _beef_page := 0
var _joke_page := 0
## Components loaded into the crafter's slots but not yet crafted. Purely
## local: the server is not told until GENERATE, so backing out of the tab
## simply returns them (nothing ever left the player's inventory).
var _slots := {"setups": 0, "punchlines": 0, "tags": 0}
## Rebuilt every render, like _rows — the panel redraws wholesale whenever the
## crafter state changes, so nothing here is kept across a rebuild.
var _slot_labels := {}
var _owned_labels := {}
var _add_buttons := {}
var _craft_btn: Button
var _points_label: Label
var _craft_status: Label
## Page counts reported by the server; 1 until the first response lands.
var _global_pages := 1
var _venues_pages := 1
var _beef_pages := 1
## Which comedian the BEEF tab's right panel is showing. "" asks the server to
## pick the top of the current page, which is what a fresh tab and every page
## turn send.
var _beef_attacker := ""
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
	Leaderboard.beef_loaded.connect(_on_beef_loaded)
	Leaderboard.beef_failed.connect(_on_beef_failed)
	if Leaderboard.JOKE_BOOK_ENABLED:
		Leaderboard.jokebook_loaded.connect(_on_jokebook_loaded)
		Leaderboard.jokebook_failed.connect(_on_jokebook_failed)
		Leaderboard.crafter_loaded.connect(_on_crafter_loaded)
		Leaderboard.crafter_failed.connect(_on_crafter_failed)

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
## Four tabs at 112px with 8px gaps span 472 — comfortably clear of the edge
## arrows at either end of a 640-wide viewport. (Three at the old 130 spanned
## 410; a fourth at that width would have crowded them.) The fifth tab only
## exists when JOKE BOOK is on, and pays for itself by shrinking the row —
## see below.
func _build_tabs() -> HBoxContainer:
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	tabs.add_child(_tab_button(Tab.LOCAL, "LOCAL"))
	tabs.add_child(_tab_button(Tab.GLOBAL, "GLOBAL"))
	tabs.add_child(_tab_button(Tab.VENUES, "VENUES"))
	tabs.add_child(_tab_button(Tab.BEEF, "BEEF"))
	# Five tabs no longer fit at the four-tab width on a 640-wide design view,
	# so they share the row out instead of each keeping 112px. 5 * 88 + 4 * 6
	# spans 464, still clear of the edge arrows (45 + 10 margin) either side.
	if Leaderboard.JOKE_BOOK_ENABLED:
		tabs.add_child(_tab_button(Tab.JOKE_BOOK, "JOKE BOOK"))
		tabs.add_theme_constant_override("separation", 6)
		for b in _tab_buttons.values():
			b.custom_minimum_size = Vector2(88, 28)
			b.add_theme_font_size_override("font_size", 8)
	return tabs


func _tab_button(tab: Tab, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(112, 28)
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(guard_tap(func():
		GameState.play_sfx("click")
		_show_tab(tab)))
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
	if _tab == Tab.BEEF:
		return maxi(_beef_pages, 1)
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
		Tab.BEEF:
			return _beef_page
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
		Tab.BEEF:
			_beef_page = next
			# Drop the selection so the server opens the new page's top
			# comedian. Carrying it over would leave the right panel showing
			# someone who isn't even in the list any more, which reads as a
			# pager that only moved half the screen.
			_beef_attacker = ""
			_load_beef()
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
		Tab.BEEF:
			_load_beef()
		Tab.JOKE_BOOK:
			# Ask for the crafter state every time the tab opens: a run may
			# have banked components since it was last seen, and the reply
			# repaints the pane in place when it lands.
			if Leaderboard.JOKE_BOOK_ENABLED:
				Leaderboard.fetch_crafter()
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

	# The tab is two panes side by side: the attendance grid on the left, the
	# JOKE CRAFTER on the right. An HBox rather than two anchored Controls so
	# the pair stays centred in the well whatever the crafter is showing.
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", CRAFT_GAP)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(split)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	split.add_child(left)

	# Streak summary: the whole reason the grid exists, so it says plainly what
	# the attendance is currently worth.
	var streak := int(book.get("streak", 0))
	var head := Label.new()
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 8)
	head.add_theme_color_override("font_color", YOU if streak > 1 else DIM)
	head.text = "STREAK %d DAY%s" % [streak, "" if streak == 1 else "S"]
	left.add_child(head)
	add_spacer(left, JOKE_HEAD_GAP)

	var grid := GridContainer.new()
	grid.columns = JOKE_COLS
	grid.add_theme_constant_override("h_separation", JOKE_GRID_SEP)
	grid.add_theme_constant_override("v_separation", 2)
	# Shrink-centred, not expand-fill: the squares are a fixed size now, so
	# spreading them over the full two-panel width would strand them at the
	# edges of a mostly empty well.
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(grid)
	split.add_child(_build_crafter())

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


# ---------------------------------------------------------------- crafter
## How many of `kind` are still free to load — what the server says the player
## owns, minus what is already sitting in a slot. Slots are local, so nothing
## has actually left the inventory until GENERATE is pressed.
func _available(kind: String) -> int:
	return maxi(Leaderboard.components(kind) - int(_slots.get(kind, 0)), 0)


## Whether ADD may load one more of `kind`.
##
## The cap is the smaller of what the OTHER two kinds total (slot plus
## inventory), because a joke needs one of each: loading a seventh punchline
## when only four tags exist in the world can never become a craft, and with no
## way to take one back out it would strand the panel for good. Since slot plus
## available always equals the owned total, that reduces to the owned totals of
## the other two.
func _can_add(kind: String) -> bool:
	if _available(kind) <= 0:
		return false
	if int(_slots.get(kind, 0)) >= CRAFT_SLOT_MAX:
		return false
	var cap := 0x7FFFFFFF
	for other in GameState.COMPONENT_KINDS:
		if other != kind:
			cap = mini(cap, Leaderboard.components(other))
	return int(_slots.get(kind, 0)) < cap


## The batch the loaded slots represent: the shared count when all three match,
## 0 otherwise. GENERATE is lit on exactly this being non-zero.
func _batch() -> int:
	var n := int(_slots.get("setups", 0))
	if n <= 0:
		return 0
	for k in GameState.COMPONENT_KINDS:
		if int(_slots.get(k, 0)) != n:
			return 0
	return n


func _build_crafter() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(CRAFT_W, 0)
	col.add_theme_constant_override("separation", 2)

	var title := Label.new()
	title.text = "JOKE CRAFTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", TAB_ON)
	col.add_child(title)

	_slot_labels = {}
	_owned_labels = {}
	_add_buttons = {}
	for kind in GameState.COMPONENT_KINDS:
		col.add_child(_craft_row(kind))

	# GENERATE and the balance share the bottom line: the button is the action,
	# the number is what it is for, and side by side they fit the well without
	# a third row.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	_craft_btn = Button.new()
	_craft_btn.text = "GENERATE JOKE!"
	_craft_btn.custom_minimum_size = Vector2(CRAFT_NAME_W + CRAFT_ICON + CRAFT_OWNED_W, 28)
	_craft_btn.add_theme_font_size_override("font_size", 8)
	_craft_btn.pressed.connect(guard_tap(_on_craft_pressed))
	foot.add_child(_craft_btn)
	_points_label = Label.new()
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_points_label.add_theme_font_size_override("font_size", 9)
	_points_label.add_theme_color_override("font_color", TAB_ON)
	_points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_points_label)
	col.add_child(foot)

	# One line for whatever the server last said — "CRAFTED 5 JOKES", or why a
	# call failed. Always present so the column height never changes.
	_craft_status = Label.new()
	_craft_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_craft_status.add_theme_font_size_override("font_size", 7)
	_craft_status.add_theme_color_override("font_color", DIM)
	col.add_child(_craft_status)

	_paint_crafter()
	return col


## | icon | NAME | owned | ADD | slot |
func _craft_row(kind: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(CRAFT_W, CRAFT_ROW_H)
	row.add_theme_constant_override("separation", 4)
	var tint: Color = CRAFT_TINTS.get(kind, TEXT)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(CRAFT_ICON, CRAFT_ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var path: String = "res://shared/assets/components/%s.png" % CRAFT_FILES.get(kind, "setup")
	if ResourceLoader.exists(path):
		icon.texture = load(path)
	icon.modulate = tint
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = String(CRAFT_LABELS.get(kind, kind.to_upper()))
	name_label.custom_minimum_size = Vector2(CRAFT_NAME_W, 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 8)
	name_label.add_theme_color_override("font_color", tint)
	row.add_child(name_label)

	var owned := Label.new()
	owned.custom_minimum_size = Vector2(CRAFT_OWNED_W, 0)
	owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	owned.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	owned.add_theme_font_size_override("font_size", 9)
	owned.add_theme_color_override("font_color", TEXT)
	row.add_child(owned)
	_owned_labels[kind] = owned

	var add := Button.new()
	add.text = "ADD >"
	add.custom_minimum_size = Vector2(CRAFT_ADD_W, 26)
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.add_theme_font_size_override("font_size", 8)
	add.pressed.connect(guard_tap(func(): _on_add_pressed(kind)))
	row.add_child(add)
	_add_buttons[kind] = add

	# The slot: a bordered box, so what is loaded reads as being IN something
	# rather than as a fourth number in the row.
	var slot_frame := Panel.new()
	slot_frame.custom_minimum_size = Vector2(CRAFT_SLOT_W, CRAFT_ROW_H - 6)
	slot_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = JOKE_FRAME_BG
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(2)
	sb.border_color = tint * Color(1, 1, 1, 0.55)
	slot_frame.add_theme_stylebox_override("panel", sb)
	var slot := Label.new()
	slot.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_theme_font_size_override("font_size", 9)
	slot.add_theme_color_override("font_color", tint)
	slot_frame.add_child(slot)
	row.add_child(slot_frame)
	_slot_labels[kind] = slot

	return row


## Repaint every number and button state from the cached crafter state. Called
## after a build, an ADD, and every server reply — one function, so the panel
## can never show a count and a button that disagree.
func _paint_crafter() -> void:
	# Switching tabs frees these along with the rest of the well, and a freed
	# node is not null — so validity, not a null check, is what makes a late
	# server reply safe.
	if not is_instance_valid(_craft_btn):
		return
	for kind in GameState.COMPONENT_KINDS:
		if _owned_labels.has(kind):
			_owned_labels[kind].text = _pad(_available(kind), CRAFT_OWNED_DIGITS)
		if _slot_labels.has(kind):
			_slot_labels[kind].text = _pad(int(_slots.get(kind, 0)), CRAFT_SLOT_DIGITS)
		if _add_buttons.has(kind):
			_add_buttons[kind].disabled = not _can_add(kind)
	var n := _batch()
	_craft_btn.disabled = n <= 0
	_craft_btn.text = "GENERATE JOKE!" if n <= 0 else "GENERATE %d JOKE%s!" % [n, "" if n == 1 else "S"]
	_points_label.text = "JP %s" % _pad(Leaderboard.joke_points(), 6)


## Zero-padded to a fixed width, arcade style, and clamped so a number can
## never render wider than the column it lives in.
func _pad(v: int, digits: int) -> String:
	var cap := int(pow(10, digits)) - 1
	return String.num_int64(clampi(v, 0, cap)).pad_zeros(digits)


func _on_add_pressed(kind: String) -> void:
	if not _can_add(kind):
		return
	GameState.play_sfx("click")
	_slots[kind] = int(_slots.get(kind, 0)) + 1
	_paint_crafter()


func _on_craft_pressed() -> void:
	var n := _batch()
	if n <= 0:
		return
	GameState.play_sfx("click")
	_craft_status.text = "CRAFTING ..."
	_craft_btn.disabled = true
	# Cleared optimistically: the reply carries the full post-craft inventory,
	# so leaving them loaded would double-count against it for a frame.
	_slots = {"setups": 0, "punchlines": 0, "tags": 0}
	Leaderboard.craft_jokes(n)


func _on_crafter_loaded(_data: Dictionary) -> void:
	if _tab != Tab.JOKE_BOOK:
		return
	if is_instance_valid(_craft_status):
		_craft_status.text = ""
	_paint_crafter()


func _on_crafter_failed(reason: String) -> void:
	if _tab != Tab.JOKE_BOOK or not is_instance_valid(_craft_status):
		return
	# The slots were cleared optimistically on GENERATE; a failure means the
	# server never took them, and since inventory is re-read from the server
	# the components are still there — only the loading is lost.
	_craft_status.text = reason.to_upper()
	_paint_crafter()


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


## A comedian's head at `px` square. The server only ever sends names; the
## sprites already ship in the build, so nothing crosses the wire and a name
## we no longer ship simply draws the factory's placeholder.
func _head_rect(character: String, px: int) -> TextureRect:
	var head := TextureRect.new()
	head.texture = CharacterFactory.head_texture(String(_heads.get(character, "")))
	head.custom_minimum_size = Vector2(px, px)
	head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	head.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return head


## Make a whole subtree click-through, so it can sit inside a Button without
## any of its labels eating the tap. Labels and TextureRects already default to
## ignoring the mouse; containers do not, which is the case this exists for.
static func _pass_through(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		if c is Control:
			_pass_through(c)


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

	row.add_child(_head_rect(character, HEAD_SIZE))
	row.add_child(_cell(character, 208 - count_w, HORIZONTAL_ALIGNMENT_LEFT, TEXT, GLOBAL_ROW_HEIGHT))
	return row


# ---------------------------------------------------------------- beef tab
## One request fills both panels (see getBeef in server/server.js): the paged
## attacker list on the left, and the grudge detail for whichever comedian is
## selected on the right.
func _load_beef() -> void:
	_update_pager()
	_message("Loading…")
	Leaderboard.fetch_beef(_beef_page, _beef_attacker)


## Tapping a row in the left list. No "Loading…" wipe here on purpose: the
## reply rebuilds both panels anyway, and blanking the screen for a round trip
## would make picking a comedian feel like leaving the board.
func _select_attacker(character: String) -> void:
	if character == _beef_attacker:
		return
	_beef_attacker = character
	Leaderboard.fetch_beef(_beef_page, _beef_attacker)


## Same late-response discipline as the other network tabs: anything answering
## a tab that is no longer on screen is dropped.
func _on_beef_loaded(data: Dictionary) -> void:
	if _tab != Tab.BEEF:
		return
	_beef_pages = maxi(int(data.get("pageCount", 1)), 1)
	_beef_page = clampi(int(data.get("page", _beef_page)), 0, _beef_pages - 1)
	_update_pager()

	var rows: Array = data.get("rows", [])
	if rows.is_empty():
		_message("No beef yet. Go start some!")
		return
	# The server has the last word on who is selected — it falls back to the
	# top of the page when we asked for nobody (or for a name it doesn't know),
	# so following its answer is what keeps the highlight and the right panel
	# describing the same comedian.
	var raw = data.get("selected")
	var selected: Dictionary = raw if raw is Dictionary else {}
	_beef_attacker = String(selected.get("character", ""))

	_clear_rows()
	var split := HBoxContainer.new()
	split.alignment = BoxContainer.ALIGNMENT_CENTER
	split.add_theme_constant_override("separation", PANEL_GAP)
	split.add_child(_beef_list_panel(rows))
	if not selected.is_empty():
		split.add_child(_beef_detail_panel(selected))
	_rows.add_child(split)


func _on_beef_failed(reason: String) -> void:
	if _tab != Tab.BEEF:
		return
	_message("Beef meter unavailable.\n(%s)" % reason)


## Left panel: comedians ranked by KOs their players have landed. Every row is
## a button — this is the one board on this screen you steer.
func _beef_list_panel(rows: Array) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(BEEF_LEFT_W, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_constant_override("separation", 0)
	panel.add_child(_cell("BEEFCAKES", BEEF_LEFT_W, HORIZONTAL_ALIGNMENT_CENTER,
		TAB_ON, PANEL_HEADER_H, BEEF_TITLE_FONT))
	for r in rows:
		panel.add_child(_beef_list_row(r))
	return panel


## | head | name | — see BEEF_LIST_HEAD for the width budget. The row contents
## ride inside the Button as a click-through overlay, because a Button's own
## text can't lay out a head sprite next to a label.
func _beef_list_row(r: Dictionary) -> Button:
	var character := String(r.get("character", "?"))
	var on := character == _beef_attacker
	var b := Button.new()
	b.custom_minimum_size = Vector2(BEEF_LEFT_W, BEEF_ROW_HEIGHT)
	set_tip(b, "Show %s's beef" % character)
	_style_beef_row(b, on)
	b.pressed.connect(guard_tap(func():
		GameState.play_sfx("click")
		_select_attacker(character)))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Inset from the button's border on both sides — the room the rank and KO
	# columns used to take.
	row.offset_left = BEEF_ROW_PAD
	row.offset_right = -BEEF_ROW_PAD
	row.add_theme_constant_override("separation", 4)
	row.add_child(_head_rect(character, BEEF_LIST_HEAD))
	row.add_child(_cell(character, BEEF_LEFT_W - BEEF_ROW_PAD * 2 - BEEF_LIST_HEAD - 4,
		HORIZONTAL_ALIGNMENT_LEFT, TAB_ON if on else TEXT, BEEF_ROW_HEIGHT))
	_pass_through(row)
	b.add_child(row)
	return b


## The selected row wears the menus' gold; the rest sit back in a dim outline
## so the list reads as one column with one thing picked out of it. Zero
## content margins, or the theme's asymmetric button padding would shove the
## anchored row overlay off-centre.
func _style_beef_row(b: Button, on: bool) -> void:
	var fills := {
		"normal": Color(0.17, 0.14, 0.24, 0.9) if on else Color(0.10, 0.09, 0.15, 0.6),
		"hover": Color(0.24, 0.20, 0.32, 0.9),
		"pressed": Color(0.10, 0.09, 0.15, 0.9),
		"focus": Color(0.17, 0.14, 0.24, 0.9) if on else Color(0.10, 0.09, 0.15, 0.6),
	}
	for state in fills:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fills[state]
		sb.set_corner_radius_all(BUTTON_RADIUS)
		sb.set_border_width_all(2 if on else 1)
		sb.border_color = TAB_ON if on else ROW_EDGE
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		b.add_theme_stylebox_override(state, sb)


## Right panel: the selected comedian's portrait, their two-sided KO ledger,
## and who they have beef with. Bars are scaled to the WORST beef in this list,
## so the top row always fills and the rest read as a share of it.
func _beef_detail_panel(selected: Dictionary) -> VBoxContainer:
	var character := String(selected.get("character", "?"))
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(BEEF_RIGHT_W, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_constant_override("separation", 2)
	panel.add_child(_cell(character.to_upper(), BEEF_RIGHT_W, HORIZONTAL_ALIGNMENT_CENTER,
		TAB_ON, 16, BEEF_TITLE_FONT))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", PANEL_GAP)
	top.add_child(_head_rect(character, BEEF_PORTRAIT))
	# Three children, so TWO separations come out of the width before the two
	# boxes split what's left: 56 + 8 + 126 + 8 + 126 = BEEF_RIGHT_W.
	var stat_w := (BEEF_RIGHT_W - BEEF_PORTRAIT - PANEL_GAP * 2) / 2.0
	top.add_child(_beef_stat("KOs LANDED", int(selected.get("dealt", 0)), stat_w, DEALT))
	top.add_child(_beef_stat("KOs TAKEN", int(selected.get("taken", 0)), stat_w, TAKEN))
	panel.add_child(top)

	panel.add_child(_cell("MOST BEEF WITH", BEEF_RIGHT_W, HORIZONTAL_ALIGNMENT_CENTER,
		TAB_ON, PANEL_HEADER_H, 8))
	var victims: Array = selected.get("victims", [])
	if victims.is_empty():
		panel.add_child(_cell("Hasn't laid a finger on anyone.", BEEF_RIGHT_W,
			HORIZONTAL_ALIGNMENT_CENTER, DIM, BEEF_VICTIM_ROW_H))
		return panel
	# The rows pack tight in their own container so the 2px gaps stay between
	# the panel's SECTIONS. Height budget: 16 + 56 + 14 + (24 + 21 + 18 * 3)
	# plus three 2px section gaps = 191, inside the 194px well.
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	var worst := maxi(int(victims[0].get("kos", 0)), 1)
	for i in victims.size():
		list.add_child(_beef_victim_row(i + 1, victims[i], worst))
	panel.add_child(list)
	return panel


## The top two grudges are typeset bigger, so the real feud reads at a glance
## instead of hiding in five identical rows. Height tracks font size to keep
## the rows padded the same; the column widths never change, so everything
## still lines up down the panel.
func _victim_font(rank: int) -> int:
	match rank:
		1: return 13
		2: return 11
		_: return ROW_FONT


func _victim_height(rank: int) -> int:
	match rank:
		1: return 24
		2: return 21
		_: return BEEF_VICTIM_ROW_H


## One half of the ledger: a caption over a big number in its own outlined box.
## Green for KOs this comedian dealt out, red for the ones they took.
func _beef_stat(caption: String, value: int, width: float, color: Color) -> PanelContainer:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.15, 0.7)
	sb.set_corner_radius_all(BUTTON_RADIUS)
	sb.set_border_width_all(1)
	sb.border_color = ROW_EDGE
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(width, BEEF_PORTRAIT)
	box.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.add_child(_cell(caption, width - 4, HORIZONTAL_ALIGNMENT_CENTER, DIM, 12, 8))
	col.add_child(_cell("%d" % value, width - 4, HORIZONTAL_ALIGNMENT_CENTER, color, 22, 16))
	box.add_child(col)
	return box


## | rank | head | name | bar | KOs | — the count is shown as well as the bar,
## because the bar is relative and only the number says how bad it actually is.
func _beef_victim_row(rank: int, victim: Dictionary, worst: int) -> HBoxContainer:
	var character := String(victim.get("character", "?"))
	var kos := int(victim.get("kos", 0))
	var h := _victim_height(rank)
	var font := _victim_font(rank)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_head_rect(character, BEEF_VICTIM_HEAD))
	# The top rows' bigger type fits fewer characters, so a long name trails off
	# rather than being chopped through a glyph.
	var name_cell := _cell(character, 188, HORIZONTAL_ALIGNMENT_LEFT, TEXT, h, font)
	name_cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_cell)

	var bar := BeefBar.new()
	bar.ratio = float(kos) / float(worst)
	bar.custom_minimum_size = Vector2(BEEF_BAR_W, BEEF_BAR_H)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)

	row.add_child(_cell("%d" % kos, 40, HORIZONTAL_ALIGNMENT_RIGHT, YOU, h, font))
	return row
