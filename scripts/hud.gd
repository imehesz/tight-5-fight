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
## Seconds BURNED (the bomb) do the same in reverse, and louder: the box goes
## hot red and holds it longer than a gain, because losing 30 is the biggest
## thing that can happen to the clock.
const CLOCK_LOSS := Color(0.95, 0.15, 0.12)
const CLOCK_LOSS_S := 0.9
const CLOCK_LOSS_POP := 1.6
## KAREN'S COMPLAINT: with the clock burning down past CAMEO_AT, the
## neighborhood Karen slides in from the left, hollers, and leaves. Fires ONCE
## per crossing — banking bonus time back over the line re-arms her, so a run
## that keeps earning seconds gets yelled at again on the way back down.
## She is looked up by CharacterId, and a game whose roster has no Karen (as
## celebs and killers do not) simply never sees her.
const CAMEO_ID := "a-karen"
## Broken over three lines so the shout reads as a comic panel rather than one
## long ribbon — at this font size a single line would be most of the screen.
const CAMEO_TEXT := "YOU ARE\nBURNING\nTHE LIGHT!!"
## Ship value: she hollers with 30 seconds left on the clock, when the light
## really is burning. (During testing this sat at 270.0 — 4:30 — so she showed
## up 30 seconds INTO a run instead of 30 seconds before the end of one.)
const CAMEO_AT := 30.0
const CAMEO_HEAD := 168.0
const CAMEO_FONT := 24
## Slide in fast, hold long enough to read 26 characters, slide back out.
const CAMEO_IN := 0.3
const CAMEO_HOLD := 1.8
const CAMEO_OUT := 0.25
## PAUSE button, right edge under the score (and under the streak chip, which
## shares that corner). Plain theme gray like every other button in the app;
## the glyph is drawn rather than typed, so it is the chunky universal pause
## mark at any size instead of two thin pipes from the pixel font.
const PAUSE_SIZE := Vector2(44, 44)
const PAUSE_TOP := 42.0
const PAUSE_MARGIN := 10.0

## The two bars of the universal pause mark, drawn to the button's size and
## passing every click through to the Button underneath (same trick as the
## share glyph in menu_base.gd).
class PauseIcon extends Control:
	const INK := Color(0.92, 0.92, 0.95)
	const BAR_W := 0.16  # of the control's width
	const BAR_H := 0.42  # of its height
	const GAP := 0.12

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x * BAR_W
		var h := size.y * BAR_H
		var gap := size.x * GAP
		var y := (size.y - h) / 2.0
		var x := (size.x - (w * 2.0 + gap)) / 2.0
		draw_rect(Rect2(x, y, w, h), INK)
		draw_rect(Rect2(x + w + gap, y, w, h), INK)


var _health_fill: ColorRect
var _lives_label: Label
var _bosses_label: Label
var _score_label: Label
var _streak_label: Label
var _venue_label: Label
var _clock_panel: Panel
var _clock_style: StyleBoxFlat
var _clock_label: Label
var _pause_btn: Button
## Seconds left on the green "+Ns" flash; 0 when the box is showing its
## normal countdown color.
var _clock_gain := 0.0
var _clock_loss := 0.0
var _center_label: Label
var _portrait: TextureRect
var _portrait_style: StyleBoxFlat
var _flip_timer: Timer
var _player: Fighter
## -1 = not seeded yet: the first signal after _ready() sets the baseline
## without flying (a fresh HUD mid-run must not replay the whole score).
var _last_score := -1
var _last_lives := -1
## False once Karen has been shown for this trip below CAMEO_AT; true again
## when bonus time lifts the clock back over it. Seeded in _ready() from the
## clock as it stands, so the fresh HUD built on every venue entry doesn't
## re-fire her for a run that is already past the line.
var _cameo_armed := true
## The cameo currently on screen, so a second crossing while she is still
## sliding (bonus time then a bomb, inside two seconds) doesn't stack a second
## Karen on top of the first.
var _cameo_node: Control


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
	_build_pause_button()
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
	GameState.time_lost.connect(_on_time_lost)
	_on_score_changed(GameState.score)
	_on_lives_changed(GameState.lives)
	_on_bosses_changed(GameState.bosses_defeated)
	_on_streak_changed(GameState.streak, GameState.streak_mult())
	_cameo_armed = GameState.run_time_left > CAMEO_AT


## The streak window can lapse with no KO to signal it, so visibility is
## polled here rather than driven by streak_changed alone.
func _process(delta: float) -> void:
	_streak_label.visible = GameState.streak_active()
	_clock_gain = maxf(_clock_gain - delta, 0.0)
	_clock_loss = maxf(_clock_loss - delta, 0.0)
	_update_clock()
	_check_cameo()


## Pinned to the LIVE right edge with the same 10px margin the score keeps, so
## it stays under the score on any width.
func _build_pause_button() -> void:
	_pause_btn = Button.new()
	_pause_btn.custom_minimum_size = PAUSE_SIZE
	MenuBase.set_tip(_pause_btn, "Pause")
	_pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_btn.offset_left = -PAUSE_MARGIN - PAUSE_SIZE.x
	_pause_btn.offset_right = -PAUSE_MARGIN
	_pause_btn.offset_top = PAUSE_TOP
	_pause_btn.offset_bottom = PAUSE_TOP + PAUSE_SIZE.y
	# The shared gray skin, so it wears the same rounded corners and tube
	# border as every other button in the app instead of the default theme's.
	MenuBase.style_gray_button(_pause_btn)
	_pause_btn.pressed.connect(_on_pause)
	add_child(_pause_btn)
	var icon := PauseIcon.new()
	# anchors AND offsets — anchors alone leaves the old offsets behind.
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_btn.add_child(icon)


## Freeze the game behind the same popup the doorway lesson uses — the click
## SFX goes first, since pausing mutes the buses it would play on. The HUD is
## pausable, so this button goes inert the moment it fires: the popup's BACK
## button is the only way back, exactly like every other popup.
func _on_pause() -> void:
	if GameState.game_paused:
		return
	GameState.play_sfx("click")
	var popup := HintPopup.new()
	popup.title_text = "GAME PAUSED"
	GameState.set_paused(true)
	add_child(popup)


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


## Burned seconds (a bomb landed on the player): the same flight in reverse
## colors, and it OUTRANKS a gain flash — a box caught in the same instant the
## bomb went off must not paint the loss green.
func _on_time_lost(seconds: float) -> void:
	_clock_loss = CLOCK_LOSS_S
	_clock_gain = 0.0
	_fly_gain("-%ds" % seconds, CLOCK_LOSS,
			_clock_panel.get_global_rect().get_center())


func _update_clock() -> void:
	var left := GameState.run_time_left
	_clock_label.text = GameState.time_text()
	if _clock_loss > 0.0:
		_clock_style.bg_color = CLOCK_LOSS
	elif _clock_gain > 0.0:
		_clock_style.bg_color = CLOCK_GAIN
	else:
		_clock_style.bg_color = _clock_color(left)
	# Under 0:05 the whole box swells, with a small pop on each second tick
	# that eases back down — the last five seconds should feel like a hook.
	var scale_now := 1.0
	if left <= CLOCK_PANIC_AT:
		scale_now = CLOCK_PANIC_SCALE * (1.0 + 0.09 * fmod(left, 1.0))
	# The gain pop rides on top of whatever scale the countdown asked for, so
	# banking time in the last five seconds still reads.
	if _clock_gain > 0.0:
		scale_now *= 1.0 + (CLOCK_GAIN_POP - 1.0) * (_clock_gain / CLOCK_GAIN_S)
	if _clock_loss > 0.0:
		scale_now *= 1.0 + (CLOCK_LOSS_POP - 1.0) * (_clock_loss / CLOCK_LOSS_S)
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


# --------------------------------------------------------------- Karen cameo
## Polled alongside the clock rather than hung off a signal: the countdown has
## no per-second tick to listen to, and polling is what makes banked time
## re-arm her for free — cross the line going up, get yelled at again coming
## back down.
func _check_cameo() -> void:
	if GameState.run_time_left > CAMEO_AT:
		_cameo_armed = true
		return
	if not _cameo_armed or GameState.time_up():
		return
	_cameo_armed = false
	_play_cameo()


## Karen slides in from the left edge at mid-height, hollers, and leaves.
## Purely decorative: nothing here touches the clock, the player or input.
func _play_cameo() -> void:
	if is_instance_valid(_cameo_node):
		return  # she is still out there hollering about the last one
	var idx := GameState.character_index_by_id(CAMEO_ID)
	if idx < 0 or bool(GameState.characters[idx].get("isDisabled", false)):
		return  # this game's roster has no Karen, or has her benched

	# Anchored to the LIVE left-center: the project scales with aspect
	# "expand", so the viewport is routinely taller or wider than the 640x360
	# design and a baked y would drift off center.
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	_cameo_node = anchor
	# One node carries head + bubble so the pair slides as a unit, and only
	# its x is ever tweened.
	var slider := Control.new()
	slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(slider)

	var face := TextureRect.new()
	# expand_mode BEFORE texture/size, same trap as the portrait: a 200x200
	# head would otherwise pin the control's minimum size for good.
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture = CharacterFactory.head_texture(
			String(GameState.characters[idx].get("HeadSpritePath", "")))
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.position = Vector2(0, -CAMEO_HEAD / 2.0)
	face.size = Vector2(CAMEO_HEAD, CAMEO_HEAD)
	slider.add_child(face)

	var bubble := Label.new()
	bubble.text = CAMEO_TEXT
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Ragged-right would read as a mistake across three lines of different
	# lengths; comic bubbles center.
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.add_theme_font_size_override("font_size", CAMEO_FONT)
	FloatingText.style_bubble(bubble)  # the same bubble the hecklers shout in
	slider.add_child(bubble)
	bubble.reset_size()
	# Beside her at mouth height, overlapping the head a little the way a
	# comic tail would.
	bubble.position = Vector2(CAMEO_HEAD - 8.0, -bubble.size.y / 2.0)

	# Parked exactly its own width off the left edge, so she is never a sliver
	# hanging in frame however wide the phone is.
	var span := CAMEO_HEAD + bubble.size.x
	slider.position.x = -span
	var tw := slider.create_tween()
	tw.tween_property(slider, "position:x", 4.0, CAMEO_IN) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(CAMEO_HOLD)
	tw.tween_property(slider, "position:x", -span, CAMEO_OUT) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_end_cameo)


func _end_cameo() -> void:
	if is_instance_valid(_cameo_node):
		_cameo_node.queue_free()
	_cameo_node = null


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
