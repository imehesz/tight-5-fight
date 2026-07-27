class_name Hud
extends CanvasLayer
## In-game HUD: player portrait, health bar, lives, score, venue banner and
## a big center label for announcements ("SURVIVE 12", "VENUE BATTLED!").

const BAR_W := 150.0
## The player's bobblehead in a framed box before the health bar, arcade
## beat-'em-up style. It flips horizontally at random moments — a cheap bit
## of life old cabinets used to fake with palette/frame swaps. The head is
## drawn bigger than the frame and centered on it, spilling past the border
## on every side on purpose.
const PORTRAIT := 26.0
const HEAD := 35.0
## Gain fliers: "+250" / "+1 LIFE" pop to 2x over the action, then sail to
## their HUD counter (score top-right, lives top-left), shrinking back to
## 1x and fading out just before they land on it.
const FLY_POP_S := 0.12
const FLY_S := 0.7
const FLY_FADE_S := 0.3
const FLY_GOLD := Color(1.0, 0.85, 0.4)
const FLY_GREEN := Color(0.3, 0.9, 0.35)
## THE TIGHT 5 CLOCK, right under the venue/street banner: white on a colored
## box that gets angrier as the run burns down — dark green, orange under 2:00,
## red under 1:00, flipping black/red on every whole second under 0:10, and the
## whole box swelling under 0:05. GameState owns the countdown itself; this is
## purely the readout, polled every frame in _process.
const CLOCK_SIZE := Vector2(76, 26)
const CLOCK_TOP := 22.0
const CLOCK_FONT := 14
const CLOCK_ORANGE_AT := 120.0
const CLOCK_RED_AT := 60.0
const CLOCK_BLINK_AT := 10.0
const CLOCK_PANIC_AT := 5.0
const CLOCK_PANIC_SCALE := 1.45
const CLOCK_GREEN := Color(0.05, 0.32, 0.12)
const CLOCK_ORANGE := Color(0.85, 0.45, 0.05)
const CLOCK_RED := Color(0.72, 0.08, 0.06)
const CLOCK_BLACK := Color(0.04, 0.04, 0.04)
## Earned seconds (venue cleared, good set box) flash the box green and pop
## it, so time coming BACK is as loud as time running out.
const CLOCK_GAIN := Color(0.35, 0.95, 0.45)
const CLOCK_GAIN_S := 0.5
const CLOCK_GAIN_POP := 1.5

var _health_fill: ColorRect
var _lives_label: Label
var _bosses_label: Label
var _score_label: Label
var _streak_label: Label
var _venue_label: Label
var _clock_panel: Panel
var _clock_style: StyleBoxFlat
var _clock_label: Label
## Seconds left on the green "+Ns" flash; 0 when the box is showing its
## normal countdown color.
var _clock_gain := 0.0
var _center_label: Label
var _portrait: TextureRect
var _portrait_style: StyleBoxFlat
var _flip_timer: Timer
var _player: Fighter
## -1 = not seeded yet: the first signal after _ready() sets the baseline
## without flying (a fresh HUD mid-run must not replay the whole score).
var _last_score := -1
var _last_lives := -1


func _ready() -> void:
	layer = 80
	# The frame's border doubles as a health light, same color as the bar.
	var frame := Panel.new()
	_portrait_style = StyleBoxFlat.new()
	_portrait_style.bg_color = Color(0, 0, 0, 0.55)
	_portrait_style.border_color = Color(0.3, 0.9, 0.35)
	_portrait_style.set_border_width_all(2)
	_portrait_style.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", _portrait_style)
	frame.position = Vector2(10, 6)
	frame.size = Vector2(PORTRAIT + 4, PORTRAIT + 4)
	add_child(frame)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.55)
	bar_bg.position = Vector2(44, 8)
	bar_bg.size = Vector2(BAR_W + 4, 14)
	add_child(bar_bg)
	_health_fill = ColorRect.new()
	_health_fill.color = Color(0.3, 0.9, 0.35)
	_health_fill.position = Vector2(46, 10)
	_health_fill.size = Vector2(BAR_W, 10)
	add_child(_health_fill)

	# The head is added AFTER the bar so its overflow drapes over the bar's
	# left edge instead of being covered by it.
	_portrait = TextureRect.new()
	# expand_mode BEFORE texture/size: with the default EXPAND_KEEP_SIZE the
	# 200x200 head texture pins the control's minimum size, and an explicit
	# size set while pinned is clamped up to it and never comes back down.
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture = CharacterFactory.head_texture(
			String(GameState.selected_character_data().get("HeadSpritePath", "")))
	# Centered on the frame's center (25, 21), overflowing it evenly.
	_portrait.position = Vector2(25 - HEAD / 2.0, 21 - HEAD / 2.0)
	_portrait.size = Vector2(HEAD, HEAD)
	add_child(_portrait)
	_flip_timer = Timer.new()
	_flip_timer.one_shot = true
	_flip_timer.timeout.connect(_flip_portrait)
	add_child(_flip_timer)
	_flip_timer.start(randf_range(1.0, 3.0))

	_lives_label = _label(Vector2(44, 26), 8)
	_bosses_label = _label(Vector2(136, 26), 8)
	_score_label = _label(Vector2(0, 8), 11, 164, HORIZONTAL_ALIGNMENT_RIGHT)
	# Pinned to the LIVE right edge with the same 10px padding the health
	# cluster keeps on the left — the old fixed x=466 was a design-width bake
	# that drifted inward on wide phones (aspect="expand").
	_score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_score_label.offset_left = -174.0
	_score_label.offset_right = -10.0
	_score_label.offset_top = 8.0
	# KO streak chip right under the score, pinned to the LIVE right edge the
	# same way. Shown only while a streak is alive (see _process).
	_streak_label = _label(Vector2(0, 26), 8, 164, HORIZONTAL_ALIGNMENT_RIGHT)
	_streak_label.modulate = Color(1.0, 0.85, 0.4)
	_streak_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_streak_label.offset_left = -174.0
	_streak_label.offset_right = -10.0
	_streak_label.offset_top = 26.0
	_streak_label.visible = false
	# Banner and announcements center on the LIVE viewport, not design 320 —
	# a design-centered box sits visibly left of center on wide phones.
	_venue_label = _label(Vector2(0, 8), 8, 300, HORIZONTAL_ALIGNMENT_CENTER)
	_venue_label.modulate = Color(1.0, 0.85, 0.4)
	_venue_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_venue_label.offset_left = -150.0
	_venue_label.offset_right = 150.0
	_venue_label.offset_top = 8.0
	_build_clock()
	_center_label = _label(Vector2(0, 110), 14, 400, HORIZONTAL_ALIGNMENT_CENTER)
	_center_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_center_label.offset_left = -200.0
	_center_label.offset_right = 200.0
	_center_label.offset_top = 110.0

	GameState.score_changed.connect(_on_score_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.bosses_changed.connect(_on_bosses_changed)
	GameState.streak_changed.connect(_on_streak_changed)
	GameState.time_added.connect(_on_time_added)
	_on_score_changed(GameState.score)
	_on_lives_changed(GameState.lives)
	_on_bosses_changed(GameState.bosses_defeated)
	_on_streak_changed(GameState.streak, GameState.streak_mult())


## The streak window can lapse with no KO to signal it, so visibility is
## polled here rather than driven by streak_changed alone.
func _process(delta: float) -> void:
	_streak_label.visible = GameState.streak_active()
	_clock_gain = maxf(_clock_gain - delta, 0.0)
	_update_clock()


## Centered under the banner. The panel is anchored to the LIVE viewport center
## (never design-width 320 — wide phones would sit it left of center) and its
## pivot is the box center, so the under-0:05 swell grows in place.
func _build_clock() -> void:
	_clock_style = StyleBoxFlat.new()
	_clock_style.bg_color = CLOCK_GREEN
	_clock_style.border_color = Color(0, 0, 0, 0.85)
	_clock_style.set_border_width_all(2)
	_clock_style.set_corner_radius_all(3)
	_clock_panel = Panel.new()
	_clock_panel.add_theme_stylebox_override("panel", _clock_style)
	_clock_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_clock_panel.offset_left = -CLOCK_SIZE.x / 2.0
	_clock_panel.offset_right = CLOCK_SIZE.x / 2.0
	_clock_panel.offset_top = CLOCK_TOP
	_clock_panel.offset_bottom = CLOCK_TOP + CLOCK_SIZE.y
	_clock_panel.pivot_offset = CLOCK_SIZE / 2.0
	add_child(_clock_panel)

	_clock_label = Label.new()
	_clock_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_size_override("font_size", CLOCK_FONT)
	_clock_label.add_theme_color_override("font_color", Color.WHITE)
	_clock_panel.add_child(_clock_label)
	_update_clock()


## Earned seconds: the box goes green, pops, and settles back over
## CLOCK_GAIN_S — it reads even while the countdown colors are doing their
## own thing, because green never appears below 2:00 otherwise.
func _on_time_added(seconds: float) -> void:
	_clock_gain = CLOCK_GAIN_S
	_fly_gain("+%ds" % seconds, CLOCK_GAIN,
			_clock_panel.get_global_rect().get_center())


func _update_clock() -> void:
	var left := GameState.run_time_left
	_clock_label.text = GameState.time_text()
	_clock_style.bg_color = CLOCK_GAIN if _clock_gain > 0.0 else _clock_color(left)
	# Under 0:05 the whole box swells, with a small pop on each second tick
	# that eases back down — the last five seconds should feel like a hook.
	var scale_now := 1.0
	if left <= CLOCK_PANIC_AT:
		scale_now = CLOCK_PANIC_SCALE * (1.0 + 0.09 * fmod(left, 1.0))
	# The gain pop rides on top of whatever scale the countdown asked for, so
	# banking time in the last five seconds still reads.
	if _clock_gain > 0.0:
		scale_now *= 1.0 + (CLOCK_GAIN_POP - 1.0) * (_clock_gain / CLOCK_GAIN_S)
	_clock_panel.scale = Vector2(scale_now, scale_now)


func _clock_color(left: float) -> Color:
	if left > CLOCK_ORANGE_AT:
		return CLOCK_GREEN
	if left > CLOCK_RED_AT:
		return CLOCK_ORANGE
	if left > CLOCK_BLINK_AT:
		return CLOCK_RED
	# Final ten seconds: alternate on every whole second (…0:08 red, 0:07
	# black…), so the box itself is ticking.
	return CLOCK_RED if int(ceilf(left)) % 2 == 0 else CLOCK_BLACK


func bind_player(p: Fighter) -> void:
	_player = p
	p.health_changed.connect(_on_health_changed)
	_on_health_changed(p.health, p.max_health)


func set_venue_text(t: String) -> void:
	_venue_label.text = t


func set_center_text(t: String) -> void:
	_center_label.text = t


func _flip_portrait() -> void:
	_portrait.flip_h = not _portrait.flip_h
	_flip_timer.start(randf_range(1.0, 3.0))


func _on_health_changed(current: float, maximum: float) -> void:
	var ratio := current / maxf(maximum, 1.0)
	_health_fill.size.x = BAR_W * ratio
	var color := _health_color(ratio)
	_health_fill.color = color
	_portrait_style.border_color = color


## Green / amber / red tiers — same thresholds and colors as the NPCs'
## overhead bars (enemy.gd), so damage reads identically everywhere.
func _health_color(ratio: float) -> Color:
	if ratio < 0.35:
		return Color(0.9, 0.25, 0.2)
	if ratio < 0.7:
		return Color(0.95, 0.8, 0.25)
	return Color(0.3, 0.9, 0.35)


func _on_score_changed(s: int) -> void:
	if _last_score >= 0 and s > _last_score:
		_fly_gain("+%d" % (s - _last_score), FLY_GOLD,
				_score_label.get_global_rect().get_center())
	_last_score = s
	_score_label.text = "SCORE %06d" % s


func _on_lives_changed(l: int) -> void:
	if _last_lives >= 0 and l > _last_lives:
		_fly_gain("+%d LIFE" % (l - _last_lives), FLY_GREEN,
				_lives_label.get_global_rect().get_center())
	_last_lives = l
	_lives_label.text = "LIVES x%d" % maxi(l, 0)


## A gained amount flying home to its counter: born over the action, popped
## to 2x, then sailing to `target` while shrinking back and going
## transparent on arrival.
func _fly_gain(text: String, color: Color, target: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.modulate = color
	add_child(lbl)
	lbl.reset_size()
	lbl.pivot_offset = lbl.size / 2.0  # scale from the center, not top-left
	lbl.position = _gain_origin() - lbl.size / 2.0
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "scale", Vector2(2, 2), FLY_POP_S) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Ease IN: it lingers readably over the action, then whips to the corner.
	tw.tween_property(lbl, "position", target - lbl.size / 2.0, FLY_S) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(lbl, "scale", Vector2.ONE, FLY_S)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, FLY_FADE_S) \
			.set_delay(FLY_S - FLY_FADE_S)
	tw.tween_callback(lbl.queue_free)


## Fliers launch from the player's chest (that's where the earning action
## is), projected into screen space; center-screen when the player is gone.
func _gain_origin() -> Vector2:
	if is_instance_valid(_player):
		return get_viewport().get_canvas_transform() \
				* (_player.global_position + Vector2(0.0, -70.0))
	var view := get_viewport().get_visible_rect().size
	return Vector2(view.x / 2.0, view.y * 0.4)


func _on_bosses_changed(n: int) -> void:
	_bosses_label.text = "BOSSES: %d" % n


func _on_streak_changed(_count: int, mult: int) -> void:
	_streak_label.text = "STREAK x%d" % mult


func _label(pos: Vector2, font_size: int, width := 0.0,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.position = pos
	l.horizontal_alignment = align
	if width > 0.0:
		l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l
