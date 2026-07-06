class_name Hud
extends CanvasLayer
## In-game HUD: health bar, lives, score, venue banner and a big center
## label for announcements ("SURVIVE 12", "VENUE CLEARED!").

const BAR_W := 150.0

var _health_fill: ColorRect
var _lives_label: Label
var _score_label: Label
var _venue_label: Label
var _center_label: Label


func _ready() -> void:
	layer = 80
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.55)
	bar_bg.position = Vector2(10, 8)
	bar_bg.size = Vector2(BAR_W + 4, 14)
	add_child(bar_bg)
	_health_fill = ColorRect.new()
	_health_fill.color = Color(0.3, 0.9, 0.35)
	_health_fill.position = Vector2(12, 10)
	_health_fill.size = Vector2(BAR_W, 10)
	add_child(_health_fill)

	_lives_label = _label(Vector2(10, 26), 8)
	_score_label = _label(Vector2(466, 8), 8, 164, HORIZONTAL_ALIGNMENT_RIGHT)
	_venue_label = _label(Vector2(170, 8), 8, 300, HORIZONTAL_ALIGNMENT_CENTER)
	_venue_label.modulate = Color(1.0, 0.85, 0.4)
	_center_label = _label(Vector2(120, 110), 14, 400, HORIZONTAL_ALIGNMENT_CENTER)

	GameState.score_changed.connect(_on_score_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	_on_score_changed(GameState.score)
	_on_lives_changed(GameState.lives)


func bind_player(p: Fighter) -> void:
	p.health_changed.connect(_on_health_changed)
	_on_health_changed(p.health, p.max_health)


func set_venue_text(t: String) -> void:
	_venue_label.text = t


func set_center_text(t: String) -> void:
	_center_label.text = t


func _on_health_changed(current: float, maximum: float) -> void:
	var ratio := current / maxf(maximum, 1.0)
	_health_fill.size.x = BAR_W * ratio
	_health_fill.color = Color(0.9, 0.25, 0.2) if ratio < 0.3 else Color(0.3, 0.9, 0.35)


func _on_score_changed(s: int) -> void:
	_score_label.text = "SCORE %06d" % s


func _on_lives_changed(l: int) -> void:
	_lives_label.text = "LIVES x%d" % maxi(l, 0)


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
