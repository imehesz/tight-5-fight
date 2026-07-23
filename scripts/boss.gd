class_name Boss
extends Node2D
## Boss stage antagonist (the club owner). Cannot be fought or damaged by
## melee — he throws bottles the player must survive until the timer runs
## out. A thrown beer bottle staggers him (see stagger()), and walking into
## his reach gets you a bar stool to the head (see _try_stool()).

## 3.0 = the previous 2.0 bumped ×1.5 alongside the venue FIGHTER_SCALE bump, so
## the boss keeps towering over the comedians (same ~1.34× ratio) instead of
## looking tiny next to them. Body, head, resting stool, swung stool and the
## stool hitbox are all children of this node, so they grow with it in one shot.
## Bottle trajectory is deliberately UNAFFECTED: throws spawn in scene space off
## boss.position with literal offsets, and fastball height derives from the
## player's scale (see _throw / _fastball_y) — neither reads BOSS_SCALE.
const BOSS_SCALE := 3.0
const HEAD_SCALE := 2.6
const TAUNTS := [
	"You call that comedy?!",
	"Get off my stage!",
	"HA! Amateur hour!",
	"I've seen funnier funerals!",
]

## --- Bottle stagger (Phase 5) ---
const STAGGER_S := 2.0        # throws nothing while staggered
const STAGGER_IMMUNE_S := 2.0 # after recovering, immune this long
const STAGGER_POINTS := 150
const STAGGER_LINES := ["MY EYE!", "WHY YOU LITTLE--", "OW! SECURITY!"]

## --- Bar stool melee ---
## The boss doesn't chase; the stool is what happens if you crowd him. It
## hits ducking players too (it comes down on the floor), so the counter is
## backing off during the wind-up, not ducking under it.
const STOOL_DAMAGE := Player.SWING_DAMAGE  # same punch as the mic stand
const STOOL_RANGE := 117.0    # parent-space distance that provokes a swing
							  # (78 ×1.5, tracking the stool box's BOSS_SCALE
							  #  bump — the live hitbox reaches ~129px, so every
							  #  provoked swing still connects)
const STOOL_WINDUP := 0.5     # telegraph: stool up, player's cue to retreat
const STOOL_SWEEP := 0.22     # hitbox is live for this long
const STOOL_RECOVER := 0.35   # helpless tail after the slam
const STOOL_COOLDOWN := 2.2
const STOOL_BOX_SIZE := Vector2(34, 46)
const STOOL_BOX_X := 26.0
## Where the stool waits between swings: on the floor beside his body, on the
## side AWAY from the room, so it never sits on top of the fight. Local px — the
## 3.0 node scale triples it, and the boss spawns ~100px from the screen edge,
## so this is pulled in from 30 to keep the tripled prop fully on-screen instead
## of clipping half off the edge (still just past the 32px-wide body base).
const STOOL_REST_X := 20.0
const STOOL_LINES := ["OUTTA MY CLUB!", "SIT DOWN!", "LAST CALL!"]

var target: Node2D
var throw_interval := 1.4
## The venue flips this off on victory. Doing it through a setter guarantees
## an in-flight stool swing can't leave its hitbox armed through the
## "YOU SURVIVED!" beat.
var active := true:
	set(value):
		active = value
		if not value:
			_cancel_stool()
var facing := -1

var _body: AnimatedSprite2D
var _head: Sprite2D
var _throw_left := 2.0
var _taunt_left := 3.0
var _stagger_left := 0.0
var _no_stagger_left := 0.0   # stagger + immunity countdown (anti chain-stun)
var _stool_left := 0.0        # whole swing: windup + sweep + recover
var _stool_cooldown := 0.0
var _stool_box: Area2D
var _stool_hit := false       # one victim per swing
var _rest_stool: BarStool     # the prop on the floor between swings


func _ready() -> void:
	scale = Vector2(BOSS_SCALE, BOSS_SCALE)
	_body = AnimatedSprite2D.new()
	_body.sprite_frames = CharacterFactory.body_frames("M")
	_body.offset = Vector2(0, -CharacterFactory.FRAME_H / 2.0)
	_body.animation_finished.connect(func(): _body.play("idle"))
	add_child(_body)
	_body.play("idle")

	_head = Sprite2D.new()
	_head.texture = CharacterFactory.head_texture(GameState.boss_head_path())
	_head.scale = Vector2(HEAD_SCALE, HEAD_SCALE)
	add_child(_head)

	_build_hurtbox()
	_build_stool_box()
	_build_rest_stool()


## The stool standing on the floor beside him, visible from the moment the
## fight opens so the melee is telegraphed as scenery before it's ever used.
## Placed on the side away from the room center (i.e. behind him), which is
## knowable here because the venue sets our position before add_child().
func _build_rest_stool() -> void:
	_rest_stool = BarStool.new()
	var center_x := get_viewport().get_visible_rect().size.x / 2.0
	var away := 1.0 if global_position.x > center_x else -1.0
	# Drawn behind the body (child index 0) so he stands in front of it.
	_rest_stool.position = Vector2(STOOL_REST_X * away, 0.0)
	add_child(_rest_stool)
	move_child(_rest_stool, 0)


## Lets PLAYER bottles find him (layer 4 is what hits_enemies projectiles
## scan). Melee is unaffected: the meta key is "boss", not "fighter", so
## Fighter's hitbox handler ignores it — he still can't be punched.
func _build_hurtbox() -> void:
	var hurtbox := Area2D.new()
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false  # others detect US; we detect nothing
	hurtbox.set_meta("boss", self)
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 44)
	cs.shape = rect
	cs.position = Vector2(0, -22)
	hurtbox.add_child(cs)
	add_child(hurtbox)


## The stool's strike zone, armed only during the sweep. Mask 2 = the player's
## hurtbox layer, and the box is tall enough to catch a ducking player.
func _build_stool_box() -> void:
	_stool_box = Area2D.new()
	_stool_box.collision_layer = 0
	_stool_box.collision_mask = 2
	_stool_box.monitoring = false
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = STOOL_BOX_SIZE
	cs.shape = rect
	_stool_box.add_child(cs)
	_stool_box.position = Vector2(STOOL_BOX_X, -STOOL_BOX_SIZE.y / 2.0)
	_stool_box.area_entered.connect(_on_stool_area_entered)
	add_child(_stool_box)


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

	# Staggered: no throwing, no taunting, no stool — just the wobble.
	if _no_stagger_left > 0.0:
		_no_stagger_left -= delta
	if _stagger_left > 0.0:
		_stagger_left -= delta
		if _stagger_left <= 0.0:
			_body.rotation = 0.0
		else:
			_body.rotation = sin(Time.get_ticks_msec() * 0.03) * 0.12
			return

	# A swing in progress owns the boss until it finishes.
	if _stool_left > 0.0:
		_tick_stool(delta)
		return
	if _stool_cooldown > 0.0:
		_stool_cooldown -= delta
	elif _player_in_stool_range():
		_start_stool()
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


## A player bottle connected. Returns true if the boss actually staggered
## (caller awards points on true; a *clink* on false).
func stagger() -> bool:
	if not active or _no_stagger_left > 0.0:
		return false
	_stagger_left = STAGGER_S
	_no_stagger_left = STAGGER_S + STAGGER_IMMUNE_S
	# A bottle to the head drops the stool: cancel any swing in flight.
	_cancel_stool()
	_body.play("hit")
	GameState.request_shake(3.0)
	FloatingText.spawn(get_parent(), global_position + Vector2(0, -160),
			STAGGER_LINES.pick_random(), Color.WHITE, true)
	return true


# ---------------------------------------------------------------- stool
func _player_in_stool_range() -> bool:
	if not is_instance_valid(target):
		return false
	# Dead/respawning players are not worth swinging at.
	if target is Fighter and target.state == Fighter.FState.DEAD:
		return false
	return absf(target.global_position.x - global_position.x) <= STOOL_RANGE


func _start_stool() -> void:
	_stool_left = STOOL_WINDUP + STOOL_SWEEP + STOOL_RECOVER
	_stool_cooldown = STOOL_COOLDOWN
	_stool_hit = false
	# He picks it up: the floor prop vanishes for as long as it's in his
	# hands, so there's never a second stool on screen.
	if _rest_stool:
		_rest_stool.visible = false
	_body.play("punch")
	GameState.play_sfx("swing" if GameState.has_sfx("swing") else "throw")
	FloatingText.spawn(get_parent(), global_position + Vector2(0, -160),
			STOOL_LINES.pick_random(), Color.WHITE, true)
	var sw := StoolSwing.new()
	sw.facing = facing
	sw.windup = STOOL_WINDUP
	sw.sweep = STOOL_SWEEP
	add_child(sw)


## Runs the windup → sweep → recover clock and arms the hitbox for the sweep.
func _tick_stool(delta: float) -> void:
	var elapsed := (STOOL_WINDUP + STOOL_SWEEP + STOOL_RECOVER) - _stool_left
	_stool_left -= delta
	if _stool_left <= 0.0:
		_cancel_stool()
		return
	var live := elapsed >= STOOL_WINDUP and elapsed < STOOL_WINDUP + STOOL_SWEEP
	if live and not _stool_hit:
		# Facing is locked at the wind-up, so a player who runs past mid-swing
		# doesn't get hit by a stool that magically turns around.
		_stool_box.position.x = STOOL_BOX_X * facing
		_stool_box.set_deferred("monitoring", true)
	else:
		_stool_box.set_deferred("monitoring", false)


## Ends a swing — on recovery, on a stagger, or when the venue deactivates
## him. Either way the stool goes back on the floor.
func _cancel_stool() -> void:
	_stool_left = 0.0
	if _stool_box:
		_stool_box.set_deferred("monitoring", false)
	if _rest_stool:
		_rest_stool.visible = true
	for c in get_children():
		if c is StoolSwing:
			c.queue_free()


func _on_stool_area_entered(area: Area2D) -> void:
	if _stool_hit or not area.has_meta("fighter"):
		return
	_stool_hit = true
	_stool_box.set_deferred("monitoring", false)
	var f: Fighter = area.get_meta("fighter")
	f.take_hit(STOOL_DAMAGE, global_position.x)
	GameState.request_shake(5.0)
	GameState.play_crowd("laugh")
	GameState.crowd_reaction.emit("laugh")


func _throw() -> void:
	_body.play("punch")
	GameState.play_sfx("throw")
	var b := Projectile.new()
	if randf() < 0.65 or not is_instance_valid(target):
		# Head-high fastball: duck under it.
		b.position = Vector2(position.x + facing * 30, _fastball_y())
		b.velocity = Vector2(facing * randf_range(220.0, 300.0), 0.0)
	else:
		# Lobbed at the player's current spot: move away.
		b.position = position + Vector2(facing * 30, -50)
		var dx := target.global_position.x - global_position.x
		b.velocity = Vector2(dx * 0.9, -170.0)
		b.arc_gravity = 300.0
	get_parent().add_child(b)


## Parent-space height that clears a ducking player but meets a standing one:
## midway between the two hurtbox tops. The rects are fighter-local, so they
## have to be scaled by the player's own scale (BODY_SCALE * size_scale).
func _fastball_y() -> float:
	if not is_instance_valid(target):
		return position.y - 50.0
	var s: float = target.scale.y
	var stand_top: float = target.position.y + Fighter.STAND_BOX.position.y * s
	var duck_top: float = target.position.y + Fighter.DUCK_BOX.position.y * s
	return (stand_top + duck_top) * 0.5
