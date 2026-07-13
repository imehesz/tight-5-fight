class_name Dancer
extends Node2D
## A modular character (body + socketed head, assembled like Fighter)
## dancing in place: random walk / arms-up poses, head glancing left and
## right. Node origin is at the character's feet.

## Dance poses: walk cycle and "hit" (arms flung up in the air).
const DANCE_ANIMS := ["walk", "hit"]

var _body: AnimatedSprite2D
var _head: Sprite2D
var _wheel: Sprite2D
var _wheel_tex: Array[Texture2D] = []
var _head_offset := Vector2.ZERO
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_dance_step)
	add_child(_timer)
	if _body:
		_dance_step()


## Apply a character entry from characters.json. Safe to call again to
## swap the previewed character in place.
func set_character(cfg: Dictionary) -> void:
	if _body:
		_body.queue_free()
		_head.queue_free()
	if _wheel:
		_wheel.queue_free()
		_wheel = null
	var chaired: bool = bool(cfg.get("inWheelchair", false))
	if chaired:
		_wheel_tex = CharacterFactory.wheelie_textures()
	if chaired and not _wheel_tex.is_empty():
		# Added before the body so the chair draws behind it.
		_wheel = Sprite2D.new()
		_wheel.texture = _wheel_tex[0]
		var ws := CharacterFactory.WHEELIE_BASE_PX \
				/ maxf(_wheel.texture.get_width(), 1.0)
		_wheel.scale = Vector2(ws, ws)
		_wheel.position = CharacterFactory.WHEELIE_POS
		add_child(_wheel)
	_body = AnimatedSprite2D.new()
	# Dancers only ever preview the player's own comedian, so they wear the
	# outfit picked in settings.
	_body.sprite_frames = CharacterFactory.body_frames(
			String(cfg.get("BodyType", "M")),
			Color.from_string(String(cfg.get("SkinColor", "")),
					CharacterFactory.DEFAULT_SKIN),
			GameState.outfit, chaired)
	_body.offset = Vector2(0, -CharacterFactory.FRAME_H / 2.0)
	_body.frame_changed.connect(_update_wheel)
	add_child(_body)

	_head = Sprite2D.new()
	_head.texture = CharacterFactory.head_texture(String(cfg.get("HeadSpritePath", "")))
	var s := Fighter.HEAD_SCALE * maxf(float(cfg.get("HeadScale", 1.0)), 0.1) \
			* (Fighter.HEAD_BASE_PX / maxf(_head.texture.get_width(), 1.0))
	_head.scale = Vector2(s, s)
	_head_offset = Vector2(float(cfg.get("HeadOffsetX", 0)), float(cfg.get("HeadOffsetY", 0)))
	add_child(_head)
	if _timer:
		_dance_step()


func _dance_step() -> void:
	var anim: String = DANCE_ANIMS.pick_random()
	_body.play(anim)
	_head.flip_h = randi() % 2 == 0
	var neck := CharacterFactory.head_offset(anim)
	var lift := _head.texture.get_height() * _head.scale.y / 2.0 - 4.0
	_head.position = Vector2(neck.x + _head_offset.x, neck.y - lift + _head_offset.y)
	_timer.start(randf_range(0.4, 0.9))


func _update_wheel() -> void:
	if _wheel:
		_wheel.texture = _wheel_tex[_body.frame % 2 if _body.animation == "walk" else 0]
