class_name ComponentPickup
extends Area2D
## A JOKE CRAFTER component lying on the ground — a SETUP, a PUNCHLINE or a
## TAG. Walk over it to collect it. Spawned on the street and dropped by
## venue bosses.
##
## Spins about its vertical axis rather than bobbing like the beer bottle, so
## the two are tellable apart at a glance even before the colour registers.
##
## Deliberately unlike BeerPickup in three ways, all of them because these are
## not a combat resource: there is NO carry cap (so a pickup never has to be
## left lying there), nothing consumes them during a run, and they are not
## gated behind the first boss. They are a pure tally that ships at game over.

## Tint per kind. The sprites are drawn in one neutral cream so a single set of
## art serves all three; colour is what makes them tellable apart at the ~40px
## they actually appear at in play. Tuning these needs no new art.
const TINTS := {
	"setups": Color(1.0, 1.0, 1.0),
	"punchlines": Color(0.62, 0.90, 1.15),
	"tags": Color(0.72, 1.12, 0.80),
}

## What floats up when one is collected. Singular, and not the plural field
## name the server and the tally use.
const LABELS := {
	"setups": "+SETUP",
	"punchlines": "+PUNCHLINE",
	"tags": "+TAG",
}

## Base sprite scale. Kept as a constant because the spin below drives scale.x
## off it every frame, so it can no longer just be set once in _ready.
const SPRITE_SCALE := 0.85
## Fake-3D spin: the sprite's x scale is driven by a cosine, so it squashes to
## an edge and opens out mirrored — which is how a coin or a card reads as
## turning about its vertical axis. Radians per second.
const SPIN_SPEED := 3.2
## The sprite never fully vanishes at the edge-on point. A true spin would hit
## zero width, but at ~40px on a busy street that reads as flickering out of
## existence rather than as turning, so it keeps a sliver.
const SPIN_MIN := 0.07

const SPRITE_PATH := "res://shared/assets/components/%s.png"
## Basenames are singular; the kind keys are plural (they are the server's
## field names). One place to bridge the two.
const FILES := {"setups": "setup", "punchlines": "punchline", "tags": "tag"}

## Which kind this is. Set before adding to the tree.
var kind := "setups"

var _sprite: Sprite2D
## Spin phase. Randomised per pickup so two on screen at once are never
## turning in lockstep, which would read as one animation on two objects.
var _spin := 0.0


func _ready() -> void:
	add_to_group("component_pickups")
	collision_layer = 0
	collision_mask = 2  # player hurtbox layer, same as BeerPickup
	_sprite = Sprite2D.new()
	var path: String = SPRITE_PATH % String(FILES.get(kind, "setup"))
	if ResourceLoader.exists(path):
		_sprite.texture = load(path)
	# The art is 48x48 and reads best a touch smaller than a beer bottle, which
	# is the one thing on the street it must not be confused with.
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_spin = randf() * TAU
	_sprite.modulate = TINTS.get(kind, Color.WHITE)
	add_child(_sprite)
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(40, 40)
	cs.shape = rs
	add_child(cs)
	area_entered.connect(_on_area_entered)
	_glint()


## Turns on the spot. Only the SPRITE is scaled — the Area2D's collision shape
## is a sibling and keeps its full width, so the pickup is exactly as easy to
## walk into edge-on as face-on. A spin that also narrowed the hitbox would
## make collecting one a timing test, which is not what these are for.
func _process(delta: float) -> void:
	_spin += delta * SPIN_SPEED
	var turn := cos(_spin)
	# signf keeps the mirrored half genuinely mirrored: the sprite flips as it
	# passes edge-on, which is what sells it as the back of the card.
	_sprite.scale.x = SPRITE_SCALE * signf(turn) * maxf(absf(turn), SPIN_MIN)


## Pulses brightness around the kind's tint rather than around white, so the
## glint never washes a punchline or a tag back to cream mid-pulse.
func _glint() -> void:
	var base: Color = TINTS.get(kind, Color.WHITE)
	var tw := create_tween().set_loops()
	tw.tween_property(_sprite, "modulate", base * 1.25, 0.6)
	tw.tween_property(_sprite, "modulate", base, 0.6)


func _on_area_entered(area: Area2D) -> void:
	if not area.has_meta("fighter"):
		return
	if not (area.get_meta("fighter") is Player):
		return
	GameState.add_component(kind)
	FloatingText.spawn(get_parent(), global_position + Vector2(0, -30),
			String(LABELS.get(kind, "+JOKE")), TINTS.get(kind, Color.WHITE))
	GameState.play_sfx("clear")
	queue_free()
