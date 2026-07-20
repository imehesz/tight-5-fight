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

var _health_fill: ColorRect
var _lives_label: Label
var _bosses_label: Label
var _score_label: Label
var _streak_label: Label
var _venue_label: Label
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
	_center_label = _label(Vector2(0, 110), 14, 400, HORIZONTAL_ALIGNMENT_CENTER)
	_center_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_center_label.offset_left = -200.0
	_center_label.offset_right = 200.0
	_center_label.offset_top = 110.0

	GameState.score_changed.connect(_on_score_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.bosses_changed.connect(_on_bosses_changed)
	GameState.streak_changed.connect(_on_streak_changed)
	_on_score_changed(GameState.score)
	_on_lives_changed(GameState.lives)
	_on_bosses_changed(GameState.bosses_defeated)
	_on_streak_changed(GameState.streak, GameState.streak_mult())


## The streak window can lapse with no KO to signal it, so visibility is
## polled here rather than driven by streak_changed alone.
func _process(_delta: float) -> void:
	_streak_label.visible = GameState.streak_active()


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
