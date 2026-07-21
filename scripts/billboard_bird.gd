class_name BillboardBird
extends Sprite2D
## A purely decorative pigeon that swoops onto a billboard's top edge, sits
## for a couple of seconds glancing around (horizontal flips), then flies
## off and frees itself. No gameplay, no impressions — street ambience.
##
## Spawned by Billboard when its panel scrolls into view (70% roll, 1-3
## birds, staggered delays), parented to the tilted panel node so a perched
## bird leans with the board.
##
## Sprite sheet: shared/assets/parts/t5f-bird.png, three 96px cells facing
## left — 0 perched, 1 wings up, 2 wings down.

const TEX_PATH := "res://shared/assets/parts/t5f-bird.png"
const CELL := 96.0
## Perched bird ends up ~15px tall on the 640x360 design view.
const BIRD_SCALE := 0.24
## Perched pose's feet sit this far below the (centered) cell midpoint.
const FOOT_DROP := 31.0
const FLAP_TIME := 0.09

enum { WAITING, FLYING_IN, PERCHED, FLYING_OUT }

var _state := WAITING
var _delay := 0.0
## Bezier endpoints for the current flight leg (panel-local).
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _ctrl := Vector2.ZERO
var _t := 0.0
var _dur := 1.0
var _perch_left := 2.0
var _next_flip := 0.8
var _flap_t := 0.0
var _flap_up := true


## `surface` is the panel-local point on the frame's top edge the bird will
## stand on; `delay` staggers multiple birds so they don't arrive as one blob.
func setup(surface: Vector2, delay: float) -> void:
	texture = load(TEX_PATH)
	region_enabled = true
	scale = Vector2(BIRD_SCALE, BIRD_SCALE)
	_delay = delay
	# Feet on the surface, body center above it.
	_to = surface + Vector2(0.0, -FOOT_DROP * BIRD_SCALE)
	# Swoop in from a random side, well off the panel and higher up, dipping
	# through a control point so the approach reads as a glide, not a slide.
	var side := 1.0 if randf() < 0.5 else -1.0
	_from = _to + Vector2(side * randf_range(150.0, 230.0), -randf_range(60.0, 110.0))
	_ctrl = _from.lerp(_to, 0.5) + Vector2(0.0, randf_range(15.0, 40.0))
	_dur = randf_range(0.9, 1.3)
	_perch_left = randf_range(1.5, 4.0)
	position = _from
	visible = false
	_face_travel()
	_set_cell(1)


func _process(delta: float) -> void:
	match _state:
		WAITING:
			_delay -= delta
			if _delay <= 0.0:
				visible = true
				_state = FLYING_IN
		FLYING_IN, FLYING_OUT:
			_t += delta / _dur
			_flap(delta)
			if _t >= 1.0:
				if _state == FLYING_IN:
					_land()
				else:
					queue_free()
				return
			# Ease-out on approach, ease-in on departure — birds brake to
			# land and build speed leaving.
			var e := 1.0 - (1.0 - _t) * (1.0 - _t) if _state == FLYING_IN else _t * _t
			position = _from.bezier_interpolate(_ctrl, _ctrl, _to, e)
		PERCHED:
			_perch_left -= delta
			_next_flip -= delta
			if _next_flip <= 0.0:
				flip_h = not flip_h
				_next_flip = randf_range(0.5, 1.3)
			if _perch_left <= 0.0:
				_take_off()


func _land() -> void:
	_state = PERCHED
	position = _to
	_set_cell(0)
	_next_flip = randf_range(0.4, 1.0)


func _take_off() -> void:
	_state = FLYING_OUT
	_t = 0.0
	_from = position
	var side := 1.0 if randf() < 0.5 else -1.0
	_to = _from + Vector2(side * randf_range(150.0, 230.0), -randf_range(70.0, 120.0))
	# Control point dips below the exit line: a little hop-drop off the edge
	# before climbing away.
	_ctrl = _from.lerp(_to, 0.4) + Vector2(0.0, randf_range(5.0, 18.0))
	_dur = randf_range(0.8, 1.1)
	_face_travel()


func _flap(delta: float) -> void:
	_flap_t += delta
	if _flap_t >= FLAP_TIME:
		_flap_t = 0.0
		_flap_up = not _flap_up
	_set_cell(1 if _flap_up else 2)


## Sheet faces left; flip when this flight leg heads right.
func _face_travel() -> void:
	flip_h = _to.x > _from.x


func _set_cell(i: int) -> void:
	region_rect = Rect2(i * CELL, 0.0, CELL, CELL)
