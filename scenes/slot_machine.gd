extends MenuBase
## SLOT MACHINE: the first mini game. Three reels showing three symbols each,
## and a SPIN button. EVERY line of three pays — three rows, three columns and
## both diagonals, eight in all. See PAYLINES for why columns are in there.
##
## NOTHING IS SCORED YET. This deliberately does not talk to Leaderboard: the
## crafter's points are server-owned (the server decides every payout, see
## server/server.js postCraft), so a client that hands itself winnings would be
## the one genuinely cheatable path in that whole feature. Wiring a payout in
## means a server endpoint that rolls the reels, not a number added here.
##
## LAYOUT. Only the SHELL is art (slot_cabinet.png): the marquee title, the
## nine symbols, the result line and SPIN are all real controls drawn on top,
## so the reels are live and nothing has to line up with a picture of itself
## — the same split the JOKE CRAFTER notepad uses.
##
## Every rect below was MEASURED off slot_cabinet.png (the dark insets the
## generation left empty), not guessed, and is in that texture's own 350x282
## pixels. Re-measure them if the art is ever regenerated.

const CAB_ART := "res://shared/assets/minigames/slot_cabinet.png"
const CAB_SIZE := Vector2(350, 282)
## The lit panel behind the marquee bulbs.
const MARQUEE_RECT := Rect2(25, 14, 265, 31)
## The three reel windows, left to right. Each is exactly three cells tall.
const REEL_RECTS := [
	Rect2(48, 60, 63, 147),
	Rect2(126, 60, 63, 147),
	Rect2(204, 60, 63, 147),
]
## The recessed plate in the cabinet base, which SPIN fills.
const PLATE_RECT := Rect2(73, 224, 169, 35)
## VERTICAL PLACEMENT. The cabinet is pinned this far from the top rather than
## centred, so the result line has somewhere to go: there is no band inside the
## cabinet tall enough for a line of text. Cabinet 12..294, result 302..326,
## and SAFE_BOTTOM starts at 344.
const CAB_TOP := 12.0
const RESULT_GAP := 8.0
const RESULT_H := 24.0

## The reel symbols. The first three are the JOKE CRAFTER components the street
## already drops — same art, same tints as ComponentPickup.TINTS, deliberately,
## so a SETUP looks like a SETUP whether it is on the pavement or on a reel.
## The rest is what else you find on the walk between venues.
##
## `weight` is the draw chance, not a payout: components come up half again as
## often as street junk, so a line of three is usually something you wanted.
## `junk` only picks which flavour line a win gets.
const SYMBOLS := [
	{"label": "SETUP", "art": "res://shared/assets/components/setup.png",
		"tint": Color(1.0, 1.0, 1.0), "weight": 3, "junk": false},
	{"label": "PUNCHLINE", "art": "res://shared/assets/components/punchline.png",
		"tint": Color(0.62, 0.90, 1.15), "weight": 3, "junk": false},
	{"label": "TAG", "art": "res://shared/assets/components/tag.png",
		"tint": Color(0.72, 1.12, 0.80), "weight": 3, "junk": false},
	{"label": "PIGEON", "art": "res://shared/assets/components/pigeon.png",
		"tint": Color(0.80, 0.86, 1.05), "weight": 2, "junk": true},
	{"label": "RAT", "art": "res://shared/assets/components/rat.png",
		"tint": Color(0.90, 0.82, 0.88), "weight": 2, "junk": true},
	{"label": "PAPER", "art": "res://shared/assets/components/paper.png",
		"tint": Color(1.0, 0.97, 0.90), "weight": 2, "junk": true},
	{"label": "APPLE", "art": "res://shared/assets/components/apple.png",
		"tint": Color(1.25, 0.55, 0.50), "weight": 2, "junk": true},
]
const SYMBOL_PX := 48
## One cell per visible row: three of them exactly fill a 147px window.
const CELL_H := 49
const ROWS := 3
const REELS := 3

## EVERY line of three pays: three rows, three columns, both diagonals.
##
## Columns are the unusual one — a real machine never pays them, because a
## column IS one reel and three of a kind down it is just that reel's strip
## repeating. But measured over 400k spins a column shows a triple on 6.7% of
## spins, which is exactly as often as a row actually wins: paying rows only
## meant half of every "wait, did I win?" moment was a dud. Nothing is at
## stake here, so the grid pays what it looks like it pays.
##
## Eight lines put a win at ~1 in 6 spins (rows alone were ~1 in 15).
## Entries are (reel, row).
const PAYLINES := [
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
	[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	[Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)],
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
	[Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)],
	[Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)],
	[Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2)],
	[Vector2i(0, 2), Vector2i(1, 1), Vector2i(2, 0)],
]
## Winning CELLS light up rather than whole lines: a diagonal cannot be drawn
## as one band, and lighting cells means rows, columns and diagonals all use
## the same mechanism — and a cell shared by two winning lines just lights once.
const WIN_CELL := Color(1.0, 0.82, 0.35, 0.32)

## Reel feel. The drum scrolls at SCROLL_PX; reel i begins settling at
## SPIN_FIRST + i * SPIN_STAGGER seconds, so they land left to right and the
## last one carries the suspense.
const SCROLL_PX := 900.0
const SPIN_FIRST := 0.8
const SPIN_STAGGER := 0.5
const LAND_TIME := 0.34
## Win shake, in pixels and seconds.
const SHAKE_PX := 5.0
const SHAKE_TIME := 0.30

const GOLD := Color(1.0, 0.85, 0.4)
const DIM := Color(0.62, 0.62, 0.72)

## Flavour only — the reels pay nothing yet, so the line IS the reward.
const WIN_LINES := [
	"KILLER SET!", "THE ROOM IS YOURS!", "STANDING OVATION!", "THAT'S THE CLOSER!",
]
## Three of a kind, but of something you found in a gutter.
const JUNK_WIN_LINES := [
	"...THAT'S YOUR ACT NOW.", "THE CROWD IS LEAVING.",
	"EVEN THE BAR WENT QUIET.", "TIGHT FIVE OF NOTHING.",
]
const PAIR_LINES := [
	"SO CLOSE.", "ALMOST HAD 'EM.", "POLITE CHUCKLE.", "ONE MORE AND YOU HAD IT.",
]
const MISS_LINES := [
	"CRICKETS.", "TOUGH CROWD.", "YOU BOMBED.", "SOMEONE COUGHED.", "CHECK, PLEASE.",
]

## A reel is a strip of STRIP sprites scrolling through a three-cell window.
## Sprite k sits at y = (k - 1) * CELL_H + offset, so at offset 0 sprite 1 is
## the top row, 2 is the payline and 3 is the bottom row — and sprite 0 is
## parked just above the window, ready to come down. Four is the fewest that
## keeps the window covered for the whole of one cell of travel.
const STRIP := 4

var _icons: Array = []          # per reel: Array[TextureRect], STRIP of them
var _strip: Array = []          # per reel: Array[int] of symbol indices
var _off := [0.0, 0.0, 0.0]
var _live := [false, false, false]
var _stop_at := [0.0, 0.0, 0.0]
## Per reel, the column of ROWS symbols it is going to land on, rolled at
## the moment SPIN is pressed. A server-rolled payout would hand back
## exactly this and change nothing else here.
var _target: Array = []
var _t := 0.0
var _spinning := false
var _settling := 0

var _cells: Array = []          # per reel: ROWS gold cell lights
var _shaker: Control
var _spin_btn: Button
var _result: Label
var _marquee: Label


func _ready() -> void:
	build_backdrop()
	# The cabinet is placed by hand rather than dropped in the menu column: it
	# is one fixed-size piece of art with controls pinned to measured points
	# inside it, and a container would fight every one of those numbers.
	var cab := Control.new()
	cab.anchor_left = 0.5
	cab.anchor_right = 0.5
	cab.offset_left = -CAB_SIZE.x / 2.0
	cab.offset_right = CAB_SIZE.x / 2.0
	cab.offset_top = CAB_TOP
	cab.offset_bottom = CAB_TOP + CAB_SIZE.y
	cab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cab)

	# Everything rides this un-anchored inner node so a win can shake the whole
	# machine by tweening one position — an anchored node would be snapped back
	# to its offsets on the next layout pass.
	_shaker = Control.new()
	_shaker.size = CAB_SIZE
	_shaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cab.add_child(_shaker)

	var art := TextureRect.new()
	art.texture = load(CAB_ART)
	art.size = CAB_SIZE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shaker.add_child(art)

	_build_reels()
	_marquee = _pin_label(MARQUEE_RECT, "JOKE SLOTS", 14, GOLD)

	# Under the machine, and NOT on the shaker — a win rattles the cabinet, and
	# a result line jittering along with it is just hard to read.
	_result = Label.new()
	_result.text = "PULL FOR A PUNCHLINE"
	_result.anchor_right = 1.0
	_result.offset_top = CAB_TOP + CAB_SIZE.y + RESULT_GAP
	_result.offset_bottom = CAB_TOP + CAB_SIZE.y + RESULT_GAP + RESULT_H
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result.add_theme_font_size_override("font_size", 10)
	_result.add_theme_color_override("font_color", DIM)
	add_child(_result)

	_spin_btn = Button.new()
	_spin_btn.text = "SPIN"
	_spin_btn.add_theme_font_size_override("font_size", 12)
	_spin_btn.position = PLATE_RECT.position
	_spin_btn.size = PLATE_RECT.size
	MenuBase.style_purple_button(_spin_btn)
	_spin_btn.pressed.connect(guard_tap(_spin))
	_shaker.add_child(_spin_btn)

	add_back_button(func(): GameState.change_scene(GameState.SCENE_MINI_GAMES))
	set_process(false)


## A read-only caption pinned to one of the cabinet's measured insets.
func _pin_label(rect: Rect2, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	_shaker.add_child(l)
	return l


func _build_reels() -> void:
	for i in REEL_RECTS.size():
		var rect: Rect2 = REEL_RECTS[i]
		var window := Control.new()
		window.position = rect.position
		window.size = rect.size
		window.clip_contents = true
		window.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shaker.add_child(window)

		# The cell lights go in FIRST so they glow behind the symbols, and
		# inside the window so they are clipped with everything else.
		var lights: Array = []
		for row in ROWS:
			var cell := ColorRect.new()
			cell.color = WIN_CELL
			cell.position = Vector2(0, row * CELL_H)
			cell.size = Vector2(rect.size.x, CELL_H)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.visible = false
			window.add_child(cell)
			lights.append(cell)
		_cells.append(lights)

		var sprites: Array = []
		var faces: Array = []
		for k in STRIP:
			var icon := TextureRect.new()
			icon.size = Vector2(SYMBOL_PX, SYMBOL_PX)
			icon.position.x = floorf((rect.size.x - SYMBOL_PX) / 2.0)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			window.add_child(icon)
			sprites.append(icon)
			faces.append(_roll())
		_icons.append(sprites)
		_strip.append(faces)

		_paint(i)
		_apply_offset(0.0, i)


## Draw from SYMBOLS by weight. See the `weight` note on that constant.
func _roll() -> int:
	var total := 0
	for s in SYMBOLS:
		total += int(s["weight"])
	var pick := randi() % total
	for i in SYMBOLS.size():
		pick -= int(SYMBOLS[i]["weight"])
		if pick < 0:
			return i
	return 0


## Push this reel's strip of symbol indices onto its sprites.
func _paint(reel: int) -> void:
	for k in STRIP:
		var sym: Dictionary = SYMBOLS[_strip[reel][k]]
		var icon: TextureRect = _icons[reel][k]
		icon.texture = load(String(sym["art"]))
		icon.modulate = sym["tint"]


## Place every sprite on this reel for a given scroll offset within one cell.
func _apply_offset(v: float, reel: int) -> void:
	_off[reel] = v
	for k in STRIP:
		_icons[reel][k].position.y = (k - 1) * CELL_H + v


func _spin() -> void:
	if _spinning:
		return
	_spinning = true
	_t = 0.0
	_settling = REEL_RECTS.size()
	_target = []
	_target.resize(REEL_RECTS.size())
	for reel in _cells:
		for cell in reel:
			cell.visible = false
	_spin_btn.disabled = true
	_result.text = "..."
	_result.add_theme_color_override("font_color", DIM)
	GameState.play_sfx("swing")
	for i in REEL_RECTS.size():
		_live[i] = true
		# Rolled up front, and only revealed as each reel lands. The scroll
		# between now and then is decoration over a decision already made —
		# which is also the shape a server-rolled payout would take later.
		var column: Array = []
		for r in ROWS:
			column.append(_roll())
		_target[i] = column
		_stop_at[i] = SPIN_FIRST + i * SPIN_STAGGER
	set_process(true)


func _process(delta: float) -> void:
	if not _spinning:
		return
	_t += delta
	for i in REEL_RECTS.size():
		if not _live[i]:
			continue
		if _t >= _stop_at[i]:
			_land(i)
			continue
		_apply_offset(_off[i] + SCROLL_PX * delta, i)
		while _off[i] >= CELL_H:
			_advance(i, _off[i] - CELL_H)


## One cell of travel has gone by: the bottom sprite has just left the window,
## so it becomes the new top one and takes a fresh face.
func _advance(reel: int, carry: float) -> void:
	var faces: Array = _strip[reel]
	faces.push_front(faces.pop_back())
	faces[0] = _roll()
	_paint(reel)
	_apply_offset(carry, reel)


## Bring a reel to rest on the face it was always going to land on. Rather
## than snapping, it keeps travelling to the next cell boundary and decelerates
## into it — so the strip is seeded one cell ahead with the target on what will
## become the payline, and the reel simply arrives there.
func _land(reel: int) -> void:
	_live[reel] = false
	# At the end of the travel (offset == CELL_H) sprite k sits on row k, so
	# seeding strip indices 0..ROWS-1 lands the rolled column on the rows.
	for r in ROWS:
		_strip[reel][r] = _target[reel][r]
	_paint(reel)
	var t := create_tween()
	t.tween_method(_apply_offset.bind(reel), float(_off[reel]), float(CELL_H), LAND_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(_settle.bind(reel))
	GameState.play_sfx("click")


## Normalise after the landing tween: the reel is one whole cell along, so roll
## the strip over and put the offset back to zero. Nothing moves on screen.
func _settle(reel: int) -> void:
	_advance(reel, 0.0)
	_settling -= 1
	if _settling <= 0:
		_finish()


func _finish() -> void:
	_spinning = false
	set_process(false)
	_spin_btn.disabled = false

	# Read the grid off the rolled columns and test all eight lines. `won`
	# collects the CELLS to light, keyed so a cell on two lines lights once.
	var hits: Array = []
	var won := {}
	var near := false
	for line in PAYLINES:
		var a: int = _target[line[0].x][line[0].y]
		var b: int = _target[line[1].x][line[1].y]
		var c: int = _target[line[2].x][line[2].y]
		if a == b and b == c:
			hits.append(a)
			for cell in line:
				won[cell] = true
		elif a == b or b == c or a == c:
			near = true

	if hits.is_empty():
		if near:
			_result.text = PAIR_LINES[randi() % PAIR_LINES.size()]
			_result.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
		else:
			_result.text = MISS_LINES[randi() % MISS_LINES.size()]
			_result.add_theme_color_override("font_color", DIM)
		return

	for cell in won:
		_light_cell(cell.x, cell.y)
	# A win made only of street junk gets needled rather than cheered.
	var all_junk := true
	for sym in hits:
		if not bool(SYMBOLS[sym]["junk"]):
			all_junk = false
	var lines: Array = JUNK_WIN_LINES if all_junk else WIN_LINES
	var tail: String = lines[randi() % lines.size()]
	if hits.size() > 1:
		_result.text = "%d LINES! - %s" % [hits.size(), tail]
	else:
		_result.text = "%s x3 - %s" % [String(SYMBOLS[hits[0]]["label"]), tail]
	_result.add_theme_color_override("font_color",
			Color(1.0, 0.6, 0.55) if all_junk else GOLD)
	GameState.play_sfx("clear")
	_celebrate()


func _light_cell(reel: int, row: int) -> void:
	var cell: ColorRect = _cells[reel][row]
	cell.visible = true
	cell.modulate.a = 0.0
	var t := create_tween()
	t.set_loops(4)
	t.tween_property(cell, "modulate:a", 1.0, 0.16)
	t.tween_property(cell, "modulate:a", 0.35, 0.16)


## Three of a kind: rattle the cabinet and flash the marquee. Both run off the
## un-anchored _shaker / a colour override, so neither can be undone by a
## layout pass mid-tween.
func _celebrate() -> void:
	var shake := create_tween()
	for i in 4:
		var dx := SHAKE_PX if i % 2 == 0 else -SHAKE_PX
		shake.tween_property(_shaker, "position:x", dx, SHAKE_TIME / 4.0)
	shake.tween_property(_shaker, "position:x", 0.0, SHAKE_TIME / 4.0)
	var flash := create_tween()
	flash.set_loops(3)
	flash.tween_property(_marquee, "modulate", Color(1.6, 1.4, 0.8), 0.09)
	flash.tween_property(_marquee, "modulate", Color(1, 1, 1), 0.09)
