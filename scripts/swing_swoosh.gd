class_name SwingSwoosh
extends Node2D
## Overhead mic-stand swing effect: the stand sweeping top-to-forward around
## the shoulder, plus a crescent swoosh arc with trailing follow-through
## lines. (Between swings the player carries the stand on their back — that
## sprite lives in player.gd and hides while this one plays.)
## Fades out over the swing and frees itself. Added as a child of the
## player, so it inherits body scale and moves with them; set `facing`
## before add_child to mirror everything.

var facing := 1
var duration := 0.2
var _t := 0.0
var _stand: Sprite2D

## Pivot sits at the shoulder; radius roughly matches the swing hitbox reach
## (local coords, before the fighter's BODY_SCALE).
const CENTER := Vector2(0, -34)
const RADIUS := 50.0
const START_ANGLE := -PI / 2.0   # straight up (overhead)
const END_ANGLE := 0.35          # a touch past horizontal, into the floor
## The blade edge finishes its sweep at this fraction of the swing; the rest
## of the time only the fade plays out (the "follow through").
const SWEEP_PORTION := 0.6
const TRAIL := 1.1               # radians of arc trailing behind the edge
const COLOR := Color(1.0, 1.0, 0.88)

const STAND_TEX := "res://shared/assets/parts/weapon_mic-in-stand_small.png"
## Texture-space y of the hand grip, just above the base plate (mic head is
## the striking tip at y 0). Grip→tip is scaled to STAND_LEN local px so the
## mic head lands right at the swoosh arc.
const GRIP_Y := 780.0
const STAND_LEN := 52.0
## Stand stays solid through this fraction of the swing, then fades fast.
const STAND_SOLID := 0.7


func _ready() -> void:
	scale.x = float(facing)
	# Guarded like every optional asset: no import yet = swoosh only.
	if ResourceLoader.exists(STAND_TEX):
		_stand = Sprite2D.new()
		_stand.texture = load(STAND_TEX)
		var s := STAND_LEN / GRIP_Y
		_stand.scale = Vector2(s, s)
		# Put the grip on the pivot: offset is pre-rotation local space.
		_stand.offset = Vector2(0, _stand.texture.get_height() / 2.0 - GRIP_Y)
		_stand.position = CENTER
		_stand.rotation = _edge(0.0) + PI / 2.0
		add_child(_stand)


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	var p := _t / duration
	if _stand:
		# Texture points up at rotation 0, so the sweep angle needs +90°.
		_stand.rotation = _edge(p) + PI / 2.0
		_stand.modulate.a = 1.0 if p < STAND_SOLID \
				else (1.0 - p) / (1.0 - STAND_SOLID)
	queue_redraw()


## Leading-edge angle of the sweep at swing progress p (0..1).
func _edge(p: float) -> float:
	return lerpf(START_ANGLE, END_ANGLE, clampf(p / SWEEP_PORTION, 0.0, 1.0))


func _draw() -> void:
	var p := _t / duration
	var alpha := 1.0 - p
	var edge := _edge(p)
	# Main crescent plus two thinner inner arcs with shorter tails — the
	# classic layered speed-line look.
	_arc(RADIUS, edge, TRAIL, 3.0, alpha)
	_arc(RADIUS - 7.0, edge - 0.12, TRAIL * 0.6, 2.0, alpha * 0.7)
	_arc(RADIUS - 14.0, edge - 0.24, TRAIL * 0.35, 1.5, alpha * 0.45)
	# Short skid ticks flying off the leading edge.
	for i in 3:
		var a := edge - 0.05 * i
		var dir := Vector2(cos(a), sin(a))
		draw_line(CENTER + dir * (RADIUS + 3.0),
				CENTER + dir * (RADIUS + 9.0 + 3.0 * i),
				Color(COLOR, alpha * 0.8), 1.5, true)


func _arc(radius: float, edge: float, trail: float, width: float,
		alpha: float) -> void:
	var from: float = maxf(edge - trail, START_ANGLE - 0.15)
	if from >= edge:
		return
	draw_arc(CENTER, radius, from, edge, 20, Color(COLOR, alpha), width, true)
