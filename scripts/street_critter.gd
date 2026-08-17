class_name StreetCritter
extends Sprite2D
## A purely decorative ground critter: runs in from off-screen, stops to look
## around, then runs back off and frees itself. No gameplay, no collision, no
## sound — foreground street ambience, the pavement's answer to the pigeons on
## the billboards (see BillboardBird, which this is deliberately shaped like).
##
## Driven entirely by a StreetDecor `critters` row, so the rat is not special:
## a cat, a cockroach or a stray dog is another PNG and another row.
##
## No sprite sheet. At ~10 design px tall there is nothing legible to animate
## frame by frame, so the scurry is a small vertical bob in code (`BobPx` /
## `BobHz`) and "looking around" is the bird's trick — flipping horizontally.
## That also keeps generating a new critter down to one clean side view.
##
## Art convention, same as the bird: the source faces LEFT.

## Hard ceiling on how long one critter can exist, whatever it is doing. The
## exit is a position test, and a critter that somehow never reaches its exit
## (freed camera, a Scale of 0, a pathological speed in the JSON) would
## otherwise sit there forever. Ambience is never worth a leak.
const MAX_LIFE := 20.0

enum { RUNNING_IN, LOOKING, RUNNING_OUT }

var _state := RUNNING_IN
var _speed := 60.0
var _target_x := 0.0
var _exit_x := 0.0
var _base_y := 0.0
var _pause_left := 1.0
var _next_flip := 0.5
var _bob_px := 0.0
var _bob_hz := 10.0
var _bob_t := 0.0
var _life := 0.0


## `row` is a StreetDecor critter row. `from_x`/`target_x`/`exit_x` are world
## x: where it comes in, where it stops to look, and where it is gone. `ground_y`
## is the line its feet stand on.
func configure(row: Dictionary, ground_y: float, from_x: float,
		target_x: float, exit_x: float) -> void:
	texture = StreetDecor.texture(row)
	var s := float(row.get("scale", 0.12))
	scale = Vector2(s, s)
	_target_x = target_x
	_exit_x = exit_x
	_speed = randf_range(float(row.speed_min), float(row.speed_max))
	_pause_left = randf_range(float(row.pause_min), float(row.pause_max))
	_bob_px = float(row.get("bob_px", 0.0))
	_bob_hz = float(row.get("bob_hz", 10.0))
	# Feet on the ground line, not the bounding box: the sprite is centered, so
	# the contact row sits (FootFrac - 0.5) of a height below the middle.
	var h := texture.get_height() if texture else 0
	_base_y = ground_y - (float(row.foot) - 0.5) * h * s
	position = Vector2(from_x, _base_y)
	_face_travel(_target_x - from_x)


func _process(delta: float) -> void:
	_life += delta
	if _life >= MAX_LIFE:
		queue_free()
		return
	match _state:
		RUNNING_IN:
			if _advance(delta, _target_x):
				_state = LOOKING
				_next_flip = randf_range(0.3, 0.8)
		LOOKING:
			# Stopped and glancing about. Flipping is the whole performance,
			# and it is enough at this size — it reads as a rat deciding
			# whether the street is safe.
			_pause_left -= delta
			_next_flip -= delta
			if _next_flip <= 0.0:
				flip_h = not flip_h
				_next_flip = randf_range(0.35, 0.9)
			if _pause_left <= 0.0:
				_state = RUNNING_OUT
				_face_travel(_exit_x - position.x)
		RUNNING_OUT:
			if _advance(delta, _exit_x):
				queue_free()


## Step toward `to_x`, bobbing as it goes. True once it has arrived.
func _advance(delta: float, to_x: float) -> bool:
	var dir := signf(to_x - position.x)
	position.x += dir * _speed * delta
	_bob_t += delta
	# abs(sin) rather than sin: the body lifts off the ground and comes back
	# down, never dips through it.
	position.y = _base_y - absf(sin(_bob_t * TAU * _bob_hz)) * _bob_px
	return dir == 0.0 or signf(to_x - position.x) != dir


## Source art faces left, so flip when this leg heads right.
func _face_travel(dx: float) -> void:
	flip_h = dx > 0.0
