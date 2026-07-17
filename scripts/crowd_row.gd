class_name CrowdRow
extends Node2D
## Foreground audience silhouettes along the bottom edge of a venue. Every slot
## is either an empty chair or a random seated comedy-club patron (guy / guy in
## a cap / girl / girl in a hat); the mix is reshuffled each venue. The row
## reacts to crowd events broadcast by GameState.crowd_reaction:
##   boo       -> throw both arms up (angry) and shake
##   laugh     -> shake only, arms stay down
##   cheer     -> quick arms-up pop (fires on every enemy KO)
##   celebrate -> rise up off the stool and hold an arms-up cheer (venue cleared)
## Empty chairs never react. Missing art = silent no-op, like the SFX system,
## so a city edition without the files simply has no crowd.

const MEMBERS := 6
## The crowd is zoomed WAY in: patrons sit right in front of the camera so only
## their heads/shoulders clear the bottom edge — the torso and stool run off the
## bottom of the screen (clipped by the viewport). Source art is 300px tall.
const SOURCE_H := 300.0
## On-screen scale at the 640-wide design width (grows with the viewport so the
## heads stay proportional on wider phones).
const CROWD_SCALE := 0.92
## Shoulder line sits this many px above the bottom edge, and is ~26% down from
## the top of an arms-down silhouette — so the head clears the edge and the rest
## hangs below off-screen.
const SHOULDER_MARGIN := 2.0
const SHOULDER_FRAC := 0.26
## Empty-chair backrests poke up to this fraction of the view height (a bit
## lower than the heads, so an empty seat reads as a gap in the crowd).
const CHAIR_TOP_FRAC := 0.84
const EMPTY_CHAIR_CHANCE := 0.4
const BASE := "res://shared/assets/crowd/crowd_"
const PERSON_TYPES := ["guy", "guy_hat", "girl", "girl_hat"]
## How far a celebrating patron lifts up, in on-screen pixels.
const CELEBRATE_RISE := 8.0

var _chair_tex: Texture2D
## person type -> {"down": Texture2D, "up": Texture2D}
var _person_tex := {}
var _members: Array = []


func _ready() -> void:
	z_index = 5  # in front of the room (bg is -10) and the fighters (0)
	_load_textures()
	if _person_tex.is_empty() and _chair_tex == null:
		return  # no art shipped for this edition -> no crowd
	_build_row()
	# Auto-disconnected when the venue (and this child) is freed on scene change.
	GameState.crowd_reaction.connect(_on_crowd_reaction)


func _load_textures() -> void:
	_chair_tex = _load(BASE + "chair")
	for t in PERSON_TYPES:
		var d := _load(BASE + t + "_down")
		var u := _load(BASE + t + "_up")
		if d and u:
			_person_tex[t] = {"down": d, "up": u}


func _load(path: String) -> Texture2D:
	var p := path + ".png"
	return load(p) if ResourceLoader.exists(p) else null


func _build_row() -> void:
	var view := get_viewport().get_visible_rect().size
	var scale_f := (view.x / 640.0) * CROWD_SCALE
	var shoulder_y := view.y - SHOULDER_MARGIN
	# People are bottom-centre anchored (origin at the stool base). Placing that
	# base here puts the shoulder line at shoulder_y and lets the body fall off
	# the bottom edge; the taller arms-up frame shares this base so arms rise up.
	var person_base_y := shoulder_y + (1.0 - SHOULDER_FRAC) * SOURCE_H * scale_f
	var chair_top_y := view.y * CHAIR_TOP_FRAC
	var slot := view.x / float(MEMBERS)
	var types: Array = _person_tex.keys()
	for i in MEMBERS:
		var use_chair: bool = types.is_empty() or randf() < EMPTY_CHAIR_CHANCE
		if use_chair and _chair_tex == null:
			use_chair = false
		var m := CrowdMember.new()
		var base_y := person_base_y
		if use_chair:
			m.setup(_chair_tex, null)
			base_y = chair_top_y + _chair_tex.get_height() * scale_f
		else:
			var pt: Dictionary = _person_tex[types[randi() % types.size()]]
			m.setup(pt["down"], pt["up"])
		m.scale = Vector2(scale_f, scale_f)
		m.flip_h = randf() < 0.5  # cheap left/right variety
		# Small horizontal jitter within the slot so the row isn't a rigid grid.
		var x := slot * (i + 0.5) + randf_range(-slot * 0.08, slot * 0.08)
		m.set_home(Vector2(x, base_y))
		add_child(m)
		_members.append(m)


func _on_crowd_reaction(kind: String) -> void:
	for m in _members:
		m.react(kind)


## One audience silhouette. Anchored bottom-centre (via offset) so swapping the
## arms-down and taller arms-up frames keeps the stool planted and the arms rise.
class CrowdMember:
	extends Sprite2D

	var _down: Texture2D
	var _up: Texture2D
	var _home: Vector2      # resting (seated) position
	var _rest: Vector2      # current baseline for shakes (moves when celebrating)
	var _tw: Tween

	func setup(down_tex: Texture2D, up_tex: Texture2D) -> void:
		_down = down_tex
		_up = up_tex
		centered = false
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_show(_down)

	func set_home(p: Vector2) -> void:
		_home = p
		_rest = p
		position = p

	func _show(t: Texture2D) -> void:
		texture = t
		# Bottom-centre anchor: origin sits at the base of the silhouette, so the
		# arms-up frame (taller) grows upward instead of shifting the whole body.
		offset = Vector2(-t.get_width() / 2.0, -float(t.get_height()))

	func _raise(up: bool) -> void:
		if _up == null:
			return  # empty chair: nothing to raise
		_show(_up if up else _down)

	func react(kind: String) -> void:
		if _up == null:
			return  # chairs stay put
		match kind:
			"boo":
				_raise(true)
				_shake(3.0, 0.5, true)
			"laugh":
				_shake(2.0, 0.4, false)
			"cheer":
				_pop()
			"celebrate":
				_celebrate()

	## Random per-member lead-in so a reaction ripples through the row instead
	## of every silhouette snapping in lockstep.
	func _lead() -> float:
		return randf_range(0.0, 0.12)

	func _fresh_tween() -> Tween:
		if _tw and _tw.is_valid():
			_tw.kill()
		_tw = create_tween()
		return _tw

	func _shake(px: float, dur: float, was_raised: bool) -> void:
		var t := _fresh_tween()
		t.tween_interval(_lead())
		var steps := 5
		for i in steps:
			t.tween_property(self, "position",
					_rest + Vector2(randf_range(-px, px), 0.0), dur / steps)
		t.tween_property(self, "position", _rest, dur / steps)
		if was_raised:
			t.tween_callback(func(): _raise(false))

	func _pop() -> void:
		var t := _fresh_tween()
		t.tween_interval(_lead())
		t.tween_callback(func(): _raise(true))
		t.tween_interval(0.35)
		t.tween_callback(func(): _raise(false))

	func _celebrate() -> void:
		var t := _fresh_tween()
		t.tween_interval(_lead())
		t.tween_callback(func(): _raise(true))
		# Pop up off the stool and hold the cheer; the venue clears in ~2s.
		_rest = _home - Vector2(0.0, CELEBRATE_RISE)
		t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(self, "position", _rest, 0.28)
