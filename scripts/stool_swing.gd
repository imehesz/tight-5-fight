class_name StoolSwing
extends Node2D
## The boss's bar-stool melee: he holds the stool overhead through the
## wind-up (the player's cue to back off), then slams it down in an arc.
## Added as a child of the Boss, so it inherits BOSS_SCALE and moves with him;
## set `facing` before add_child to mirror everything. Frees itself when done.
##
## The stool itself is a BarStool child — the same node that stands on the
## floor beside him between swings, so the prop and the weapon always match.

var facing := 1
var windup := 0.5
var sweep := 0.22
var _t := 0.0
var _stool: BarStool

## Pivot at the shoulder, matching SwingSwoosh — boss-local coords, before
## the node's 3.0 scale.
const CENTER := Vector2(0, -34)
const START_ANGLE := -PI / 2.0   # stool held straight up
const END_ANGLE := 0.5           # a touch past horizontal, into the floor
const SWOOSH := Color(1.0, 0.92, 0.75)
## Wind-up shudder: the raised stool shakes a little more as the slam nears.
const SHAKE := 0.06


func _ready() -> void:
	scale.x = float(facing)
	_stool = BarStool.new()
	_stool.position = CENTER
	add_child(_stool)
	_apply_stool_rotation()


func _process(delta: float) -> void:
	_t += delta
	if _t >= windup + sweep:
		queue_free()
		return
	_apply_stool_rotation()
	queue_redraw()


## Stool angle now. Held overhead (with a tell-tale shudder) through the
## wind-up, then swept down over `sweep` seconds.
func _angle() -> float:
	if _t < windup:
		var ramp := _t / windup
		return START_ANGLE + sin(_t * 42.0) * SHAKE * ramp
	return lerpf(START_ANGLE, END_ANGLE, (_t - windup) / sweep)


## BarStool is drawn pointing up (seat at -y), so the sweep angle needs +90°.
func _apply_stool_rotation() -> void:
	_stool.rotation = _angle() + PI / 2.0


func _draw() -> void:
	# Speed arc only during the slam itself — the wind-up has to read as a
	# pause, not as motion.
	if _t < windup:
		return
	var p := (_t - windup) / sweep
	var alpha := 1.0 - p
	var angle := _angle()
	var from: float = maxf(angle - 1.0, START_ANGLE)
	if from >= angle:
		return
	draw_arc(CENTER, BarStool.STOOL_LEN, from, angle, 20,
			Color(SWOOSH, alpha * 0.9), 3.0, true)
	draw_arc(CENTER, BarStool.STOOL_LEN - 8.0, from + 0.15, angle, 16,
			Color(SWOOSH, alpha * 0.5), 2.0, true)
