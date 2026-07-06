class_name Boss
extends Node2D
## Boss stage antagonist (the club owner). Cannot be fought or damaged —
## he throws bottles the player must survive until the timer runs out.

const BOSS_SCALE := 2.0
const HEAD_SCALE := 2.6
const TAUNTS := [
	"You call that comedy?!",
	"Get off my stage!",
	"HA! Amateur hour!",
	"I've seen funnier funerals!",
]

var target: Node2D
var throw_interval := 1.4
var active := true
var facing := -1

var _body: AnimatedSprite2D
var _head: Sprite2D
var _throw_left := 2.0
var _taunt_left := 3.0


func _ready() -> void:
	scale = Vector2(BOSS_SCALE, BOSS_SCALE)
	_body = AnimatedSprite2D.new()
	_body.sprite_frames = CharacterFactory.body_frames("M")
	_body.offset = Vector2(0, -CharacterFactory.FRAME_H / 2.0)
	_body.animation_finished.connect(func(): _body.play("idle"))
	add_child(_body)
	_body.play("idle")

	_head = Sprite2D.new()
	_head.texture = CharacterFactory.head_texture("res://assets/gen/heads/boss_lou.png")
	_head.scale = Vector2(HEAD_SCALE, HEAD_SCALE)
	add_child(_head)


func _process(delta: float) -> void:
	if is_instance_valid(target):
		facing = -1 if target.global_position.x < global_position.x else 1
	_body.flip_h = facing < 0
	_head.flip_h = facing < 0
	var neck := CharacterFactory.head_offset(_body.animation)
	var lift := 8.0 * HEAD_SCALE - 4.0
	_head.position = Vector2(neck.x * facing, neck.y - lift)

	if not active:
		return
	_throw_left -= delta
	if _throw_left <= 0.0:
		_throw_left = throw_interval * randf_range(0.7, 1.2)
		_throw()
	_taunt_left -= delta
	if _taunt_left <= 0.0:
		_taunt_left = randf_range(3.0, 6.0)
		FloatingText.spawn(get_parent(), global_position + Vector2(0, -160),
				TAUNTS.pick_random(), Color.WHITE, true)


func _throw() -> void:
	_body.play("punch")
	var b := Projectile.new()
	# Parent-space spawn point: head-high for a 1.4x fighter — over a duck,
	# into a standing face. (Standing hurtbox top ~-62, ducking ~-36.)
	b.position = position + Vector2(facing * 30, -50)
	if randf() < 0.65 or not is_instance_valid(target):
		# Head-high fastball: duck under it.
		b.velocity = Vector2(facing * randf_range(220.0, 300.0), 0.0)
	else:
		# Lobbed at the player's current spot: move away.
		var dx := target.global_position.x - global_position.x
		b.velocity = Vector2(dx * 0.9, -170.0)
		b.arc_gravity = 300.0
	get_parent().add_child(b)
