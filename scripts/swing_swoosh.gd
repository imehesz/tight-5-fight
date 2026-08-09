class_name SwingSwoosh
extends Node2D
## Overhead melee swing effect: the equipped weapon sweeping top-to-forward
## around the shoulder, plus a crescent swoosh arc with trailing follow-through
## lines. (Between swings the player carries the weapon on their back — that
## sprite lives in player.gd and hides while this one plays.)
## Fades out over the swing and frees itself. Added as a child of the
## player, so it inherits body scale and moves with them; set `facing` and
## `weapon` before add_child.

var facing := 1
## Index into the weapons.json rack. Only the art changes with it — reach, damage
## and duration are the same whatever the player picked.
var weapon := Weapons.DEFAULT
var duration := 0.2
## HELD AT FRAME ONE: set before add_child to freeze the weapon overhead at
## START_ANGLE while the player charges, with no arc drawn (there is no sweep
## to trail yet). release() lets go, and the swing plays from the top exactly
## as an uncharged one does — the sweep is never a different animation.
var charging := false
var _t := 0.0
var _weapon_sprite: Sprite2D

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

## Grip→tip is scaled to this many local px, whatever the weapon, so the
## striking tip lands right at the swoosh arc — a sword and a pool cue reach
## exactly as far as the mic stand always did (Weapons.grip_y supplies the
## texture-space y of the hand for each one).
const WEAPON_LEN := 52.0
## Weapon stays solid through this fraction of the swing, then fades fast.
const WEAPON_SOLID := 0.7
## The one tell that a charge has banked its bonus: the raised weapon warms up
## the instant it crosses Player.CHARGE_TIME, and keeps the tint through the
## sweep (the fade only touches alpha). Without it a 1.5x hit is invisible to
## the player. Drop mark_charged() to remove the tell entirely.
const CHARGED_TINT := Color(1.6, 1.35, 0.7)


func _ready() -> void:
	scale.x = float(facing)
	# Guarded like every optional asset: no import yet = swoosh only.
	var tex := Weapons.texture(weapon)
	if tex:
		_weapon_sprite = Sprite2D.new()
		_weapon_sprite.texture = tex
		var grip := Weapons.grip_y(weapon)
		var s := WEAPON_LEN / grip
		_weapon_sprite.scale = Vector2(s, s)
		# Put the grip on the pivot: offset is pre-rotation local space.
		_weapon_sprite.offset = Vector2(0, tex.get_height() / 2.0 - grip)
		_weapon_sprite.position = CENTER
		_weapon_sprite.rotation = _edge(0.0) + PI / 2.0
		add_child(_weapon_sprite)


## Let go of a held swing: the sweep starts from wherever the charge froze it,
## which is frame one, so nothing about the swing itself changes.
func release() -> void:
	charging = false


## Warm the raised weapon once the charge is worth the bonus. Only the tint is
## set — _process owns alpha, so this survives the swing's fade-out.
func mark_charged() -> void:
	if _weapon_sprite:
		_weapon_sprite.modulate = Color(CHARGED_TINT, _weapon_sprite.modulate.a)


func _process(delta: float) -> void:
	# Frozen overhead until the player lets go. The clock does not start, so
	# the swing is never shortened by however long the charge was held.
	if charging:
		return
	_t += delta
	if _t >= duration:
		queue_free()
		return
	var p := _t / duration
	if _weapon_sprite:
		# Texture points up at rotation 0, so the sweep angle needs +90°.
		_weapon_sprite.rotation = _edge(p) + PI / 2.0
		_weapon_sprite.modulate.a = 1.0 if p < WEAPON_SOLID \
				else (1.0 - p) / (1.0 - WEAPON_SOLID)
	queue_redraw()


## Leading-edge angle of the sweep at swing progress p (0..1).
func _edge(p: float) -> float:
	return lerpf(START_ANGLE, END_ANGLE, clampf(p / SWEEP_PORTION, 0.0, 1.0))


func _draw() -> void:
	# A charge shows the weapon alone: at p=0 the arcs would be a stray sliver
	# of crescent parked next to the player for as long as the button is held.
	if charging:
		return
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
