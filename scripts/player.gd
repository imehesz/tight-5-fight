class_name Player
extends Fighter
## The chosen comedian. Reads input actions (shared by keyboard and the
## on-screen touch controls) and emits interact_pressed for door entry.

signal interact_pressed

## Baseline walk speed; plane drops nudge it via apply_speed_effect().
const BASE_SPEED := 140.0

## Melee swing: an overhead hit with double the punch/kick reach, gated by a
## cooldown (punch/kick have none). Damage is kick +15%. During the swing
## SwingSwoosh draws the weapon + arc; between swings the weapon rides on the
## player's back (see CARRY_* below). Which weapon is pure cosmetics — these
## numbers are the same for the mic stand and the chainsaw alike.
const SWING_DAMAGE := KICK_DAMAGE * 1.15
const SWING_COOLDOWN := 1.5
const SWING_TIME := 0.25
## CHARGED SWING. The swing fires on RELEASE, not press: holding the button
## freezes the weapon overhead at frame one of the sweep, and letting go drops
## it. A tap therefore still swings immediately. Hold past CHARGE_TIME and the
## same swing — same reach, same cooldown, same art — lands for CHARGE_MULT
## damage. A charge can only be STARTED off cooldown; the cooldown itself is
## dead time as it always was.
const CHARGE_TIME := 1.0
const CHARGE_MULT := 1.5
## How much further a charged hit throws its victim, as a multiple of the
## normal recoil DISTANCE (~6px, see Fighter.KNOCKBACK) — so 4.0 is ~24px, a
## shove that reads across the room. Push it much past here and the skid stops
## fitting inside the 0.33s hit animation: the victim would still be sliding
## when they recover, and apply_locomotion would cut the launch short.
const CHARGE_KNOCKBACK := 4.0
## Safety valve, not a design limit: the bonus caps at CHARGE_TIME anyway, so
## nothing is lost by swinging for the player if the release event never
## arrives (a web build losing focus mid-hold would otherwise freeze them
## overhead forever).
const CHARGE_MAX := 2.5
## Punch hitbox reaches ~29px from center (18 + 22/2); this box ends at ~58.
const SWING_BOX_SIZE := Vector2(48, 20)
const SWING_BOX_X := 34.0
## The weapon rides on the player's back between swings: slung diagonally,
## striking end poking up behind the shoulder, drawn behind the body sprite.
## Every weapon sprite shares one canvas (see Weapons), so one length fits all.
const CARRY_POS := Vector2(-5, -26)  # sprite center, x mirrors with facing
const CARRY_TILT := 0.4              # radians off vertical, toward the back
const CARRY_LEN := 47.6              # full weapon height in local px
## What holds that weapon up: a leather strap over the back-side shoulder,
## running down across the chest to the front-side hip — so it leans the same
## way as the weapon behind it, and mirrors when the player turns around.
## Endpoints are relative to the animation's neck anchor (CharacterFactory
## .HEAD_OFFSETS), which is what makes the strap ride the torso through the
## walk bob, the punch lean and the hit recoil without per-frame tuning. X
## mirrors with facing, exactly like the head and the stand.
const STRAP_COLOR := Color(0.42, 0.26, 0.14)
const STRAP_WIDTH := 2.0
## Endpoints verified against every frame of both body sheets: the band stays
## on shirt pixels throughout. Pushing the bottom out to x=4 puts the tip on
## the forearm during walk frame 2, where the near arm swings across the hip.
const STRAP_TOP := Vector2(-5, 4)
const STRAP_BOTTOM := Vector2(3, 16)
## Ducking squashes the torso to roughly half its standing height (chest rows
## end 6px above the hips), so the strap needs its own shorter run or it would
## trail off the shirt and onto the legs.
const STRAP_DUCK_TOP := Vector2(-5, 3)
const STRAP_DUCK_BOTTOM := Vector2(4, 11)

## Brief lock while the throw animation plays, so the player can't walk or
## re-throw mid-toss (the melee state machine is untouched — no punch damage).
var _throw_lock := 0.0
var _speed_timer := 0.0
var _swing_lock := 0.0
var _swing_cooldown := 0.0
var _swing_box: Area2D
## Charge in progress: how long the button has been held, and the raised
## weapon waiting on it (the same SwingSwoosh that will play the sweep).
var _charging := false
var _charge_t := 0.0
var _charge_swoosh: SwingSwoosh
var _carried_weapon: Sprite2D
var _chest_strap: Line2D


func _init() -> void:
	hurt_layer = 2
	attack_mask = 4
	move_speed = BASE_SPEED
	# Here rather than at each spawn site, so no scene can forget it.
	outfit = GameState.outfit


func _ready() -> void:
	super()
	# Lets in-flight boss bottles find the player for the close-call check.
	add_to_group("player")
	_build_swing_box()
	_build_carried_weapon()
	_build_chest_strap()


## The between-swings weapon on the back. Child index 0 keeps it behind the
## body/head sprites without z_index (negative z would drop it behind the
## scene background, which draws at z 0).
func _build_carried_weapon() -> void:
	var tex := Weapons.texture(GameState.weapon)
	if tex == null:
		return
	_carried_weapon = Sprite2D.new()
	_carried_weapon.texture = tex
	# Off the full canvas height, not the art inside it, so every weapon hangs
	# the same length on the back no matter what its silhouette is.
	var s := CARRY_LEN / tex.get_height()
	_carried_weapon.scale = Vector2(s, s)
	_carried_weapon.position = CARRY_POS
	add_child(_carried_weapon)
	move_child(_carried_weapon, 0)


## The strap sits in front of the body sprite (the weapon behind it), so it
## reads as worn rather than floating. Placed by index for the same reason
## _build_carried_weapon() uses index 0: negative z_index would sink it behind
## the scene background.
func _build_chest_strap() -> void:
	_chest_strap = Line2D.new()
	_chest_strap.width = STRAP_WIDTH
	_chest_strap.default_color = STRAP_COLOR
	# Flat caps and no AA — a soft, rounded band would read as a smear next
	# to art drawn on a 2px grid.
	_chest_strap.begin_cap_mode = Line2D.LINE_CAP_NONE
	_chest_strap.end_cap_mode = Line2D.LINE_CAP_NONE
	_chest_strap.antialiased = false
	add_child(_chest_strap)
	move_child(_chest_strap, body_sprite.get_index() + 1)


func _process(delta: float) -> void:
	super(delta)
	if _carried_weapon:
		# Hidden while the SwingSwoosh draws its own copy — through the charge
		# as well as the swing, or the weapon would be in two places at once —
		# and on defeat (a floating diagonal weapon over a lying body looks
		# wrong).
		_carried_weapon.visible = _swing_lock <= 0.0 and not _charging \
				and state != FState.DEAD
		_carried_weapon.position.x = CARRY_POS.x * facing
		_carried_weapon.flip_h = facing < 0
		# The half-turn for a handle-up weapon rides on top of the tilt, so it
		# stays on the strap's diagonal and only swaps which end clears the
		# shoulder. Mirrors correctly as-is: negating the tilt and adding PI is
		# the same angle as negating the whole thing, one turn around.
		_carried_weapon.rotation = -CARRY_TILT * facing + Weapons.carry_spin(GameState.weapon)
	if _chest_strap:
		# Worn through the swing (the weapon leaves, the strap stays), dropped
		# only on defeat — the defeated frame lies the body down sideways, so
		# a chest-height diagonal would hang in the air.
		_chest_strap.visible = state != FState.DEAD
		if _chest_strap.visible:
			var ducking := body_sprite.animation == "duck"
			var top := STRAP_DUCK_TOP if ducking else STRAP_TOP
			var bottom := STRAP_DUCK_BOTTOM if ducking else STRAP_BOTTOM
			var neck := CharacterFactory.head_offset(body_sprite.animation)
			_chest_strap.points = PackedVector2Array([
				Vector2((neck.x + top.x) * facing, neck.y + top.y),
				Vector2((neck.x + bottom.x) * facing, neck.y + bottom.y),
			])


## Separate hitbox for the melee swing so the shared punch/kick hitbox
## (and everyone's hurtboxes) keep their tuned sizes untouched.
func _build_swing_box() -> void:
	_swing_box = Area2D.new()
	_swing_box.collision_layer = 0
	_swing_box.collision_mask = attack_mask
	_swing_box.monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SWING_BOX_SIZE
	shape.shape = rect
	_swing_box.add_child(shape)
	_swing_box.position = Vector2(SWING_BOX_X, -30)
	# Reuses Fighter's victim/damage plumbing, same as punch and kick.
	_swing_box.area_entered.connect(_on_hitbox_area_entered)
	add_child(_swing_box)


## Temporary speed modifier from plane drops: bomb slow (0.75) or good-set-box
## boost (1.25). A fresh effect replaces whatever is running outright.
func apply_speed_effect(mult: float, duration: float) -> void:
	move_speed = BASE_SPEED * mult
	_speed_timer = duration


## THE "player got hit" hook — Phase 2's crowd boo goes in here too, don't
## add a second override. Any damage (melee or bottle) breaks the KO streak;
## death passes through here as well, so no separate death hook is needed.
func take_hit(damage: float, from_x: float, knockback := 1.0) -> void:
	GameState.reset_streak()
	# Getting hit interrupts a swing in progress (the cooldown still runs).
	if _swing_lock > 0.0:
		_swing_lock = 0.0
		_swing_box.set_deferred("monitoring", false)
	# A charge is broken outright — but no swing happened, so no cooldown is
	# charged for it either: the player can wind up again the moment they
	# recover. Standing still holding a weapon overhead is punishment enough.
	_cancel_charge()
	super(damage, from_x, knockback)


## Dropped mid-charge: clear the raised weapon with the body, or it hangs in
## the air over the defeated frame.
func _die() -> void:
	_cancel_charge()
	super()


func _physics_process(delta: float) -> void:
	if state == FState.DEAD:
		return
	if _speed_timer > 0.0:
		_speed_timer -= delta
		if _speed_timer <= 0.0:
			move_speed = BASE_SPEED
	if _swing_cooldown > 0.0:
		_swing_cooldown -= delta
		if _swing_cooldown <= 0.0:
			GameState.swing_ready_changed.emit(true)
	if state == FState.HIT:
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		move_and_slide()
		return
	if _throw_lock > 0.0:
		_throw_lock -= delta
		velocity.x = 0
		move_and_slide()
		return
	if _swing_lock > 0.0:
		_swing_lock -= delta
		if _swing_lock <= 0.0:
			_swing_box.set_deferred("monitoring", false)
		velocity.x = 0
		move_and_slide()
		return

	# Winding up: rooted like the throw lock, and committed — no walking, no
	# turning, no punching out of it. The only way out is the swing itself.
	if _charging:
		var was_ready := _charge_t >= CHARGE_TIME
		_charge_t += delta
		if not was_ready and _charge_t >= CHARGE_TIME \
				and is_instance_valid(_charge_swoosh):
			_charge_swoosh.mark_charged()
		if Input.is_action_just_released("swing") or _charge_t >= CHARGE_MAX:
			_release_swing()
		velocity.x = 0
		move_and_slide()
		return

	set_ducking(Input.is_action_pressed("duck"))
	if state == FState.DUCK:
		return

	if Input.is_action_just_pressed("throw") and _try_throw():
		return
	if Input.is_action_just_pressed("swing") and _begin_charge():
		return
	if Input.is_action_just_pressed("punch"):
		try_attack(FState.PUNCH)
	elif Input.is_action_just_pressed("kick"):
		try_attack(FState.KICK)
	if Input.is_action_just_pressed("interact"):
		interact_pressed.emit()

	apply_locomotion(Input.get_axis("move_left", "move_right"))


## Throw a beer bottle forward at head height. Returns true if one was thrown.
func _try_throw() -> bool:
	if not can_act() or not GameState.use_bottle():
		return false
	_throw_lock = 0.35
	velocity.x = 0
	_play("punch")  # reuse the wind-up pose; state stays IDLE so no fist hitbox
	GameState.play_sfx("throw")
	var b := Projectile.new()
	b.hits_enemies = true
	b.position = position + Vector2(facing * 22.0, -40.0)
	b.velocity = Vector2(facing * 320.0, 0.0)
	get_parent().add_child(b)
	return true


## Press the swing button off cooldown: the weapon comes up overhead and STAYS
## there until the button is let go. Returns true if the wind-up started.
## Nothing is committed here — no cooldown, no hitbox, no sound — because the
## swing has not happened yet; this is only the pose.
func _begin_charge() -> bool:
	if not can_act() or _swing_cooldown > 0.0:
		return false
	_charging = true
	_charge_t = 0.0
	velocity.x = 0
	# The punch row is 3 frames at 10fps and does NOT loop, so left running it
	# would settle the body on the recovery frame while the weapon sits up in
	# the air. Paused on frame 0 — arms back, the wind-up — it waits instead,
	# and _try_swing's _play("punch") resumes it from exactly there.
	_play("punch")
	body_sprite.frame = 0
	body_sprite.pause()
	_charge_swoosh = SwingSwoosh.new()
	_charge_swoosh.facing = facing
	_charge_swoosh.weapon = GameState.weapon
	_charge_swoosh.duration = SWING_TIME
	_charge_swoosh.charging = true
	add_child(_charge_swoosh)
	return true


## Button released (or CHARGE_MAX reached): the held weapon drops into its
## sweep. Held past CHARGE_TIME, it lands for CHARGE_MULT damage.
func _release_swing() -> void:
	var charged := _charge_t >= CHARGE_TIME
	var held := _charge_swoosh
	_charging = false
	_charge_t = 0.0
	_charge_swoosh = null
	if _try_swing(charged, held):
		return
	# Can't normally happen (the charge held every state that could refuse),
	# but a refused swing must not leave the weapon hanging overhead.
	if is_instance_valid(held):
		held.queue_free()


## Give up a wind-up with no swing: the pose is left to whatever interrupted
## it, and the raised weapon goes away.
func _cancel_charge() -> void:
	if not _charging:
		return
	_charging = false
	_charge_t = 0.0
	if is_instance_valid(_charge_swoosh):
		_charge_swoosh.queue_free()
	_charge_swoosh = null


## Overhead weapon swing, released from a charge. Returns true if it started.
## `held` is the weapon already raised by the wind-up — it is dropped into the
## sweep rather than a second copy being spawned. Like the throw, state stays
## IDLE (so the fist hitbox never arms) and a lock timer holds the player in
## place for the SWING_TIME.
func _try_swing(charged: bool, held: SwingSwoosh = null) -> bool:
	if not can_act() or _swing_cooldown > 0.0:
		return false
	_swing_lock = SWING_TIME
	_swing_cooldown = SWING_COOLDOWN
	GameState.swing_ready_changed.emit(false)
	velocity.x = 0
	_victims.clear()
	_attack_damage = SWING_DAMAGE * damage_scale
	# The skid decelerates at a constant rate, so distance goes with the SQUARE
	# of launch speed: doubling how far they fly is √2 on the velocity, not 2
	# (which would send them four times as far).
	_attack_knockback = sqrt(CHARGE_KNOCKBACK) if charged else 1.0
	if charged:
		_attack_damage *= CHARGE_MULT
	_swing_box.position = Vector2(SWING_BOX_X * facing, -30)
	_swing_box.monitoring = true
	_play("punch")  # reuse the wind-up pose; the swoosh arc sells the swing
	GameState.play_sfx("swing")  # borrows the throw sample; see SFX_ALIASES
	if is_instance_valid(held):
		held.release()
		return true
	var sw := SwingSwoosh.new()
	sw.facing = facing
	sw.weapon = GameState.weapon
	sw.duration = SWING_TIME
	add_child(sw)
	return true
